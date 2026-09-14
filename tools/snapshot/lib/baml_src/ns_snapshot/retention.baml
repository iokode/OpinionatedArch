// Automatic snapshots: one taken at a moment the policy names, and the ones of
// the same scope that the retention policy of `docs/decisions/004-snapshots.md`
// no longer keeps deleted in the same run.

/// How many automatic snapshots each scope keeps.
function automatic_snapshots_kept() -> int {
    60
}

/// Where the automatic snapshots of the system are, inside `@snapshots`.
function system_automatic_directory() -> string {
    `system/${automatic_kind()}`
}

/// Where the automatic snapshots of a work context's home are, inside
/// `@snapshots`.
function home_automatic_directory(work_context: string) -> string {
    `home/${work_context}/${automatic_kind()}`
}

/// Whether a text holds at least one character and nothing but decimal digits.
function only_digits(text: string) -> bool {
    if (text == "") {
        return false;
    }
    let index = 0;
    while (index < text.length()) {
        if (!"0123456789".includes(text.slice(index, index + 1))) {
            return false;
        }
        index = index + 1;
    }
    true
}

test "only digits are digits" {
    assert.is_true(only_digits("1000"));
    assert.is_true(!only_digits(""));
    assert.is_true(!only_digits("work"));
    assert.is_true(!only_digits("-1"));
    assert.is_true(!only_digits("10a"))
}

/// The moment a snapshot's name gives, or null when the name is not
/// `@<unix-seconds>`.
function moment_of(name: string) -> int? {
    if (!name.starts_with("@")) {
        return null;
    }
    let seconds = name.slice(1, name.length());
    if (!only_digits(seconds)) {
        return null;
    }
    root.common.parse_int(seconds)
}

test "the moment is read from a snapshot's name, and from nothing else" {
    assert.equal(moment_of("@1778764800"), 1778764800);
    assert.equal(moment_of("1778764800"), null);
    assert.equal(moment_of("@1778764800-before-kernel-upgrade"), null);
    assert.equal(moment_of("@"), null)
}

/// The work context a home scope was given, by name or by UID, or what stopped
/// it from being found.
class Resolved {
    work_context: string,
    error: string,
}

/// A value made only of decimal digits is a UID, and the work context is the
/// account that has it. Anything else is the name of the work context.
function resolve_work_context(shell: root.common.Shell, given: string) -> Resolved {
    if (!only_digits(given)) {
        return Resolved { work_context: given, error: "" };
    }
    let account = shell.capture("getent", ["passwd", given]);
    let name = account.stdout.trim().split(":").at(0) ?? "";
    if (!account.ok() || name == "") {
        return Resolved { work_context: "", error: `no account has the user id ${given}` };
    }
    Resolved { work_context: name, error: "" }
}

test "a work context given by name is that name, and asks nothing of the machine" {
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(resolve_work_context(shell, "work").work_context, "work");
    assert.equal(shell.commands, [])
}

test "a work context given by UID is the account that has it" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "getent passwd 1001": "work:x:1001:1001::/home/work:/bin/bash\n" },
    };

    let resolved = resolve_work_context(shell, "1001");

    assert.equal(resolved.error, "");
    assert.equal(resolved.work_context, "work")
}

test "a UID no account has is refused" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: {}, exit_codes: { "getent passwd 4242": 2 },
    };

    assert.equal(resolve_work_context(shell, "4242").error, "no account has the user id 4242")
}

/// The snapshots of a directory, oldest first, by name, or what stopped them
/// from being listed.
class Listed {
    names: string[],
    error: string,
}

/// The automatic snapshots of a scope, oldest first. What is in the directory
/// and is not named `@<unix-seconds>` is not a snapshot this library took, and
/// is left out.
function automatic_snapshots(files: root.common.Files, directory: string) -> Listed {
    let path = in_snapshots(directory);
    let listed = files.read_dir(path);
    if (listed == null) {
        return Listed { names: [], error: `cannot list ${path}` };
    }
    let names: string[] = [];
    let empty: root.common.DirEntry[] = [];
    for (let entry in listed ?? empty) {
        if (entry.is_dir && moment_of(entry.name) != null) {
            names.push(entry.name);
        }
    }
    Listed {
        names: names.sort_by_key(
            (name) -> {
                moment_of(name) ?? 0
            },
        ),
        error: "",
    }
}

/// The automatic snapshots that were deleted, by their paths inside
/// `@snapshots`, and what stopped the deleting when one could not be.
class Purged {
    removed: string[],
    error: string,
}

/// Deletes the oldest automatic snapshots of a scope beyond the ones it keeps.
function purge_automatic(shell: root.common.Shell, files: root.common.Files, directory: string) -> Purged {
    let listed = automatic_snapshots(files, directory);
    if (listed.error != "") {
        return Purged { removed: [], error: listed.error };
    }
    let removed: string[] = [];
    let excess = listed.names.length() - automatic_snapshots_kept();
    let index = 0;
    while (index < excess) {
        let relative = `${directory}/${listed.names.at(index) ?? ""}`;
        let path = in_snapshots(relative);
        let deleted = failed(shell.capture("btrfs", ["subvolume", "delete", path]), `deleting the snapshot ${path}`);
        if (deleted != "") {
            return Purged { removed: removed, error: deleted };
        }
        removed.push(relative);
        index = index + 1;
    }
    Purged { removed: removed, error: "" }
}

test "the oldest automatic snapshots beyond sixty are deleted, by their moment" {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/home/work/automatic");
    let seconds = 1;
    while (seconds <= 62) {
        files.mkdir(`/snapshots/home/work/automatic/@${seconds}`);
        seconds = seconds + 1;
    }
    files.mkdir("/snapshots/home/work/automatic/not-a-snapshot");
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    let purged = purge_automatic(shell, files, "home/work/automatic");

    //# @9 sorts after @10 as text; by its moment it is older, and it stays
    assert.equal(purged.error, "");
    assert.equal(purged.removed, ["home/work/automatic/@1", "home/work/automatic/@2"]);
    assert.equal(shell.commands, [
        "btrfs subvolume delete /snapshots/home/work/automatic/@1",
        "btrfs subvolume delete /snapshots/home/work/automatic/@2",
    ])
}

test "a scope that keeps no more than sixty loses nothing" {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/system/automatic");
    files.mkdir("/snapshots/system/automatic/@1778764800");
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(purge_automatic(shell, files, "system/automatic").removed, []);
    assert.equal(shell.commands, [])
}

/// The lines of the boot table, or what stopped it from being read. A table
/// that is not there holds no line; one that is there and cannot be read is an
/// error, because every set would otherwise look like one nothing points at.
class TableRead {
    lines: string[],
    error: string,
}

function read_boot_table(files: root.common.Files) -> TableRead {
    let path = in_snapshots(boot_table_path());
    if (!files.exists(path)) {
        return TableRead { lines: [], error: "" };
    }
    let text = files.read(path);
    if (text == null) {
        return TableRead { lines: [], error: `cannot read ${path}` };
    }
    TableRead { lines: root.common.nonempty_lines(text ?? ""), error: "" }
}

/// The snapshot a line of the table is about, by its path inside `@snapshots`.
function table_line_snapshot(line: string) -> string {
    line.split(" ").at(0) ?? ""
}

/// The hash of the set a line of the table points at.
function table_line_hash(line: string) -> string {
    line.split(" ").at(1) ?? ""
}

/// Removes the lines of the snapshots that were deleted, keeping every other
/// line as it was.
function drop_from_boot_table(files: root.common.Files, removed: string[]) -> string {
    if (removed.length() == 0) {
        return "";
    }
    let table = read_boot_table(files);
    if (table.error != "") {
        return table.error;
    }
    let kept = "";
    for (let line in table.lines) {
        if (!removed.includes(table_line_snapshot(line))) {
            kept = kept + line + "\n";
        }
    }
    files.write(in_snapshots(boot_table_path()), kept);
    files.failure() ?? ""
}

/// Deletes every directory under `@snapshots/boot` that no line of the table
/// points at: the sets whose last snapshot is gone, and a copy a run that
/// stopped half way left unnamed.
function sweep_boot_sets(shell: root.common.Shell, files: root.common.Files) -> string {
    let table = read_boot_table(files);
    if (table.error != "") {
        return table.error;
    }
    let referenced: string[] = [];
    for (let line in table.lines) {
        referenced.push(table_line_hash(line));
    }
    let sets = in_snapshots(boot_sets_path());
    if (!files.exists(sets)) {
        return "";
    }
    let listed = files.read_dir(sets);
    if (listed == null) {
        return `cannot list ${sets}`;
    }
    let empty: root.common.DirEntry[] = [];
    for (let entry in listed ?? empty) {
        if (entry.is_dir && !referenced.includes(entry.name)) {
            let path = root.common.in_directory(sets, entry.name);
            let deleted = failed(shell.capture("rm", ["-rf", path]), `deleting ${path}`);
            if (deleted != "") {
                return deleted;
            }
        }
    }
    ""
}

/// Takes an automatic snapshot of the system and deletes what the retention
/// policy no longer keeps, holding the lock for the whole of it. Nothing is
/// deleted when the snapshot could not be taken.
function take_automatic_system_snapshot(shell: root.common.Shell, files: root.common.Files,
                                        lock: SnapshotLock) -> Taken {
    let locked = lock.acquire();
    if (locked != "") {
        return Taken { path: "", error: locked };
    }
    let taken = take_system_snapshot_holding_lock(shell, files, automatic_kind(), "");
    if (taken.error == "") {
        taken = retain_system(shell, files, taken.path);
    }
    lock.release();
    taken
}

/// The retention of the system scope, once its snapshot is taken: the oldest
/// automatic snapshots go, then their lines in the table, then every set
/// nothing points at any more.
function retain_system(shell: root.common.Shell, files: root.common.Files, path: string) -> Taken {
    let purged = purge_automatic(shell, files, system_automatic_directory());
    let dropped = drop_from_boot_table(files, purged.removed);
    if (purged.error != "") {
        return Taken { path: path, error: purged.error };
    }
    if (dropped != "") {
        return Taken { path: path, error: dropped };
    }
    Taken { path: path, error: sweep_boot_sets(shell, files) }
}

/// Takes an automatic snapshot of a work context's home, given by name or by
/// UID, and deletes what the retention policy no longer keeps. Nothing is
/// deleted when the snapshot could not be taken.
function take_automatic_home_snapshot(shell: root.common.Shell, files: root.common.Files,
                                      lock: SnapshotLock, given: string) -> Taken {
    let resolved = resolve_work_context(shell, given);
    if (resolved.error != "") {
        return Taken { path: "", error: resolved.error };
    }
    let taken = take_home_snapshot(shell, files, lock, resolved.work_context, automatic_kind(), "");
    if (taken.error != "") {
        return taken;
    }
    let purged = purge_automatic(shell, files, home_automatic_directory(resolved.work_context));
    Taken { path: taken.path, error: purged.error }
}

test "an automatic system snapshot deletes the oldest beyond sixty, their lines and the sets left without one" {
    let files = boot_files();
    let shell = boot_shell();
    let new_set = "1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732";
    files.mkdir("/snapshots/system/automatic");
    let seconds = 1778000001;
    while (seconds <= 1778000060) {
        files.mkdir(`/snapshots/system/automatic/@${seconds}`);
        seconds = seconds + 1;
    }
    //# the snapshot this run takes, which the double does not make on its own:
    //# with it the scope holds sixty-one, and the oldest is past what it keeps
    files.mkdir("/snapshots/system/automatic/@1778764800");
    files.write("/snapshots/boot/table",
                "system/automatic/@1778000001 aaaa\nsystem/manual/@1778000100 bbbb\n");
    files.mkdir("/snapshots/boot");
    files.mkdir("/snapshots/boot/aaaa");
    files.mkdir("/snapshots/boot/bbbb");
    files.mkdir(`/snapshots/boot/${new_set}`);
    files.mkdir("/snapshots/boot/tmp.Xq3v9TzL1a");

    let taken = take_automatic_system_snapshot(shell, files, recording_lock(shell));

    assert.equal(taken.error, "");
    assert.equal(taken.path, "/snapshots/system/automatic/@1778764800");
    assert.equal(shell.commands, [
        "lock /snapshots/lock",
        "date +%s",
        "sha256sum -- /boot/OpinionatedArch/vmlinuz-linux /boot/grubx64.efi",
        "sha256sum",
        "btrfs subvolume snapshot -r / /snapshots/system/automatic/@1778764800",
        "btrfs subvolume delete /snapshots/system/automatic/@1778000001",
        "rm -rf /snapshots/boot/aaaa",
        "rm -rf /snapshots/boot/tmp.Xq3v9TzL1a",
        "unlock /snapshots/lock",
    ]);
    assert.equal(files.written.get("/snapshots/boot/table"),
                 `system/manual/@1778000100 bbbb` + "\n" + `system/automatic/@1778764800 ${new_set}` + "\n");
    assert.equal(files.written.get("/snapshots/labels.json"), null)
}

test "an automatic system snapshot that cannot be taken deletes nothing" {
    let files = boot_files();
    let shell = boot_shell();
    files.mkdir("/snapshots/boot");
    files.mkdir("/snapshots/boot/1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732");
    let _ = shell.exit_codes.set("btrfs subvolume snapshot -r / /snapshots/system/automatic/@1778764800", 1);

    let taken = take_automatic_system_snapshot(shell, files, recording_lock(shell));

    assert.equal(taken.error, "taking the snapshot /snapshots/system/automatic/@1778764800 failed with exit code 1.");
    assert.is_true(!shell.commands.join("\n").includes("delete"));
    assert.is_true(!shell.commands.join("\n").includes("rm -rf"));
    assert.equal(shell.commands.at(shell.commands.length() - 1), "unlock /snapshots/lock")
}

test "a table that is there and cannot be read deletes no set" {
    let files = root.common.recording_files();
    files.present.push("/snapshots/boot/table");
    files.mkdir("/snapshots/boot");
    files.mkdir("/snapshots/boot/aaaa");
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(sweep_boot_sets(shell, files), "cannot read /snapshots/boot/table");
    assert.equal(shell.commands, [])
}

test "an automatic snapshot of a home given by UID is taken of that account's home and kept to sixty" {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/home/work/automatic");
    let seconds = 1778000001;
    while (seconds <= 1778000060) {
        files.mkdir(`/snapshots/home/work/automatic/@${seconds}`);
        seconds = seconds + 1;
    }
    files.mkdir("/snapshots/home/work/automatic/@1778761500");
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: {
            "getent passwd 1001": "work:x:1001:1001::/home/work:/bin/bash\n",
            "date +%s": "1778761500\n",
        },
    };

    let taken = take_automatic_home_snapshot(shell, files, recording_lock(shell), "1001");

    assert.equal(taken.error, "");
    assert.equal(taken.path, "/snapshots/home/work/automatic/@1778761500");
    assert.equal(shell.commands, [
        "getent passwd 1001",
        "date +%s",
        "btrfs subvolume snapshot -r /home/work /snapshots/home/work/automatic/@1778761500",
        "btrfs subvolume delete /snapshots/home/work/automatic/@1778000001",
    ])
}

test "an automatic snapshot of a home that cannot be taken deletes nothing" {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/home/work/automatic");
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [],
        replies: { "getent passwd 1001": "work:x:1001:1001::/home/work:/bin/bash\n", "date +%s": "1778761500\n" },
        exit_codes: { "btrfs subvolume snapshot -r /home/work /snapshots/home/work/automatic/@1778761500": 1 },
    };

    let taken = take_automatic_home_snapshot(shell, files, recording_lock(shell), "1001");

    assert.equal(taken.error, "taking the snapshot /snapshots/home/work/automatic/@1778761500 failed with exit code 1.");
    assert.is_true(!shell.commands.join("\n").includes("delete"))
}
