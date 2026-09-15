// Creating a work context: the account that carries it and its password, its
// home subvolume and the mount of that home, the ownership of the home, and its
// snapshot paths, as `docs/decisions/000-work-contexts-and-accounts.md`,
// `docs/decisions/001-disk-layout.md` and `docs/decisions/004-snapshots.md`
// decide. What it makes is what an installation makes for each context it is
// given.
//
// It works on the machine it runs on, so its commands go to the shell directly,
// which is what a local target would do.

/// The groups a work context's account belongs to beside its own.
function work_context_groups() -> string {
    "wheel,dotfiles,work-contexts"
}

/// `text` with spaces after it up to `width` characters, and as it is when it
/// is already that long.
function padded(text: string, width: int) -> string {
    let out = text;
    while (out.length() < width) {
        out = out + " ";
    }
    out
}

/// A mounted subvolume written as `genfstab -U` writes it, which is how the
/// installation wrote the mounts of the homes it made: the device as a comment,
/// then the filesystem's UUID, the mount point, the type and the options the
/// kernel reports, padded the way it pads them, and a blank line after.
///
/// `subvolid=` is dropped, as `genfstab` drops it beside `subvol=`: the
/// subvolume is named by its path.
function fstab_entry(device: string, uuid: string, mount_point: string, options: string) -> string {
    let kept = options
        .split(",")
        .filter(
            (option) -> {
                !option.starts_with("subvolid=")
            },
        );
    "# " + device + "\n"
        + padded("UUID=" + uuid, 20)
        + "\t" + padded(mount_point, 10)
        + "\t" + padded("btrfs", 10)
        + "\t" + padded(kept.join(","), 10)
        + "\t0 0" + "\n" + "\n"
}

/// Creates `home/@<name>` in the top level of the filesystem, which is mounted
/// for as long as the subvolume takes, and unmounted and its directory removed
/// whether or not the subvolume was made.
function create_home_subvolume(shell: root.common.Shell, device: string, name: string) -> string {
    let top = mount_top_level(shell, device);
    if (top.error != "") {
        return top.error;
    }
    let created = root.common.must(
        shell.capture("btrfs", ["subvolume", "create", `${top.value}/home/@${name}`]),
        `creating the home subvolume of ${name}`);
    joined_failures([created, unmount_top_level(shell, top.value)])
}

/// Creates the work context `name` on this machine, or says why it did not.
///
/// The name is checked before anything is created. The password is the one
/// every work context already has: the account is given the hash an existing
/// work context carries, on standard input, so no secret is given to this and
/// none is on a command line.
function create_work_context(shell: root.common.Shell, files: root.common.Files, name: string) -> string {
    let invalid = root.common.work_context_name_error(name);
    if (invalid != "") {
        return invalid;
    }

    let contexts = list_work_contexts(shell);
    if (contexts.error != "") {
        return contexts.error;
    }
    let existing = contexts.names.at(0) ?? "";
    let shadow = shell.capture("getent", ["shadow", existing]);
    let unread = root.common.must(shadow, `reading the password of ${existing}`);
    if (unread != "") {
        return unread;
    }
    let hash = shadow.stdout.trim().split(":").at(1) ?? "";

    let home = `/home/${name}`;
    let account = root.common.must(
        shell.capture("useradd", ["-M", "-d", home, "-G", work_context_groups(), "-s", "/bin/bash", name]),
        `creating the account ${name}`);
    if (account != "") {
        return account;
    }
    let password = root.common.must(shell.feed("chpasswd", ["-e"], `${name}:${hash}` + "\n"),
                                    `setting the password of ${name}`);
    if (password != "") {
        return password;
    }

    let found = root_device(shell);
    if (found.error != "") {
        return found.error;
    }
    let device = found.value;

    let subvolume = create_home_subvolume(shell, device, name);
    if (subvolume != "") {
        return subvolume;
    }

    files.mkdir(home);
    if let failure: string = files.failure() {
        return failure;
    }
    let mounted = root.common.must(shell.capture("mount", ["-o", `subvol=home/@${name}`, device, home]),
                                   `mounting the home of ${name}`);
    if (mounted != "") {
        return mounted;
    }

    //# what the mount table says about the home is what the kernel says about
    //# the mount that was just made, which is where `genfstab` reads it from
    let uuid = shell.capture("lsblk", ["-rno", "UUID", device]);
    let no_uuid = root.common.must(uuid, `reading the UUID of ${device}`);
    if (no_uuid != "") {
        return no_uuid;
    }
    let options = shell.capture("findmnt", ["-nro", "OPTIONS", "--mountpoint", home]);
    let no_options = root.common.must(options, `reading the mount options of ${home}`);
    if (no_options != "") {
        return no_options;
    }
    root.common.append_to_file(files, "/etc/fstab",
                               fstab_entry(device, uuid.stdout.trim(), home, options.stdout.trim()));

    let owned = root.common.must(shell.capture("chown", ["-R", `${name}:${name}`, home]),
                                 `taking ownership of the home of ${name}`);
    if (owned != "") {
        return owned;
    }

    files.mkdir(`/snapshots/home/${name}/automatic`);
    files.mkdir(`/snapshots/home/${name}/manual`);
    files.failure() ?? ""
}

// -------------------------------------------------------------------- tests

function creating_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        replies: {
            "getent group work-contexts": "work-contexts:x:1002:personal,work\n",
            "getent shadow personal": "personal:$6$pepper$c2hhcmVkLXNlY3JldA:20345:0:99999:7:::\n",
            "findmnt -nvo SOURCE /": "/dev/mapper/cryptroot\n",
            "mktemp -d": "/tmp/tmp.oparch\n",
            "lsblk -rno UUID /dev/mapper/cryptroot": "5ab108d8-d24b-485f-bbc0-9491a6c228db\n",
            "findmnt -nro OPTIONS --mountpoint /home/project":
                "rw,relatime,ssd,space_cache=v2,subvolid=262,subvol=/home/@project\n",
        },
        exit_codes: {},
    }
}

function machine_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/etc/fstab", "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/         \tbtrfs     \trw,relatime,ssd,space_cache=v2,subvol=/@\t0 0\n\n");
    files
}

test "a work context is created the way an installation creates one" {
    let shell = creating_shell();
    let files = machine_files();

    assert.equal(create_work_context(shell, files, "project"), "");

    assert.equal(shell.commands, [
        "getent group work-contexts",
        "getent shadow personal",
        "useradd -M -d /home/project -G wheel,dotfiles,work-contexts -s /bin/bash project",
        "chpasswd -e",
        "findmnt -nvo SOURCE /",
        "mktemp -d",
        "mount -o subvolid=5 /dev/mapper/cryptroot /tmp/tmp.oparch",
        "btrfs subvolume create /tmp/tmp.oparch/home/@project",
        "umount /tmp/tmp.oparch",
        "rmdir /tmp/tmp.oparch",
        "mount -o subvol=home/@project /dev/mapper/cryptroot /home/project",
        "lsblk -rno UUID /dev/mapper/cryptroot",
        "findmnt -nro OPTIONS --mountpoint /home/project",
        "chown -R project:project /home/project",
    ]);
    assert.equal(files.directories, [
        "/home/project", "/snapshots/home/project/automatic", "/snapshots/home/project/manual",
    ])
}

test "the password is taken as a hash on standard input and never on a command line" {
    let shell = creating_shell();

    let _ = create_work_context(shell, machine_files(), "project");

    assert.equal(shell.fed, ["chpasswd -e"]);
    assert.is_true(!shell.commands.join(" ").includes("c2hhcmVkLXNlY3JldA"))
}

test "the home's mount is added to the mount table as genfstab writes one" {
    let files = machine_files();

    let _ = create_work_context(creating_shell(), files, "project");

    assert.equal(files.written.get("/etc/fstab"),
                 "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/         \tbtrfs     \trw,relatime,ssd,space_cache=v2,subvol=/@\t0 0\n\n"
                     + "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/home/project\tbtrfs     \trw,relatime,ssd,space_cache=v2,subvol=/home/@project\t0 0\n\n")
}

test "a short mount point is padded the way genfstab pads it" {
    assert.equal(fstab_entry("/dev/mapper/cryptroot", "5ab108d8-d24b-485f-bbc0-9491a6c228db", "/home/a",
                             "rw,relatime,subvolid=300,subvol=/home/@a"),
                 "# /dev/mapper/cryptroot\nUUID=5ab108d8-d24b-485f-bbc0-9491a6c228db\t/home/a   \tbtrfs     \trw,relatime,subvol=/home/@a\t0 0\n\n")
}

test "a name that cannot be a work context's creates nothing" {
    let shell = creating_shell();
    let files = machine_files();

    assert.equal(create_work_context(shell, files, "Project"), "Invalid work context name: Project");
    assert.equal(create_work_context(shell, files, "system"), "Work context name 'system' is reserved.");
    assert.equal(shell.commands, []);
    assert.equal(files.directories, [])
}

test "an account that cannot be created stops before the disk is touched" {
    let shell = creating_shell();
    let _ = shell.exit_codes.set(
        "useradd -M -d /home/project -G wheel,dotfiles,work-contexts -s /bin/bash project", 9);

    assert.equal(create_work_context(shell, machine_files(), "project"),
                 "creating the account project failed with exit code 9.");
    assert.is_true(!shell.commands.includes("chpasswd -e"));
    assert.is_true(!shell.commands.includes("mktemp -d"))
}

test "the top level is unmounted and its directory removed when the subvolume cannot be made" {
    let shell = creating_shell();
    let _ = shell.exit_codes.set("btrfs subvolume create /tmp/tmp.oparch/home/@project", 1);
    let files = machine_files();

    assert.equal(create_work_context(shell, files, "project"),
                 "creating the home subvolume of project failed with exit code 1.");
    assert.is_true(shell.commands.includes("umount /tmp/tmp.oparch"));
    assert.is_true(shell.commands.includes("rmdir /tmp/tmp.oparch"));
    //# nothing is mounted at the home and nothing is added to the mount table
    assert.is_true(!shell.commands.includes("mount -o subvol=home/@project /dev/mapper/cryptroot /home/project"));
    assert.equal(files.directories, [])
}

test "a top level that cannot be mounted leaves no directory behind" {
    let shell = creating_shell();
    let _ = shell.exit_codes.set("mount -o subvolid=5 /dev/mapper/cryptroot /tmp/tmp.oparch", 32);

    assert.equal(create_work_context(shell, machine_files(), "project"),
                 "mounting the top level of the filesystem failed with exit code 32.");
    assert.is_true(shell.commands.includes("rmdir /tmp/tmp.oparch"));
    assert.is_true(!shell.commands.includes("btrfs subvolume create /tmp/tmp.oparch/home/@project"))
}

test "a top level that cannot be unmounted is reported, and its directory is left to it" {
    let shell = creating_shell();
    let _ = shell.exit_codes.set("umount /tmp/tmp.oparch", 32);

    assert.equal(create_work_context(shell, machine_files(), "project"),
                 "unmounting the top level of the filesystem failed with exit code 32.");
    assert.is_true(!shell.commands.includes("rmdir /tmp/tmp.oparch"))
}
