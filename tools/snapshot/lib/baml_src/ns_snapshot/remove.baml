// Removing a snapshot: its subvolume and everything that goes with it — its
// line in the boot table and a set of boot artifacts nothing points at any
// more, for a system snapshot, and its label, for a manual one.

/// A snapshot as `oparch-snapshot-list` prints it, read into what removing it
/// has to know, or what is wrong with the path.
class SnapshotPath {
    /// The path inside `@snapshots`.
    relative: string,
    is_system: bool,
    is_manual: bool,
    error: string,
}

/// Reads the path of a snapshot. Anything that is not a snapshot's path under
/// `/snapshots` — `system/<kind>/@<unix-seconds>` or
/// `home/<work-context>/<kind>/@<unix-seconds>` — is refused, so nothing but a
/// snapshot is ever deleted.
function parse_snapshot_path(path: string) -> SnapshotPath {
    let wrong = SnapshotPath {
        relative: "", is_system: false, is_manual: false,
        error: `'${path}' is not the path of a snapshot under ${snapshots_root()}`,
    };
    let prefix = in_snapshots("");
    if (!path.starts_with(prefix)) {
        return wrong;
    }
    let relative = path.slice(prefix.length(), path.length());
    let parts = relative.split("/");
    let kind = "";
    let name = "";
    let is_system = false;
    if (parts.length() == 3 && (parts.at(0) ?? "") == "system") {
        kind = parts.at(1) ?? "";
        name = parts.at(2) ?? "";
        is_system = true;
    } else if (parts.length() == 4 && (parts.at(0) ?? "") == "home") {
        let work_context = parts.at(1) ?? "";
        if (work_context == "" || work_context == "." || work_context == "..") {
            return wrong;
        }
        kind = parts.at(2) ?? "";
        name = parts.at(3) ?? "";
    } else {
        return wrong;
    }
    if (kind != automatic_kind() && kind != manual_kind()) {
        return wrong;
    }
    if (moment_of(name) == null) {
        return wrong;
    }
    SnapshotPath { relative: relative, is_system: is_system, is_manual: kind == manual_kind(), error: "" }
}

test "the path of a snapshot of either scope and either kind is read" {
    let system = parse_snapshot_path("/snapshots/system/manual/@1778764800");
    let home = parse_snapshot_path("/snapshots/home/work/automatic/@1778761500");

    assert.equal(system.error, "");
    assert.equal(system.relative, "system/manual/@1778764800");
    assert.is_true(system.is_system && system.is_manual);
    assert.equal(home.error, "");
    assert.equal(home.relative, "home/work/automatic/@1778761500");
    assert.is_true(!home.is_system && !home.is_manual)
}

test "a path that is not a snapshot's is refused" {
    let refused = [
        "/snapshots/system/manual", "/snapshots/system/manual/@1778764800/",
        "/snapshots/system/other/@1778764800", "/snapshots/system/manual/@before-upgrade",
        "/snapshots/home/../manual/@1778764800", "/snapshots/home/work/manual",
        "/snapshots/boot/2c6d281a", "/snapshots/labels.json", "system/manual/@1778764800", "/",
    ];
    for (let path in refused) {
        assert.equal(parse_snapshot_path(path).error, `'${path}' is not the path of a snapshot under /snapshots`);
    }
}

/// Removes the label of a manual snapshot, keeping every other. A labels file
/// that is not there, or that holds no label for it, has nothing to remove.
function remove_label(files: root.common.Files, snapshot: string) -> string {
    let path = in_snapshots(labels_path());
    if (!files.exists(path)) {
        return "";
    }
    let labels = read_labels(files);
    if (labels.error != "") {
        return labels.error;
    }
    if (labels.entries.get(snapshot) == null) {
        return "";
    }
    let kept: map<string, string> = {};
    for (let key in labels.entries.keys()) {
        if (key != snapshot) {
            let _ = kept.set(key, labels.entries.get(key) ?? "");
        }
    }
    files.write(path, baml.json.to_string(kept) + "\n");
    files.failure() ?? ""
}

/// Removes a snapshot given by its path, holding the lock for the whole of it.
/// "" once it is removed, or what stopped it.
function remove_snapshot(shell: root.common.Shell, files: root.common.Files, lock: SnapshotLock,
                         path: string) -> string {
    let snapshot = parse_snapshot_path(path);
    if (snapshot.error != "") {
        return snapshot.error;
    }
    let locked = lock.acquire();
    if (locked != "") {
        return locked;
    }
    let removed = remove_snapshot_holding_lock(shell, files, snapshot, path);
    lock.release();
    removed
}

/// The removal itself, once the lock is held. The subvolume goes first, so a
/// snapshot that could not be deleted keeps its line and its label.
function remove_snapshot_holding_lock(shell: root.common.Shell, files: root.common.Files,
                                      snapshot: SnapshotPath, path: string) -> string {
    let deleted = failed(shell.capture("btrfs", ["subvolume", "delete", path]), `deleting the snapshot ${path}`);
    if (deleted != "") {
        return deleted;
    }
    if (snapshot.is_system) {
        let dropped = drop_from_boot_table(files, [snapshot.relative]);
        if (dropped != "") {
            return dropped;
        }
        let swept = sweep_boot_sets(shell, files);
        if (swept != "") {
            return swept;
        }
    }
    if (snapshot.is_manual) {
        return remove_label(files, snapshot.relative);
    }
    ""
}

/// A machine with three system snapshots in the table: a manual and an
/// automatic one sharing a set, and a manual one alone on its own.
function removal_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/snapshots/boot/table",
                "system/manual/@1778764800 aaaa\nsystem/automatic/@1778764800 aaaa\nsystem/manual/@1778761200 bbbb\n");
    files.mkdir("/snapshots/boot");
    files.mkdir("/snapshots/boot/aaaa");
    files.mkdir("/snapshots/boot/bbbb");
    files.write("/snapshots/labels.json",
                "{\"system/manual/@1778764800\":\"before a kernel upgrade\",\"system/manual/@1778761200\":\"a clean base install\"}\n");
    files
}

test "a system snapshot takes its line with it, and the set nothing else points at, and its label" {
    let files = removal_files();
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(remove_snapshot(shell, files, recording_lock(shell), "/snapshots/system/manual/@1778761200"), "");

    assert.equal(shell.commands, [
        "lock /snapshots/lock",
        "btrfs subvolume delete /snapshots/system/manual/@1778761200",
        "rm -rf /snapshots/boot/bbbb",
        "unlock /snapshots/lock",
    ]);
    assert.equal(files.written.get("/snapshots/boot/table"),
                 "system/manual/@1778764800 aaaa\nsystem/automatic/@1778764800 aaaa\n");
    let labels = read_labels(files);
    assert.equal(labels.entries.get("system/manual/@1778761200"), null);
    assert.equal(labels.entries.get("system/manual/@1778764800"), "before a kernel upgrade")
}

test "a set another line still points at stays" {
    let files = removal_files();
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(remove_snapshot(shell, files, recording_lock(shell), "/snapshots/system/manual/@1778764800"), "");

    //# the automatic snapshot of the same second has a line of its own, and
    //# still points at the set
    assert.is_true(!shell.commands.join("\n").includes("rm -rf"));
    assert.equal(files.written.get("/snapshots/boot/table"),
                 "system/automatic/@1778764800 aaaa\nsystem/manual/@1778761200 bbbb\n")
}

test "an automatic snapshot of a home is only its subvolume" {
    let files = removal_files();
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(remove_snapshot(shell, files, recording_lock(shell), "/snapshots/home/work/automatic/@1778761500"), "");

    assert.equal(shell.commands, [
        "lock /snapshots/lock",
        "btrfs subvolume delete /snapshots/home/work/automatic/@1778761500",
        "unlock /snapshots/lock",
    ]);
    assert.equal(files.written.get("/snapshots/boot/table"),
                 "system/manual/@1778764800 aaaa\nsystem/automatic/@1778764800 aaaa\nsystem/manual/@1778761200 bbbb\n")
}

test "a manual snapshot of a home loses its label" {
    let files = root.common.recording_files();
    files.write("/snapshots/labels.json", "{\"home/work/manual/@1778765100\":\"before the client project import\"}\n");
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(remove_snapshot(shell, files, recording_lock(shell), "/snapshots/home/work/manual/@1778765100"), "");

    assert.equal(files.written.get("/snapshots/labels.json"), "{}\n")
}

test "a snapshot that cannot be deleted keeps its line, its set and its label" {
    let files = removal_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: {},
        exit_codes: { "btrfs subvolume delete /snapshots/system/manual/@1778761200": 1 },
    };

    assert.equal(remove_snapshot(shell, files, recording_lock(shell), "/snapshots/system/manual/@1778761200"),
                 "deleting the snapshot /snapshots/system/manual/@1778761200 failed with exit code 1.");
    assert.equal(files.written.get("/snapshots/boot/table"),
                 "system/manual/@1778764800 aaaa\nsystem/automatic/@1778764800 aaaa\nsystem/manual/@1778761200 bbbb\n");
    assert.equal(read_labels(files).entries.get("system/manual/@1778761200"), "a clean base install");
    assert.equal(shell.commands.at(shell.commands.length() - 1), "unlock /snapshots/lock")
}

test "a path that is not a snapshot's takes no lock and deletes nothing" {
    let files = removal_files();
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(remove_snapshot(shell, files, recording_lock(shell), "/snapshots/boot/aaaa"),
                 "'/snapshots/boot/aaaa' is not the path of a snapshot under /snapshots");
    assert.equal(shell.commands, [])
}
