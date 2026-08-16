// Writing into a filesystem the caller does not necessarily own.
//
// A program can have more than one root in play at once: the system it is
// running on, and a system mounted somewhere else. `Target` names which of
// them a path belongs to, so a path is never written to the wrong one.

class Target {
    /// "/" for the system this program runs on, or the mount point of another.
    root: string,
    /// Whether a command aimed at this target has to be run inside it.
    ///
    /// It is answered rather than derived from the root, because the two are
    /// different questions about the same volume: a mounted system is written
    /// to and read from directly whatever the answer, and only a command that
    /// has to see it as its own root is entered with `arch-chroot`. A volume
    /// can be inspected without being entered, and a root of "/" is never
    /// entered at all.
    uses_chroot: bool,
}

/// The system this program is running on.
function local_target() -> Target {
    Target { root: "/", uses_chroot: false }
}

/// A system mounted elsewhere, whose commands are run inside it.
function chroot_target(root: string) -> Target {
    Target { root: root, uses_chroot: true }
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
    let root = if (trimmed) { target.root.slice(0, target.root.length() - 1) } else { target.root };
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

/// One entry of a directory listing. Its own class rather than the one the
/// filesystem module returns, so that what implements the port is not named by
/// the port itself. What is asked of an entry is what it is, and a caller that
/// must not follow a link needs to be told about one before it does.
class DirEntry {
    name: string,
    is_dir: bool,
    is_file: bool,
    is_symlink: bool,
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
    /// What a directory holds, or null when it cannot be listed. Being unable
    /// to list one is not recorded as a failure, for the reason `read` is not:
    /// asking what is in a directory is how a caller finds out whether it is
    /// there at all.
    function read_dir(self, path: string) -> DirEntry[]? throws never
    function mkdir(self, path: string) -> void throws never
    function symlink(self, path: string, points_to: string) -> void throws never
    /// Mode as the octal number a mode is: `0o755`. It is the number rather
    /// than the four characters that spell it because that is what a mode is,
    /// and because nothing below has to parse it back.
    function chmod(self, path: string, mode: int) -> void throws never
}

/// A mode written the way modes are read: four octal digits, so the leading
/// one, which carries setuid, setgid and sticky, is always there to be read.
///
/// It exists because an `int` prints itself in base ten, and `0440` shown as
/// `288` is a mode nobody recognises. Only what shows a mode to a person needs
/// this; everything else carries the number.
function octal_mode(mode: int) -> string {
    let special = (mode / 0o1000) % 8;
    let user = (mode / 0o100) % 8;
    let group = (mode / 0o10) % 8;
    let other = mode % 8;
    `${special}${user}${group}${other}`
}

test "octal_mode spells a mode the way a mode is written" {
    assert.equal(octal_mode(0o440), "0440");
    assert.equal(octal_mode(0o755), "0755");
    assert.equal(octal_mode(0o600), "0600");
    assert.equal(octal_mode(0o2775), "2775")
}

/// Records what would be written instead of writing it, so a phase can be
/// verified by the contents it produces.
class RecordingFiles {
    /// Set by a test to make the next check report a failure.
    fails_with: string?,
    written: map<string, string>,
    directories: string[],
    symlinks: map<string, string>,
    modes: map<string, int>,
    present: string[],

    implements Files {
        function failure(self) -> string? { self.fails_with }
        function write(self, path: string, content: string) -> void {
            let _ = self.written.set(path, content);
        }
        function read(self, path: string) -> string? {
            self.written.get(path)
        }
        /// Everything this double has been told about counts as being there,
        /// including a directory it was asked to make. Anything else would have
        /// it answer that what it just created is not there, which no
        /// filesystem does and no caller should have to work around.
        function exists(self, path: string) -> bool {
            self.present.includes(path)
                || self.written.get(path) != null
                || self.directories.includes(path)
                || self.symlinks.get(path) != null
        }
        /// A listing assembled from what this double has been told about. A
        /// directory it has never heard of cannot be listed, which is what a
        /// real one answers for a path that is not there.
        ///
        /// What a child is, is decided by which list it came from: one that was
        /// made a directory, or that has anything below it, is a directory; one
        /// that was linked is a link; anything else that is known is a file.
        function read_dir(self, path: string) -> DirEntry[]? {
            if (!self.directories.includes(path)) {
                return null;
            }
            let prefix = if (path.ends_with("/")) { path } else { path + "/" };
            let known = self
                .directories
                .concat(self.present)
                .concat(self.written.keys())
                .concat(self.symlinks.keys());

            let named: string[] = [];
            let out: DirEntry[] = [];
            for (let entry in known) {
                if (!entry.starts_with(prefix)) {
                    continue;
                }
                let rest = entry.slice(prefix.length(), entry.length());
                let name = (rest.split("/").at(0)) ?? "";
                if (name == "" || named.includes(name)) {
                    continue;
                }
                named.push(name);

                let child = prefix + name;
                let is_dir = self.directories.includes(child) || rest.includes("/");
                let is_symlink = self.symlinks.get(child) != null;
                out.push(DirEntry {
                    name: name,
                    is_dir: is_dir,
                    is_file: !is_dir && !is_symlink,
                    is_symlink: is_symlink,
                });
            }
            out
        }

        function mkdir(self, path: string) -> void {
            if (!self.directories.includes(path)) { self.directories.push(path); }
        }
        function symlink(self, path: string, points_to: string) -> void {
            let _ = self.symlinks.set(path, points_to);
        }
        function chmod(self, path: string, mode: int) -> void {
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
    assert.equal(target_path(chroot_target("/mnt"), "/etc/hostname"), "/mnt/etc/hostname");
    assert.equal(target_path(chroot_target("/mnt/"), "/etc/hostname"), "/mnt/etc/hostname")
}

test "target_path refuses a relative path" {
    let failed = target_path(chroot_target("/mnt"), "etc/hostname")
        catch (e) { baml.errors.InvalidArgument => "refused" };
    assert.equal(failed, "refused")
}

test "RecordingFiles remembers what a phase produced" {
    let files = recording_files();
    files.write("/etc/hostname", "oparch\n");
    files.mkdir("/var/log");
    files.symlink("/etc/localtime", "/usr/share/zoneinfo/Europe/Madrid");
    files.chmod("/root/script.sh", 0o755);

    assert.equal(files.written.get("/etc/hostname"), "oparch\n");
    assert.equal(files.directories, ["/var/log"]);
    assert.equal(files.symlinks.get("/etc/localtime"), "/usr/share/zoneinfo/Europe/Madrid");
    assert.equal(files.modes.get("/root/script.sh"), 0o755);
    assert.is_true(files.exists("/etc/hostname"));
    assert.is_true(!files.exists("/etc/fstab"))
}

test "RecordingFiles lists what it was told a directory holds" {
    let files = recording_files();
    files.mkdir("/dotfiles");
    files.mkdir("/dotfiles/hypr");
    files.write("/dotfiles/main.dfmap", "[map]\n");
    files.symlink("/dotfiles/link", "/elsewhere");
    files.write("/other/thing", "x");

    let empty: DirEntry[] = [];
    let listed = files.read_dir("/dotfiles") ?? empty;
    let names = listed.map((entry) -> { entry.name });

    assert.equal(names, ["hypr", "main.dfmap", "link"]);
    assert.is_true(listed.find((e) -> { e.name == "hypr" })?.is_dir ?? false);
    assert.is_true(listed.find((e) -> { e.name == "main.dfmap" })?.is_file ?? false);
    assert.is_true(listed.find((e) -> { e.name == "link" })?.is_symlink ?? false)
}

test "a directory nothing knows about cannot be listed" {
    let files = recording_files();
    files.write("/dotfiles/main.dfmap", "[map]\n");

    //# writing into it never said it was there, and a listing that answered
    //# with nothing would be a directory that exists and is empty
    assert.equal(files.read_dir("/dotfiles"), null)
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
