// The ports, implemented against the machine BAML is running on.
//
// A tool that needs neither a terminal interface nor incremental output from a
// long command needs no host program: `baml.sys` runs processes and `baml.fs`
// touches files, and `baml pack` turns the tool into a single executable. The
// classes here are what let such a tool use the same `Shell` and `Files` the
// rest of the code is written against, and stay testable with the recording
// doubles beside them.
//
// The installer keeps its host for the reasons in
// `docs/decisions/015-installer-host-bridge.md`.

/// Runs commands with `baml.sys.exec`. A command that cannot be started at all
/// is reported as exit code 127, which is the shell's own code for it, so a
/// caller never has to tell "did not run" from "ran and failed".
class SystemShell {
    /// Added to what a command runs with. Empty leaves the environment this
    /// process was started in, which is what almost everything wants; a value
    /// here replaces it, so anything the command still needs has to be in the
    /// map. It exists because a program can need to be told where to look for
    /// something that is not installed — a font a theme carries, for instance.
    env: map<string, string>,

    function run(self, program: string, args: string[], input: string?) -> CommandResult {
        let environment = if (self.env.keys().length() == 0) { null } else { self.env };
        let output = baml.sys.exec(program, args, baml.sys.ProcessOptions {
            cwd: null, env: environment, timeout_ms: null, stdin: input,
        }) catch (e) {
            _ => {
                return CommandResult { exit_code: 127, stdout: "" };
            }
        };
        CommandResult { exit_code: output.exit_code, stdout: output.stdout.to_string() }
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

        function mkdir(self, path: string) -> void {
            let _ = baml.fs.mkdir(path, baml.fs.MkdirOptions { recursive: true }) catch (e) {
                _ => {
                    self.fail(`cannot create ${path}: ${e.message}`);
                    null
                }
            };
        }

        /// `baml.fs` has neither this nor `chmod` yet, so both go through the
        /// commands that do exactly what they say. Each is still one operation,
        /// and a failure still lands in `failure()`.
        function symlink(self, path: string, points_to: string) -> void {
            let result = system_shell().capture("ln", ["-s", points_to, path]);
            if (result.exit_code != 0) {
                self.fail(`cannot link ${path} to ${points_to}: exit code ${result.exit_code}`);
            }
        }

        function chmod(self, path: string, mode: string) -> void {
            let result = system_shell().capture("chmod", [mode, path]);
            if (result.exit_code != 0) {
                self.fail(`cannot set mode ${mode} on ${path}: exit code ${result.exit_code}`);
            }
        }
    }
}

/// A shell that runs commands the way this process was started.
function system_shell() -> SystemShell {
    SystemShell { env: {} }
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

test "SystemFiles reports an absent file as absent, not as a failure" {
    let files = system_files();

    assert.equal(files.read("/oparch/not/there"), null);
    assert.is_true(!files.exists("/oparch/not/there"));
    assert.equal(files.failure(), null)
}

test "a shell given an environment passes it to the command" {
    let shell = SystemShell { env: { "OPARCH_TEST": "here" } };
    assert.equal(shell.capture("sh", ["-c", "printf %s \"$OPARCH_TEST\""]).stdout, "here");

    //# and one given none leaves the environment alone
    assert.equal(system_shell().capture("sh", ["-c", "test -n \"$PATH\""]).exit_code, 0)
}
