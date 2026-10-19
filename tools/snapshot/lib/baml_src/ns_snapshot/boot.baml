// The boot artifacts a system snapshot carries, as
// `docs/decisions/004-snapshots.md` requires: the content of the EFI system
// partition, copied once for each distinct set of it under `@snapshots/boot`,
// and the table that pairs each system snapshot with its set. What the hash is
// taken over and what the table holds is
// `docs/tools/snapshot/create/002-boot-table-format.md`.

/// Where the EFI system partition is mounted, and what a set is a copy of.
function boot_directory() -> string {
    "/boot"
}

/// Where the sets are kept, inside `@snapshots`.
function boot_sets_path() -> string {
    "boot"
}

/// The table pairing each system snapshot with its set, inside `@snapshots`.
function boot_table_path() -> string {
    "boot/table"
}

/// The regular files under a directory, as paths relative to it, in byte order.
class FilesUnder {
    paths: string[],
    error: string,
}

/// Walks a directory for its regular files. A directory in it that cannot be
/// listed is an error rather than one with nothing in it: a set taken over
/// part of the partition would be named as if it were the whole of it.
function files_under(files: root.common.Files, directory: string) -> FilesUnder {
    let found: string[] = [];
    let pending: string[] = [""];
    let index = 0;
    while (index < pending.length()) {
        let relative = pending.at(index) ?? "";
        index = index + 1;
        let absolute = if (relative == "") { directory } else { root.common.in_directory(directory, relative) };
        let listed = files.read_dir(absolute);
        if (listed == null) {
            return FilesUnder { paths: [], error: `cannot list ${absolute}` };
        }
        let empty: root.common.DirEntry[] = [];
        for (let entry in listed ?? empty) {
            let child = if (relative == "") { entry.name } else { `${relative}/${entry.name}` };
            if (entry.is_dir) {
                pending.push(child);
            } else if (entry.is_file) {
                found.push(child);
            }
        }
    }
    FilesUnder { paths: found.sort(), error: "" }
}

test "the files under a directory are every regular file at any depth, in byte order" {
    let files = root.common.recording_files();
    files.mkdir("/boot");
    files.mkdir("/boot/EFI");
    files.mkdir("/boot/EFI/OpinionatedArch");
    files.mkdir("/boot/OpinionatedArch");
    files.write("/boot/OpinionatedArch/vmlinuz-linux", "kernel");
    files.write("/boot/EFI/OpinionatedArch/grubx64.efi", "grub");
    files.write("/boot/OpinionatedArch/initramfs-linux.img", "initramfs");

    let under = files_under(files, "/boot");

    assert.equal(under.error, "");
    assert.equal(under.paths, [
        "EFI/OpinionatedArch/grubx64.efi",
        "OpinionatedArch/initramfs-linux.img",
        "OpinionatedArch/vmlinuz-linux",
    ])
}

test "a directory that cannot be listed stops the walk" {
    let files = root.common.recording_files();

    assert.equal(files_under(files, "/boot").error, "cannot list /boot")
}

/// The hash on one line of what `sha256sum` prints. A line whose file name
/// holds a backslash or a newline is begun with a backslash, and the hash
/// follows it. Empty when the line holds no hash.
function hash_of_line(line: string) -> string {
    let start = if (line.starts_with("\\")) { 1 } else { 0 };
    if (line.length() < start + 64) {
        return "";
    }
    line.slice(start, start + 64)
}

test "the hash is read from a line whether or not its name was escaped" {
    let hash = "73cb3858a687a8494ca3323053016282f3dad39d42cf62ca4e79dda2aac7d9ac";

    assert.equal(hash_of_line(`${hash}  /boot/vmlinuz-linux`), hash);
    assert.equal(hash_of_line(`\\${hash}  /boot/we\\\\ird`), hash);
    assert.equal(hash_of_line("sha256sum: /boot: Is a directory"), "")
}

/// The text a set is named by the hash of: one line for each file, its hash
/// and its path, as `sha256sum` writes them.
function boot_manifest(paths: string[], hashes: string[]) -> string {
    let manifest = "";
    let index = 0;
    while (index < paths.length()) {
        manifest = manifest + `${hashes.at(index) ?? ""}  ${paths.at(index) ?? ""}` + "\n";
        index = index + 1;
    }
    manifest
}

test "the manifest is a line for each file, its hash and its path" {
    assert.equal(boot_manifest(["a", "sub/b"], ["1111", "2222"]), "1111  a\n2222  sub/b\n");
    assert.equal(boot_manifest([], []), "")
}

/// The name a set of boot artifacts is stored under, or what stopped it from
/// being worked out.
class SetHash {
    hash: string,
    error: string,
}

/// Hashes the content of a directory: every regular file in it, by its content
/// and its path, so that the same content always gives the same name.
function hash_boot_set(shell: root.common.Shell, files: root.common.Files,
                       directory: string) -> SetHash {
    let under = files_under(files, directory);
    if (under.error != "") {
        return SetHash { hash: "", error: under.error };
    }

    let hashes: string[] = [];
    //# with no files `sha256sum` would read its standard input, which is not an
    //# empty set
    if (under.paths.length() > 0) {
        let absolute: string[] = [];
        for (let relative in under.paths) {
            absolute.push(root.common.in_directory(directory, relative));
        }
        let summed = shell.capture("sha256sum", ["--"].concat(absolute));
        let problem = failed(summed, `hashing the files under ${directory}`);
        if (problem != "") {
            return SetHash { hash: "", error: problem };
        }
        for (let line in root.common.nonempty_lines(summed.stdout)) {
            hashes.push(hash_of_line(line));
        }
        if (hashes.length() != under.paths.length() || hashes.includes("")) {
            return SetHash {
                hash: "",
                error: `hashing the files under ${directory} did not give one hash for each of them`,
            };
        }
    }

    let named = shell.feed("sha256sum", [], boot_manifest(under.paths, hashes));
    let problem = failed(named, `hashing the set of files under ${directory}`);
    if (problem != "") {
        return SetHash { hash: "", error: problem };
    }
    let hash = hash_of_line(named.stdout.trim());
    if (hash == "") {
        return SetHash { hash: "", error: `hashing the set of files under ${directory} gave no hash` };
    }
    SetHash { hash: hash, error: "" }
}

test "a set is named by the hash of its files and their paths" {
    let directory = `${baml.env.get("TMPDIR") ?? "/tmp"}/oparch-snapshot-boot-set`;
    let files = root.common.system_files();
    files.mkdir(`${directory}/sub`);
    files.write(`${directory}/a`, "x\n");
    files.write(`${directory}/sub/b`, "y\n");

    let set = hash_boot_set(root.common.system_shell(), files, directory);

    //# the SHA-256 of "73cb…d9ac  a\n3bb2…0877  sub/b\n", where each hash is
    //# that of the file named beside it, worked out apart from this code
    assert.equal(set.error, "");
    assert.equal(set.hash, "1d015346f81f8a20205a1e1325572085d8cfab2d935435a3506c911fefe1e732");
    let _ = baml.fs.remove(`${directory}/sub/b`) catch (e) { _ => null };
    let _ = baml.fs.remove(`${directory}/a`) catch (e) { _ => null };
    let _ = baml.fs.remove_dir(`${directory}/sub`) catch (e) { _ => null };
    let _ = baml.fs.remove_dir(directory) catch (e) { _ => null }
}

test "a file whose hash cannot be read names no set" {
    let files = root.common.recording_files();
    files.mkdir("/boot");
    files.write("/boot/vmlinuz-linux", "kernel");
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: {},
        exit_codes: { "sha256sum -- /boot/vmlinuz-linux": 1 },
    };

    let set = hash_boot_set(shell, files, "/boot");

    assert.equal(set.hash, "");
    assert.equal(set.error, "hashing the files under /boot failed with exit code 1.");
    assert.equal(shell.fed, [])
}

/// Stores a set under its hash, unless a set with that hash is there already.
///
/// The copy is made under a name of its own and given the hash only once it is
/// whole, so a directory named by a hash always holds the whole of that set: a
/// copy that stops half way is never taken for one that finished.
function store_boot_set(shell: root.common.Shell, files: root.common.Files,
                        directory: string, hash: string) -> string {
    let sets = in_snapshots(boot_sets_path());
    let stored = root.common.in_directory(sets, hash);
    if (files.exists(stored)) {
        return "";
    }
    files.mkdir(sets);
    if let problem: string = files.failure() {
        return problem;
    }

    let staging = shell.capture("mktemp", ["-d", "-p", sets]);
    let made = failed(staging, `making a directory to copy ${directory} into`);
    if (made != "") {
        return made;
    }
    let copying = staging.stdout.trim();
    let copied = failed(shell.capture("cp", ["-r", `${directory}/.`, copying]),
                        `copying ${directory} into ${copying}`);
    if (copied != "") {
        return copied;
    }
    failed(shell.capture("mv", ["-T", copying, stored]), `naming the copy of ${directory} ${stored}`)
}

test "a set that is not stored yet is copied whole and then named" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "mktemp -d -p /snapshots/boot": "/snapshots/boot/tmp.Xq3v9TzL1a\n" },
    };

    assert.equal(store_boot_set(shell, files, "/boot", "2c6d281a"), "");
    assert.is_true(files.directories.includes("/snapshots/boot"));
    assert.equal(shell.commands, [
        "mktemp -d -p /snapshots/boot",
        "cp -r /boot/. /snapshots/boot/tmp.Xq3v9TzL1a",
        "mv -T /snapshots/boot/tmp.Xq3v9TzL1a /snapshots/boot/2c6d281a",
    ])
}

test "a set that is stored already is not copied again" {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/boot/2c6d281a");
    let shell = root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    assert.equal(store_boot_set(shell, files, "/boot", "2c6d281a"), "");
    assert.equal(shell.commands, [])
}

test "a copy that fails is never given the name of the set" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [],
        replies: { "mktemp -d -p /snapshots/boot": "/snapshots/boot/tmp.Xq3v9TzL1a\n" },
        exit_codes: { "cp -r /boot/. /snapshots/boot/tmp.Xq3v9TzL1a": 1 },
    };

    assert.equal(store_boot_set(shell, files, "/boot", "2c6d281a"),
                 "copying /boot into /snapshots/boot/tmp.Xq3v9TzL1a failed with exit code 1.");
    assert.is_true(!shell.commands.join("\n").includes("mv "))
}

/// The line of the table that pairs a system snapshot, by its path inside
/// `@snapshots`, with its set.
function boot_table_line(snapshot: string, hash: string) -> string {
    `${snapshot} ${hash}` + "\n"
}

test "a line of the table is the snapshot's path and its set's hash" {
    assert.equal(boot_table_line("system/manual/@1778764800", "2c6d281a"), "system/manual/@1778764800 2c6d281a\n")
}
