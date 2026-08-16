// The ports, implemented against the machine BAML is running on.
//
// A tool that needs neither a terminal interface nor incremental output from a
// long command needs no host program: `baml.sys` runs processes and `baml.fs`
// touches files, and `baml pack` turns the tool into a single executable. The
// classes here are what let such a tool use the same `Shell` and `Files` the
// rest of the code is written against, and stay testable with the recording
// doubles beside them.
//
// A caller that does need one of those two things keeps a host program, and its
// commands arrive through `HostShell` instead, for the reasons in
// `docs/development/004-host-bridge.md`. Only commands do: touching a file needs
// neither a terminal nor output read as it is produced, so `SystemFiles` is what
// every caller uses, host or no host. Nothing here knows which is which, and
// nothing here should.

/// Runs commands with `baml.sys.exec`. A command that cannot be started at all
/// is reported as exit code 127, which is the shell's own code for it, so a
/// caller never has to tell "did not run" from "ran and failed".
///
/// Commands run with the environment this process was started in. Giving one
/// its own variables is `with_env`'s job.
class SystemShell {
    function run(self, program: string, args: string[], input: string?) -> CommandResult {
        let output = baml.sys.exec(program, args, baml.sys.ProcessOptions {
            cwd: null, env: null, timeout_ms: null, stdin: input,
        }) catch (e) {
            _ => {
                return CommandResult { exit_code: 127, stdout: "", stderr: "" };
            }
        };
        CommandResult {
            exit_code: output.exit_code,
            stdout: output.stdout.to_string(),
            stderr: output.stderr.to_string(),
        }
    }

    implements Shell {
        function capture(self, program: string, args: string[]) -> CommandResult {
            self.run(program, args, null)
        }
        /// Nothing is reported while it runs: reporting progress is what a host
        /// exists for, and a tool with no host has no one to report to.
        function stream(self, program: string, args: string[]) -> CommandResult {
            self.run(program, args, null)
        }
        function feed(self, program: string, args: string[], input: string) -> CommandResult {
            self.run(program, args, input)
        }
    }
}

/// Touches files with `baml.fs`, remembering the first failure rather than
/// returning one per call, which is the contract `Files` defines.
class SystemFiles {
    first_failure: string?,

    function fail(self, message: string) -> void {
        if (self.first_failure == null) {
            self.first_failure = message;
        }
    }

    implements Files {
        function failure(self) -> string? {
            self.first_failure
        }

        function write(self, path: string, content: string) -> void {
            let _ = baml.fs.write(path, content) catch (e) {
                _ => {
                    self.fail(`cannot write ${path}: ${e.message}`);
                    0
                }
            };
        }

        /// A file that cannot be read is absent as far as a caller is
        /// concerned, and absence is already part of the contract. It is not
        /// recorded as a failure: reading a file that may not be there is how
        /// callers ask whether it is.
        function read(self, path: string) -> string? {
            baml.fs.read(path) catch (e) {
                _ => null
            }
        }

        function exists(self, path: string) -> bool {
            baml.fs.exists(path) catch (e) {
                _ => false
            }
        }

        /// The listing carried into the port's own entry, so that nothing above
        /// the port names the filesystem module the entries came from.
        function read_dir(self, path: string) -> DirEntry[]? {
            let listed = baml.fs.read_dir(path) catch (e) {
                _ => {
                    return null;
                }
            };
            listed
                .map(
                    (entry) -> {
                        DirEntry {
                            name: entry.name,
                            is_dir: entry.is_dir,
                            is_file: entry.is_file,
                            is_symlink: entry.is_symlink,
                        }
                    },
                )
        }

        function mkdir(self, path: string) -> void {
            let _ = baml.fs.mkdir(path, baml.fs.MkdirOptions { recursive: true }) catch (e) {
                _ => {
                    self.fail(`cannot create ${path}: ${e.message}`);
                    null
                }
            };
        }

        /// `baml.fs.symlink` is given what the link points to first and where
        /// the link goes second, which is the order `ln` takes them in and the
        /// reverse of the one this port reads in. The two are swapped here,
        /// where the difference is one line, rather than at every call.
        function symlink(self, path: string, points_to: string) -> void {
            let _ = baml.fs.symlink(points_to, path) catch (e) {
                _ => {
                    self.fail(`cannot link ${path} to ${points_to}: ${e.message}`);
                    null
                }
            };
        }

        /// A mode that is not a mode at all is `InvalidArgument` rather than
        /// `Io`, and both land in `failure()` the same way: what the caller was
        /// trying to do, then what went wrong with it.
        function chmod(self, path: string, mode: int) -> void {
            let _ = baml.fs.chmod(path, mode) catch (e) {
                _ => {
                    self.fail(`cannot set mode ${octal_mode(mode)} on ${path}: ${e.message}`);
                    null
                }
            };
        }
    }
}

/// A shell that runs commands the way this process was started.
function system_shell() -> SystemShell {
    SystemShell {}
}

function system_files() -> SystemFiles {
    SystemFiles { first_failure: null }
}

test "SystemShell reports the exit code and the output of a real command" {
    let shell = system_shell();

    assert.equal(shell.capture("echo", ["hello"]).stdout, "hello\n");
    assert.equal(shell.capture("echo", ["hello"]).exit_code, 0);
    assert.equal(shell.capture("false", []).exit_code, 1)
}

test "SystemShell reports a program that cannot be run as 127" {
    assert.equal(system_shell().capture("oparch-no-such-program", []).exit_code, 127)
}

test "SystemShell feeds standard input to the command" {
    assert.equal(system_shell().feed("cat", [], "secret\n").stdout, "secret\n")
}

test "SystemShell keeps the two streams apart and keeps both" {
    let result = system_shell().capture("sh", ["-c", "printf out; printf err >&2; exit 3"]);

    assert.equal(result.stdout, "out");
    assert.equal(result.stderr, "err");
    assert.equal(result.exit_code, 3);
    assert.is_true(!result.ok())
}

test "a command that says nothing on standard error reports it as empty" {
    let result = system_shell().capture("echo", ["hello"]);

    assert.equal(result.stderr, "");
    assert.is_true(result.ok())
}

test "SystemFiles keeps the first failure and only the first" {
    let files = system_files();
    assert.equal(files.failure(), null);

    files.write("/proc/oparch/nowhere", "x");
    let first = files.failure();
    files.write("/proc/oparch/nowhere-either", "x");

    assert.is_true(first != null);
    assert.equal(files.failure(), first)
}

test "SystemFiles reads back what it wrote" {
    let files = system_files();
    let path = `${baml.env.get("TMPDIR") ?? "/tmp"}/oparch-system-files-test.txt`;

    files.write(path, "written\n");

    assert.equal(files.failure(), null);
    assert.is_true(files.exists(path));
    assert.equal(files.read(path), "written\n");
    let _ = baml.fs.remove(path) catch (e) { _ => null }
}

test "a mode that cannot be set is reported the way a write that fails is" {
    let files = system_files();
    let opening = "cannot set mode 0644 on /oparch/not/there: ";

    files.chmod("/oparch/not/there", 0o644);
    let said = files.failure() ?? "";

    //# the same shape `write` and `mkdir` produce: what was being done, then
    //# what went wrong. The words for a path that is not there are the
    //# runtime's own, so what is asserted is that they are carried at all
    assert.is_true(said.starts_with(opening));
    assert.is_true(said.length() > opening.length())
}

test "SystemFiles makes the link where it was asked for, pointing where it was told" {
    let files = system_files();
    let directory = `${baml.env.get("TMPDIR") ?? "/tmp"}/oparch-system-files-link`;
    let link = `${directory}/localtime`;
    let _ = baml.fs.remove(link) catch (e) { _ => null };
    files.mkdir(directory);

    //# what it points to is not there on purpose: the two arguments are given
    //# to `baml.fs.symlink` in the opposite order to the one this port reads
    //# in, so a swap is what can be wrong here, and a link to nothing is a link
    files.symlink(link, "/oparch/not/there");

    assert.equal(files.failure(), null);
    let empty: DirEntry[] = [];
    let listed = files.read_dir(directory) ?? empty;
    assert.is_true(listed.find((entry) -> { entry.name == "localtime" })?.is_symlink ?? false);
    let _ = baml.fs.remove(link) catch (e) { _ => null };
    let _ = baml.fs.remove_dir(directory) catch (e) { _ => null }
}

test "SystemFiles reports an absent file as absent, not as a failure" {
    let files = system_files();

    assert.equal(files.read("/oparch/not/there"), null);
    assert.is_true(!files.exists("/oparch/not/there"));
    assert.equal(files.failure(), null)
}

test "a shell left alone runs commands in the environment this process has" {
    assert.equal(system_shell().capture("sh", ["-c", "test -n \"$PATH\""]).exit_code, 0)
}
