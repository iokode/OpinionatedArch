// Writing into a filesystem the tool does not necessarily own.
//
// An installer works on two roots at once: the live system it runs from, and
// the system it is building. `Target` names which one a path belongs to, so a
// path is never accidentally written to the wrong root.

class Target {
    /// "/" for the live system, or the mount point of the system being built.
    root: string,
}

function local_target() -> Target {
    Target { root: "/" }
}

function mounted_target(root: string) -> Target {
    Target { root: root }
}

/// Resolves an absolute path inside a target. Paths are always written as
/// absolute paths of the target system, never as host paths.
function target_path(target: Target, path: string) -> string throws baml.errors.InvalidArgument {
    if (!path.starts_with("/")) {
        throw baml.errors.InvalidArgument { message: `Path must be absolute: ${path}` };
    }
    if (target.root == "/") {
        return path;
    }
    let trimmed = target.root.ends_with("/");
    let root = if (trimmed) { target.root.substring(0, target.root.length() - 1) } else { target.root };
    `${root}${path}`
}

/// Joins a directory and a name, whether or not the directory ends in a slash.
function in_directory(directory: string, name: string) -> string {
    if (directory.ends_with("/")) {
        `${directory}${name}`
    } else {
        `${directory}/${name}`
    }
}

test "in_directory joins with exactly one slash" {
    assert.equal(in_directory("/pkg", "manifest.yaml"), "/pkg/manifest.yaml");
    assert.equal(in_directory("/pkg/", "manifest.yaml"), "/pkg/manifest.yaml")
}

interface Files {
    /// The first operation that failed, if any. File operations do not report
    /// failure one by one, because a phase would then have to check every
    /// write; instead the caller asks once, and a failed write can never pass
    /// unnoticed.
    function failure(self) -> string? throws never

    function write(self, path: string, content: string) -> void throws never
    function read(self, path: string) -> string? throws never
    function exists(self, path: string) -> bool throws never
    function mkdir(self, path: string) -> void throws never
    function symlink(self, path: string, points_to: string) -> void throws never
    /// Mode as an octal string, as `chmod` takes it: "0755".
    function chmod(self, path: string, mode: string) -> void throws never
}

class HostFiles {
    on_failure: () -> string? throws never,
    on_write: (string, string) -> void throws never,
    on_read: (string) -> string? throws never,
    on_exists: (string) -> bool throws never,
    on_mkdir: (string) -> void throws never,
    on_symlink: (string, string) -> void throws never,
    on_chmod: (string, string) -> void throws never,
    implements Files {
        function failure(self) -> string? { self.on_failure() }
        function write(self, path: string, content: string) -> void { self.on_write(path, content) }
        function read(self, path: string) -> string? { self.on_read(path) }
        function exists(self, path: string) -> bool { self.on_exists(path) }
        function mkdir(self, path: string) -> void { self.on_mkdir(path) }
        function symlink(self, path: string, points_to: string) -> void { self.on_symlink(path, points_to) }
        function chmod(self, path: string, mode: string) -> void { self.on_chmod(path, mode) }
    }
}

/// Records what would be written instead of writing it, so a phase can be
/// verified by the contents it produces.
class RecordingFiles {
    /// Set by a test to make the next check report a failure.
    fails_with: string?,
    written: map<string, string>,
    directories: string[],
    symlinks: map<string, string>,
    modes: map<string, string>,
    present: string[],

    implements Files {
        function failure(self) -> string? { self.fails_with }
        function write(self, path: string, content: string) -> void {
            let _ = self.written.set(path, content);
        }
        function read(self, path: string) -> string? {
            self.written.get(path)
        }
        function exists(self, path: string) -> bool {
            self.present.includes(path) || self.written.get(path) != null
        }
        function mkdir(self, path: string) -> void {
            if (!self.directories.includes(path)) { self.directories.push(path); }
        }
        function symlink(self, path: string, points_to: string) -> void {
            let _ = self.symlinks.set(path, points_to);
        }
        function chmod(self, path: string, mode: string) -> void {
            let _ = self.modes.set(path, mode);
        }
    }
}

function recording_files() -> RecordingFiles {
    RecordingFiles {
        fails_with: null, written: {}, directories: [], symlinks: {}, modes: {}, present: [],
    }
}

test "target_path prefixes a mounted root and leaves the local one alone" {
    assert.equal(target_path(local_target(), "/etc/hostname"), "/etc/hostname");
    assert.equal(target_path(mounted_target("/mnt"), "/etc/hostname"), "/mnt/etc/hostname");
    assert.equal(target_path(mounted_target("/mnt/"), "/etc/hostname"), "/mnt/etc/hostname")
}

test "target_path refuses a relative path" {
    let failed = target_path(mounted_target("/mnt"), "etc/hostname")
        catch (e) { baml.errors.InvalidArgument => "refused" };
    assert.equal(failed, "refused")
}

test "RecordingFiles remembers what a phase produced" {
    let files = recording_files();
    files.write("/etc/hostname", "oparch\n");
    files.mkdir("/var/log");
    files.symlink("/etc/localtime", "/usr/share/zoneinfo/Europe/Madrid");
    files.chmod("/root/script.sh", "0755");

    assert.equal(files.written.get("/etc/hostname"), "oparch\n");
    assert.equal(files.directories, ["/var/log"]);
    assert.equal(files.symlinks.get("/etc/localtime"), "/usr/share/zoneinfo/Europe/Madrid");
    assert.equal(files.modes.get("/root/script.sh"), "0755");
    assert.is_true(files.exists("/etc/hostname"));
    assert.is_true(!files.exists("/etc/fstab"))
}

/// Rewrites a file, replacing the first occurrence of `from`. Returns false
/// when the file is not there to rewrite.
function replace_in_file(files: Files, path: string, from: string, to: string) -> bool {
    if let content: string = files.read(path) {
        files.write(path, content.replace(from, to));
        return true;
    }
    false
}

/// Adds to the end of a file, creating it when it does not exist yet.
function append_to_file(files: Files, path: string, content: string) -> void {
    files.write(path, (files.read(path) ?? "") + content)
}

test "append_to_file adds to what is already there" {
    let files = recording_files();
    files.write("/etc/fstab", "UUID=5f3a / btrfs subvol=@ 0 0\n");
    append_to_file(files, "/etc/fstab", "/swap/swapfile none swap defaults 0 0\n");

    assert.equal(files.written.get("/etc/fstab"),
                 "UUID=5f3a / btrfs subvol=@ 0 0\n/swap/swapfile none swap defaults 0 0\n")
}

test "append_to_file creates the file when it is not there" {
    let files = recording_files();
    append_to_file(files, "/etc/new", "line\n");
    assert.equal(files.written.get("/etc/new"), "line\n")
}
