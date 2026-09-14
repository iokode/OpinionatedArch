// The one lock every operation that writes the boot table, the labels file or
// a set of boot artifacts holds, as
// `docs/tools/snapshot/system-create/003-storage-lock.md` specifies.

/// The lock file, inside `@snapshots`.
function lock_path() -> string {
    "lock"
}

/// Holding the lock. It is a port because what holds it is a process outside
/// this one, and a test puts a double where that process would be.
interface SnapshotLock {
    /// Waits until the lock is held by this run, however long that takes. ""
    /// once it is, or what stopped it from being taken.
    function acquire(self) -> string throws never

    /// Gives the lock back. Nothing happens when it is not held.
    function release(self) -> null throws never
}

/// Holds the lock through `flock`, which takes it and then runs `cat` for as
/// long as the lock is wanted.
///
/// `cat` starts only once `flock` holds the lock, so the line written to it is
/// read back only then, and that line is how this knows the lock is held.
/// Closing its input ends `cat`, and `flock` gives the lock back as it exits.
/// The same happens when this process ends without releasing it, however it
/// ends: the input closes with it, so a run that is killed half way leaves no
/// lock behind.
class FlockLock {
    path: string,
    holder: baml.sys.Process?,

    implements SnapshotLock {
        function acquire(self) -> string {
            let process = baml.sys.start_process("flock", ["--exclusive", self.path, "cat"],
                baml.sys.ProcessOptions {
                    cwd: null, env: null, timeout_ms: null, stdin: null, keep_stdin_open: true,
                }) catch (e) {
                _ => {
                    return `cannot take the lock ${self.path}`;
                }
            };
            let written = process.write_stdin("held\n") catch (e) {
                _ => {
                    process.close();
                    return `cannot take the lock ${self.path}`;
                }
            };
            let answer = process.stdout._next() catch (e) {
                _ => null
            };
            if (answer != "held") {
                process.close();
                return `cannot take the lock ${self.path}`;
            }
            self.holder = process;
            ""
        }

        function release(self) -> null {
            if let process: baml.sys.Process = self.holder {
                let _ = process.close_stdin() catch (e) {
                    _ => null
                };
                let _ = process.wait() catch (e) {
                    _ => null
                };
                self.holder = null;
            }
            null
        }
    }
}

/// The lock of the `@snapshots` this machine mounts.
function snapshots_lock() -> FlockLock {
    FlockLock { path: in_snapshots(lock_path()), holder: null }
}

test "a lock that is held is refused to anyone else until it is given back" {
    let path = `${baml.env.get("TMPDIR") ?? "/tmp"}/oparch-snapshot-lock-test`;
    let lock = FlockLock { path: path, holder: null };
    let shell = root.common.system_shell();

    assert.equal(lock.acquire(), "");
    assert.equal(shell.capture("flock", ["--nonblock", path, "true"]).exit_code, 1);
    lock.release();
    assert.equal(shell.capture("flock", ["--nonblock", path, "true"]).exit_code, 0);
    let _ = baml.fs.remove(path) catch (e) { _ => null }
}

test "a lock that cannot be made is reported rather than taken" {
    let lock = FlockLock { path: "/oparch/not/there/lock", holder: null };

    assert.equal(lock.acquire(), "cannot take the lock /oparch/not/there/lock");
    lock.release()
}

/// Records taking and giving back the lock in the command log of the shell a
/// test uses, so that the test reads one sequence and sees what was done while
/// the lock was held.
class RecordingLock {
    shell: root.common.RecordingShell,
    /// What taking it answers. "" takes it.
    fails_with: string,

    implements SnapshotLock {
        function acquire(self) -> string {
            self.shell.commands.push("lock /snapshots/lock");
            self.fails_with
        }
        function release(self) -> null {
            self.shell.commands.push("unlock /snapshots/lock");
            null
        }
    }
}

function recording_lock(shell: root.common.RecordingShell) -> RecordingLock {
    RecordingLock { shell: shell, fails_with: "" }
}
