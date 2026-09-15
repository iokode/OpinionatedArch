// Removing a work context: what creating one made — the account, the home
// subvolume, its mount and its line in the mount table — and the snapshots of
// its home, unless they are kept. Its home can be copied into the home of
// another work context first.

/// What removing a work context is asked for.
class Removal {
    name: string,
    /// The work context whose home receives a copy of the removed home, or ""
    /// for no copy.
    preserve_home: string,
    /// Whether the snapshot scope of the removed context is left as it is.
    preserve_snapshots: bool,
}

/// What removing a work context did: where the home was copied to, "" when it
/// was not, or what stopped the removal.
class Removed {
    copy: string,
    error: string,
}

/// The directory, inside the home of the work context that keeps them, that
/// holds the homes of removed work contexts.
function preserved_homes_directory(target: string) -> string {
    `/home/${target}/other-contexts-home-data`
}

/// Where the home of a removed work context is copied to: the directory named
/// after it when that name is free, and otherwise the name followed by `-0`,
/// `-1` and on, the first of them that is free.
function preserved_home_path(files: root.common.Files, target: string, removed: string) -> string {
    let named = `${preserved_homes_directory(target)}/${removed}`;
    if (!files.exists(named)) {
        return named;
    }
    let index = 0;
    while (files.exists(`${named}-${index}`)) {
        index = index + 1;
    }
    `${named}-${index}`
}

/// A mount table without the entry that mounts `mount_point`, and without what
/// `genfstab` writes around an entry: the comment line above it, naming the
/// device, and the blank line below it. Every other line stays as it was.
function without_fstab_entry(fstab: string, mount_point: string) -> string {
    let kept: string[] = [];
    let comment = "";
    let has_comment = false;
    let after_entry = false;
    for (let line in fstab.lines()) {
        if (after_entry) {
            after_entry = false;
            if (line.trim() == "") {
                continue;
            }
        }
        let is_comment = line.trim().starts_with("#");
        let fields = root.common.split_fields(line.split("\t").join(" "));
        if (!is_comment && (fields.at(1) ?? "") == mount_point) {
            has_comment = false;
            after_entry = true;
            continue;
        }
        if (has_comment) {
            kept.push(comment);
            has_comment = false;
        }
        if (is_comment) {
            comment = line;
            has_comment = true;
        } else {
            kept.push(line);
        }
    }
    if (has_comment) {
        kept.push(comment);
    }
    if (kept.length() == 0) {
        return "";
    }
    kept.join("\n") + "\n"
}

/// Removes every snapshot of a work context's home, each as
/// `oparch-snapshot-remove` removes one, under the lock and with its label, and
/// then the directories of the scope.
function remove_snapshot_scope(shell: root.common.Shell, files: root.common.Files,
                               lock: root.snapshot.SnapshotLock, name: string) -> string {
    let listing = root.snapshot.list_snapshots(files, root.snapshot.SnapshotFilter {
        scope: "home", work_context: name, since: null, until: null,
    });
    if (listing.error != "") {
        return listing.error;
    }
    for (let snapshot in listing.snapshots) {
        let removed = root.snapshot.remove_snapshot(shell, files, lock, snapshot.path);
        if (removed != "") {
            return removed;
        }
    }
    let scope = root.snapshot.in_snapshots(`home/${name}`);
    let directories = [`${scope}/${root.snapshot.automatic_kind()}`, `${scope}/${root.snapshot.manual_kind()}`, scope];
    for (let directory in directories) {
        let removed = root.common.must(shell.capture("rmdir", [directory]), `removing ${directory}`);
        if (removed != "") {
            return removed;
        }
    }
    ""
}

/// Copies the home of `name` into the home of `target`, at the first free path,
/// and gives the copy to `target`, and the directory that holds it too when
/// this is what creates that directory. The path of the copy, or what failed.
function copy_home(shell: root.common.Shell, files: root.common.Files, name: string, target: string) -> Removed {
    let holder = preserved_homes_directory(target);
    let holder_is_new = !files.exists(holder);
    let copy = preserved_home_path(files, target, name);
    files.mkdir(copy);
    if let failure: string = files.failure() {
        return Removed { copy: "", error: failure };
    }
    if (holder_is_new) {
        let held = root.common.must(shell.capture("chown", [`${target}:${target}`, holder]),
                                    `giving ${holder} to ${target}`);
        if (held != "") {
            return Removed { copy: "", error: held };
        }
    }
    let copied = root.common.must(shell.capture("cp", ["-a", `/home/${name}/.`, copy]),
                                  `copying the home of ${name} to ${copy}`);
    if (copied != "") {
        return Removed { copy: "", error: copied };
    }
    let given = root.common.must(shell.capture("chown", ["-R", `${target}:${target}`, copy]),
                                 `giving ${copy} to ${target}`);
    if (given != "") {
        return Removed { copy: "", error: given };
    }
    Removed { copy: copy, error: "" }
}

/// Why a removal cannot be done on a machine whose work contexts are `names`,
/// or "" when it can: the context removed, and the one given its home, have to
/// be work contexts of the machine; the one removed cannot be the last; and its
/// home cannot be given to itself.
function removal_problem(names: string[], removal: Removal) -> string {
    let name = removal.name;
    let target = removal.preserve_home;
    if (!names.includes(name)) {
        return `'${name}' is not a work context of this machine`;
    }
    if (names.length() == 1) {
        return `'${name}' is the last work context of this machine`;
    }
    if (target == name) {
        return `the home of '${name}' cannot be kept in the home of the work context being removed`;
    }
    if (target != "" && !names.includes(target)) {
        return `'${target}' is not a work context of this machine`;
    }
    ""
}

/// Removes a work context from this machine. It stops at the first step that
/// fails, and what was done before that stays done. What is asked is checked
/// before anything is done, as `removal_problem` checks it.
function remove_work_context(shell: root.common.Shell, files: root.common.Files,
                             lock: root.snapshot.SnapshotLock, removal: Removal) -> Removed {
    let name = removal.name;
    let target = removal.preserve_home;
    let contexts = list_work_contexts(shell);
    if (contexts.error != "") {
        return Removed { copy: "", error: contexts.error };
    }
    let problem = removal_problem(contexts.names, removal);
    if (problem != "") {
        return Removed { copy: "", error: problem };
    }

    let copy = "";
    if (target != "") {
        let copied = copy_home(shell, files, name, target);
        if (copied.error != "") {
            return copied;
        }
        copy = copied.copy;
    }

    let home = `/home/${name}`;
    let unmounted = root.common.must(shell.capture("umount", [home]), `unmounting the home of ${name}`);
    if (unmounted != "") {
        return Removed { copy: copy, error: unmounted };
    }
    let account = root.common.must(shell.capture("userdel", [name]), `removing the account ${name}`);
    if (account != "") {
        return Removed { copy: copy, error: account };
    }

    let table = files.read("/etc/fstab");
    if (table == null) {
        return Removed { copy: copy, error: "cannot read /etc/fstab" };
    }
    files.write("/etc/fstab", without_fstab_entry(table ?? "", home));
    if let failure: string = files.failure() {
        return Removed { copy: copy, error: failure };
    }
    let mount_point = root.common.must(shell.capture("rmdir", [home]), `removing ${home}`);
    if (mount_point != "") {
        return Removed { copy: copy, error: mount_point };
    }

    let device = root_device(shell);
    if (device.error != "") {
        return Removed { copy: copy, error: device.error };
    }
    let top = mount_top_level(shell, device.value);
    if (top.error != "") {
        return Removed { copy: copy, error: top.error };
    }
    let deleted = root.common.must(
        shell.capture("btrfs", ["subvolume", "delete", `${top.value}/home/@${name}`]),
        `deleting the home subvolume of ${name}`);
    let subvolume = joined_failures([deleted, unmount_top_level(shell, top.value)]);
    if (subvolume != "") {
        return Removed { copy: copy, error: subvolume };
    }

    if (removal.preserve_snapshots) {
        return Removed { copy: copy, error: "" };
    }
    Removed { copy: copy, error: remove_snapshot_scope(shell, files, lock, name) }
}

// -------------------------------------------------------------------- tests

function machine_fstab() -> string {
    "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/         \tbtrfs     \trw,relatime,subvol=/@\t0 0\n\n"
        + "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/home/project\tbtrfs     \trw,relatime,subvol=/home/@project\t0 0\n\n"
        + "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/home/personal\tbtrfs     \trw,relatime,subvol=/home/@personal\t0 0\n\n"
        + "/swap/swapfile none swap defaults 0 0\n"
}

function removing_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        replies: {
            "getent group work-contexts": "work-contexts:x:1002:personal,project\n",
            "findmnt -nvo SOURCE /": "/dev/mapper/cryptroot\n",
            "mktemp -d": "/tmp/tmp.oparch\n",
        },
        exit_codes: {},
    }
}

/// A machine whose `project` context has an automatic and a labelled manual
/// snapshot of its home, beside a system snapshot that stays.
function removing_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/etc/fstab", machine_fstab());
    files.mkdir("/snapshots/home/project/automatic/@1778761600");
    files.mkdir("/snapshots/home/project/manual/@1778765200");
    files.mkdir("/snapshots/home/project/automatic");
    files.mkdir("/snapshots/home/project/manual");
    files.write("/snapshots/labels.json",
                "{\"home/project/manual/@1778765200\":\"before the photo library cleanup\",\"system/manual/@1778764800\":\"a clean base install\"}\n");
    files
}

function removal_of(name: string) -> Removal {
    Removal { name: name, preserve_home: "", preserve_snapshots: false }
}

test "a work context is removed with its mount, its account, its home and its snapshots" {
    let shell = removing_shell();
    let files = removing_files();

    let removed = remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal_of("project"));

    assert.equal(removed.error, "");
    assert.equal(removed.copy, "");
    assert.equal(shell.commands, [
        "getent group work-contexts",
        "umount /home/project",
        "userdel project",
        "rmdir /home/project",
        "findmnt -nvo SOURCE /",
        "mktemp -d",
        "mount -o subvolid=5 /dev/mapper/cryptroot /tmp/tmp.oparch",
        "btrfs subvolume delete /tmp/tmp.oparch/home/@project",
        "umount /tmp/tmp.oparch",
        "rmdir /tmp/tmp.oparch",
        "lock /snapshots/lock",
        "btrfs subvolume delete /snapshots/home/project/automatic/@1778761600",
        "unlock /snapshots/lock",
        "lock /snapshots/lock",
        "btrfs subvolume delete /snapshots/home/project/manual/@1778765200",
        "unlock /snapshots/lock",
        "rmdir /snapshots/home/project/automatic",
        "rmdir /snapshots/home/project/manual",
        "rmdir /snapshots/home/project",
    ]);
    let labels = root.snapshot.read_labels(files);
    assert.equal(labels.entries.get("home/project/manual/@1778765200"), null);
    assert.equal(labels.entries.get("system/manual/@1778764800"), "a clean base install")
}

test "the mount table loses the entry of the removed home and nothing else" {
    let files = removing_files();
    let shell = removing_shell();

    let _ = remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal_of("project"));

    assert.equal(files.written.get("/etc/fstab"),
                 "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/         \tbtrfs     \trw,relatime,subvol=/@\t0 0\n\n"
                     + "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/home/personal\tbtrfs     \trw,relatime,subvol=/home/@personal\t0 0\n\n"
                     + "/swap/swapfile none swap defaults 0 0\n")
}

test "an entry for a mount point that only starts like the home is not the home's" {
    let fstab = "UUID=a\t/home/project-archive\tbtrfs\tsubvol=/home/@project-archive\t0 0\n";

    assert.equal(without_fstab_entry(fstab, "/home/project"), fstab)
}

test "a home that is kept is copied into the other context's home and given to it before anything is removed" {
    let shell = removing_shell();
    let files = removing_files();
    let removal = removal_of("project");
    removal.preserve_home = "personal";

    let removed = remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal);

    assert.equal(removed.error, "");
    assert.equal(removed.copy, "/home/personal/other-contexts-home-data/project");
    //# the directory that holds the copy is new, so it is given to the context
    //# that keeps it too
    assert.equal(shell.commands.slice(0, 5), [
        "getent group work-contexts",
        "chown personal:personal /home/personal/other-contexts-home-data",
        "cp -a /home/project/. /home/personal/other-contexts-home-data/project",
        "chown -R personal:personal /home/personal/other-contexts-home-data/project",
        "umount /home/project",
    ]);
    assert.is_true(files.directories.includes("/home/personal/other-contexts-home-data/project"))
}

test "a copy whose name is taken goes to the first free name after it, in a directory that is left as it was" {
    let shell = removing_shell();
    let files = removing_files();
    files.mkdir("/home/personal/other-contexts-home-data");
    files.mkdir("/home/personal/other-contexts-home-data/project");
    files.mkdir("/home/personal/other-contexts-home-data/project-0");
    let removal = removal_of("project");
    removal.preserve_home = "personal";

    let removed = remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal);

    assert.equal(removed.error, "");
    assert.equal(removed.copy, "/home/personal/other-contexts-home-data/project-1");
    assert.equal(shell.commands.slice(0, 3), [
        "getent group work-contexts",
        "cp -a /home/project/. /home/personal/other-contexts-home-data/project-1",
        "chown -R personal:personal /home/personal/other-contexts-home-data/project-1",
    ])
}

test "the first free name is the one after the removed context's own" {
    let files = root.common.recording_files();
    assert.equal(preserved_home_path(files, "personal", "project"), "/home/personal/other-contexts-home-data/project");
    files.mkdir("/home/personal/other-contexts-home-data/project");
    assert.equal(preserved_home_path(files, "personal", "project"), "/home/personal/other-contexts-home-data/project-0")
}

test "snapshots that are kept are not touched" {
    let shell = removing_shell();
    let files = removing_files();
    let removal = removal_of("project");
    removal.preserve_snapshots = true;

    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal).error, "");

    assert.is_true(!shell.commands.join("\n").includes("/snapshots"));
    assert.equal(root.snapshot.read_labels(files).entries.get("home/project/manual/@1778765200"),
                 "before the photo library cleanup")
}

test "an account that is not a work context, or a home given to one, is refused before anything is done" {
    let shell = removing_shell();
    let files = removing_files();

    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal_of("root")).error,
                 "'root' is not a work context of this machine");
    let removal = removal_of("project");
    removal.preserve_home = "http";
    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal).error,
                 "'http' is not a work context of this machine");

    assert.equal(shell.commands, ["getent group work-contexts", "getent group work-contexts"]);
    assert.equal(files.written.get("/etc/fstab"), machine_fstab())
}

test "the last work context of the machine is refused before anything is done" {
    let shell = removing_shell();
    let _ = shell.replies.set("getent group work-contexts", "work-contexts:x:1002:project\n");
    let files = removing_files();

    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal_of("project")).error,
                 "'project' is the last work context of this machine");
    assert.equal(shell.commands, ["getent group work-contexts"]);
    assert.equal(files.written.get("/etc/fstab"), machine_fstab())
}

test "a home given to the context being removed is refused before anything is done" {
    let shell = removing_shell();
    let files = removing_files();
    let removal = removal_of("project");
    removal.preserve_home = "project";

    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal).error,
                 "the home of 'project' cannot be kept in the home of the work context being removed");
    assert.equal(shell.commands, ["getent group work-contexts"]);
    assert.equal(files.directories.includes("/home/project/other-contexts-home-data/project"), false)
}

test "a home that cannot be unmounted stops the removal before the account or the mount table are touched" {
    let shell = removing_shell();
    let _ = shell.exit_codes.set("umount /home/project", 32);
    let files = removing_files();

    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal_of("project")).error,
                 "unmounting the home of project failed with exit code 32.");
    assert.is_true(!shell.commands.includes("userdel project"));
    assert.equal(files.written.get("/etc/fstab"), machine_fstab())
}

test "a snapshot that cannot be removed leaves the directories of the scope" {
    let shell = removing_shell();
    let _ = shell.exit_codes.set("btrfs subvolume delete /snapshots/home/project/manual/@1778765200", 1);
    let files = removing_files();

    assert.equal(remove_work_context(shell, files, root.snapshot.recording_lock(shell), removal_of("project")).error,
                 "deleting the snapshot /snapshots/home/project/manual/@1778765200 failed with exit code 1.");
    assert.is_true(!shell.commands.includes("rmdir /snapshots/home/project"))
}
