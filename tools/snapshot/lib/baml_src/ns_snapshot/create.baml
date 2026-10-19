// Taking a snapshot: the subvolume of its scope, read only, named after the
// moment it was taken, and what goes with it.

/// A snapshot that was taken, as the path it is reached at, or what stopped it.
class Taken {
    path: string,
    error: string,
}

/// The moment a snapshot is taken, in seconds since the Unix epoch, or what
/// stopped it from being read.
class Moment {
    seconds: int,
    error: string,
}

function read_moment(shell: root.common.Shell) -> Moment {
    let date = shell.capture("date", ["+%s"]);
    let problem = failed(date, "reading the time");
    if (problem != "") {
        return Moment { seconds: 0, error: problem };
    }
    if let seconds: int = root.common.parse_int(date.stdout.trim()) {
        return Moment { seconds: seconds, error: "" };
    }
    Moment { seconds: 0, error: `reading the time gave '${date.stdout.trim()}', which is not a number of seconds` }
}

/// Takes a snapshot of `@`, with the boot artifacts of that moment, holding the
/// lock from before the moment is read until the last file is written.
function take_system_snapshot(shell: root.common.Shell, files: root.common.Files, lock: SnapshotLock,
                              kind: string, justification: string) -> Taken {
    if (kind == manual_kind()) {
        let refused = check_justification(justification);
        if (refused != "") {
            return Taken { path: "", error: refused };
        }
    }
    let locked = lock.acquire();
    if (locked != "") {
        return Taken { path: "", error: locked };
    }
    let taken = take_system_snapshot_holding_lock(shell, files, kind, justification);
    lock.release();
    taken
}

/// The snapshot itself, once the lock is held.
///
/// The set of boot artifacts is stored before the snapshot is taken and the
/// snapshot is paired with it in the table once it has been, so the table
/// never names a snapshot that is not there. A manual snapshot is labelled
/// last.
function take_system_snapshot_holding_lock(shell: root.common.Shell, files: root.common.Files,
                                           kind: string, justification: string) -> Taken {
    let moment = read_moment(shell);
    if (moment.error != "") {
        return Taken { path: "", error: moment.error };
    }
    let relative = system_snapshot_path(kind, snapshot_name(moment.seconds));
    let path = in_snapshots(relative);

    let set = hash_boot_set(shell, files, boot_directory());
    if (set.error != "") {
        return Taken { path: "", error: set.error };
    }
    let stored = store_boot_set(shell, files, boot_directory(), set.hash);
    if (stored != "") {
        return Taken { path: "", error: stored };
    }

    let snapshot = failed(shell.capture("btrfs", ["subvolume", "snapshot", "-r", "/", path]),
                          `taking the snapshot ${path}`);
    if (snapshot != "") {
        return Taken { path: "", error: snapshot };
    }
    root.common.append_to_file(files, in_snapshots(boot_table_path()), boot_table_line(relative, set.hash));
    if let problem: string = files.failure() {
        return Taken { path: path, error: problem };
    }

    if (kind == manual_kind()) {
        let labelled = write_label(files, relative, justification);
        if (labelled != "") {
            return Taken { path: path, error: labelled };
        }
    }
    Taken { path: path, error: "" }
}

/// Takes a snapshot of the home of a work context: the subvolume mounted at
/// its home, which is what makes it a scope of its own.
///
/// A manual snapshot is labelled once it has been taken, and holds the lock
/// from before the moment is read until its label is written. An automatic one
/// writes nothing the lock covers, so it does not take it.
function take_home_snapshot(shell: root.common.Shell, files: root.common.Files, lock: SnapshotLock,
                            work_context: string, kind: string, justification: string) -> Taken {
    if (kind != manual_kind()) {
        return take_home_snapshot_holding_lock(shell, files, work_context, kind, justification);
    }
    let refused = check_justification(justification);
    if (refused != "") {
        return Taken { path: "", error: refused };
    }
    let locked = lock.acquire();
    if (locked != "") {
        return Taken { path: "", error: locked };
    }
    let taken = take_home_snapshot_holding_lock(shell, files, work_context, kind, justification);
    lock.release();
    taken
}

/// The snapshot of a home itself, once whatever lock it needs is held.
function take_home_snapshot_holding_lock(shell: root.common.Shell, files: root.common.Files,
                                         work_context: string, kind: string, justification: string) -> Taken {
    let moment = read_moment(shell);
    if (moment.error != "") {
        return Taken { path: "", error: moment.error };
    }
    let relative = home_snapshot_path(work_context, kind, snapshot_name(moment.seconds));
    let path = in_snapshots(relative);

    let snapshot = failed(shell.capture("btrfs",
                              ["subvolume", "snapshot", "-r", home_directory(work_context), path]),
                          `taking the snapshot ${path}`);
    if (snapshot != "") {
        return Taken { path: "", error: snapshot };
    }

    if (kind == manual_kind()) {
        let labelled = write_label(files, relative, justification);
        if (labelled != "") {
            return Taken { path: path, error: labelled };
        }
    }
    Taken { path: path, error: "" }
}

test "a manual snapshot of a home is taken of its subvolume and labelled" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: { "date +%s": "1778765100\n" },
    };

    let taken = take_home_snapshot(shell, files, recording_lock(shell), "work", manual_kind(),
                                   "before the client project import");

    assert.equal(taken.error, "");
    assert.equal(taken.path, "/snapshots/home/work/manual/@1778765100");
    //# a home carries no boot artifacts, so nothing but the moment and the
    //# snapshot is asked of the machine, and the table is not touched
    assert.equal(shell.commands, [
        "lock /snapshots/lock",
        "date +%s",
        "btrfs subvolume snapshot -r /home/work /snapshots/home/work/manual/@1778765100",
        "unlock /snapshots/lock",
    ]);
    assert.equal(files.written.get("/snapshots/boot/table"), null);
    assert.equal(read_labels(files).entries.get("home/work/manual/@1778765100"), "before the client project import")
}

test "a home that cannot be snapshotted is never labelled" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [],
        replies: { "date +%s": "1778765100\n" },
        exit_codes: { "btrfs subvolume snapshot -r /home/nobody /snapshots/home/nobody/manual/@1778765100": 1 },
    };

    let taken = take_home_snapshot(shell, files, recording_lock(shell), "nobody", manual_kind(),
                                   "before the client project import");

    assert.equal(taken.error, "taking the snapshot /snapshots/home/nobody/manual/@1778765100 failed with exit code 1.");
    assert.equal(files.written.get("/snapshots/labels.json"), null)
}

test "a manual snapshot of a home with no justification is refused before anything is done" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    let taken = take_home_snapshot(shell, files, recording_lock(shell), "work", manual_kind(), "\t");

    assert.equal(taken.error, "a manual snapshot needs a justification, and this one is empty");
    assert.equal(shell.commands, [])
}

test "an automatic snapshot of a home takes no lock and no label" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: { "date +%s": "1778761500\n" },
    };

    let taken = take_home_snapshot(shell, files, recording_lock(shell), "work", automatic_kind(), "");

    assert.equal(taken.error, "");
    assert.equal(shell.commands, [
        "date +%s",
        "btrfs subvolume snapshot -r /home/work /snapshots/home/work/automatic/@1778761500",
    ]);
    assert.equal(files.written.get("/snapshots/labels.json"), null)
}

/// A machine whose EFI system partition holds a kernel and GRUB, with the
/// answers a snapshot of it is given.
function boot_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.mkdir("/boot");
    files.mkdir("/boot/OpinionatedArch");
    files.write("/boot/OpinionatedArch/vmlinuz-linux", "kernel");
    files.write("/boot/grubx64.efi", "grub");
    files
}

function boot_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: {
            "date +%s": "1778764800\n",
            "sha256sum -- /boot/OpinionatedArch/vmlinuz-linux /boot/grubx64.efi":
                "2c6d281a7198da35893e6b5bfcb1fc2d3499169c27055adc47430645652f2050  /boot/OpinionatedArch/vmlinuz-linux\n"
                + "2d07898b568b0949d5863b8d4949b3f2d505c9c36e80426d72897a66c41f46be  /boot/grubx64.efi\n",
            "sha256sum": "1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732  -\n",
            "mktemp -d -p /snapshots/boot": "/snapshots/boot/tmp.Xq3v9TzL1a\n",
        },
    }
}

test "a manual system snapshot takes its boot artifacts, is paired with them and is labelled, under the lock" {
    let files = boot_files();
    let shell = boot_shell();

    let taken = take_system_snapshot(shell, files, recording_lock(shell), manual_kind(), "before a kernel upgrade");

    assert.equal(taken.error, "");
    assert.equal(taken.path, "/snapshots/system/manual/@1778764800");
    assert.equal(shell.commands, [
        "lock /snapshots/lock",
        "date +%s",
        "sha256sum -- /boot/OpinionatedArch/vmlinuz-linux /boot/grubx64.efi",
        "sha256sum",
        "mktemp -d -p /snapshots/boot",
        "cp -r /boot/. /snapshots/boot/tmp.Xq3v9TzL1a",
        "mv -T /snapshots/boot/tmp.Xq3v9TzL1a /snapshots/boot/1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732",
        "btrfs subvolume snapshot -r / /snapshots/system/manual/@1778764800",
        "unlock /snapshots/lock",
    ]);
    assert.equal(files.written.get("/snapshots/boot/table"),
                 "system/manual/@1778764800 1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732\n");
    assert.equal(read_labels(files).entries.get("system/manual/@1778764800"), "before a kernel upgrade")
}

test "a system snapshot is added to the table beside the ones already in it" {
    let files = boot_files();
    files.write("/snapshots/boot/table",
                "system/automatic/@1778764800 1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732\n");
    files.mkdir("/snapshots/boot/1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732");
    let shell = boot_shell();

    let taken = take_system_snapshot(shell, files, recording_lock(shell), manual_kind(), "a clean base install");

    assert.equal(taken.error, "");
    //# the set was there, so nothing was copied
    assert.is_true(!shell.commands.join("\n").includes("cp -r"));
    //# an automatic and a manual snapshot taken in the same second share a
    //# name, and their paths are what tell their lines apart
    assert.equal(files.written.get("/snapshots/boot/table"),
                 "system/automatic/@1778764800 1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732\n"
                 + "system/manual/@1778764800 1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732\n")
}

test "a manual snapshot with no justification is refused before anything is done" {
    let files = boot_files();
    let shell = boot_shell();

    let taken = take_system_snapshot(shell, files, recording_lock(shell), manual_kind(), "");

    assert.equal(taken.error, "a manual snapshot needs a justification, and this one is empty");
    assert.equal(shell.commands, [])
}

test "a snapshot that cannot be taken is never put in the table, and the lock is given back" {
    let files = boot_files();
    let shell = boot_shell();
    let _ = shell.exit_codes.set("btrfs subvolume snapshot -r / /snapshots/system/manual/@1778764800", 1);

    let taken = take_system_snapshot(shell, files, recording_lock(shell), manual_kind(), "before a kernel upgrade");

    assert.equal(taken.error, "taking the snapshot /snapshots/system/manual/@1778764800 failed with exit code 1.");
    assert.equal(files.written.get("/snapshots/boot/table"), null);
    assert.equal(files.written.get("/snapshots/labels.json"), null);
    assert.equal(shell.commands.at(shell.commands.length() - 1), "unlock /snapshots/lock")
}

test "a time that is not a number of seconds takes no snapshot" {
    let files = boot_files();
    let shell = boot_shell();
    let _ = shell.replies.set("date +%s", "+%s\n");

    let taken = take_system_snapshot(shell, files, recording_lock(shell), manual_kind(), "before a kernel upgrade");

    assert.equal(taken.error, "reading the time gave '+%s', which is not a number of seconds");
    assert.equal(shell.commands, ["lock /snapshots/lock", "date +%s", "unlock /snapshots/lock"])
}

test "a lock that cannot be taken takes no snapshot" {
    let files = boot_files();
    let shell = boot_shell();
    let lock = RecordingLock { shell: shell, fails_with: "cannot take the lock /snapshots/lock" };

    let taken = take_system_snapshot(shell, files, lock, manual_kind(), "before a kernel upgrade");

    assert.equal(taken.error, "cannot take the lock /snapshots/lock");
    assert.equal(shell.commands, ["lock /snapshots/lock"])
}
