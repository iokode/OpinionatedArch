// Running external commands. Every OpinionatedArch tool needs this, so it
// lives here rather than in any single tool.

/// The result of running an external command. The host produces these; BAML
/// only ever reads them.
class CommandResult {
    exit_code: int,
    stdout: string,
    /// What the command wrote to standard error, empty when it wrote nothing.
    /// Every implementation fills it: a caller cannot tell "said nothing" from
    /// "was thrown away", so an implementation that cannot capture it would
    /// make the field a lie for everyone else.
    ///
    /// A tool with a log shows this there and keeps its messages short; a tool
    /// whose only channel is the message it prints puts it in the message.
    /// Which of the two a tool is, is the tool's own decision.
    stderr: string,

    function ok(self) -> bool {
        self.exit_code == 0
    }
}

/// Running a command for its output and running a long operation the user
/// should watch are different contracts, and the caller is the one who knows
/// which is which. Keeping them apart is what stops a command that merely
/// produces data from paying the cost of a progress pipeline.
interface Shell {
    /// Runs a command for its output. Nothing is reported while it runs.
    function capture(self, program: string, args: string[]) -> CommandResult throws never

    /// Runs a long operation whose progress the user should see. The host
    /// reads its output as it is produced and reports on it.
    function stream(self, program: string, args: string[]) -> CommandResult throws never

    /// Runs a command that reads from standard input. Secrets are passed this
    /// way so they never appear in a command line, where any user of the
    /// machine could read them from the process list.
    function feed(self, program: string, args: string[], input: string) -> CommandResult throws never
}

/// Wraps the closures a host program passes at an entrypoint. An interface
/// cannot cross a generated SDK boundary (see
/// `docs/development/004-host-bridge.md`), so a caller that runs its commands
/// through another language hands over plain callbacks; this is where they
/// become a `Shell` again, and the last place anything knows they were.
class HostShell {
    on_capture: (string, string[]) -> CommandResult throws never,
    on_stream: (string, string[]) -> CommandResult throws never,
    on_feed: (string, string[], string) -> CommandResult throws never,
    implements Shell {
        function capture(self, program: string, args: string[]) -> CommandResult {
            self.on_capture(program, args)
        }
        function stream(self, program: string, args: string[]) -> CommandResult {
            self.on_stream(program, args)
        }
        function feed(self, program: string, args: string[], input: string) -> CommandResult {
            self.on_feed(program, args, input)
        }
    }
}

/// Records commands instead of running them, and replies with canned output
/// keyed by the full command line. This is what makes a flow testable with no
/// host, no bridge and no privileges.
class RecordingShell {
    commands: string[],
    streamed: string[],
    /// Commands that were given something on standard input. The input itself
    /// is never kept, so a test cannot accidentally assert on a secret.
    fed: string[],
    replies: map<string, string>,
    /// Commands that should fail, and with what code. Anything absent succeeds.
    exit_codes: map<string, int>,

    /// A scripted command says nothing on standard error. There is no map for
    /// it because no test has needed one yet; the day one does, it is added
    /// here beside `replies` and every existing literal keeps working.
    function record(self, program: string, args: string[]) -> CommandResult {
        let line = `${program} ${args.join(" ")}`.trim();
        self.commands.push(line);
        CommandResult {
            exit_code: self.exit_codes.get(line) ?? 0,
            stdout: self.replies.get(line) ?? "",
            stderr: "",
        }
    }

    implements Shell {
        function capture(self, program: string, args: string[]) -> CommandResult {
            self.record(program, args)
        }
        function stream(self, program: string, args: string[]) -> CommandResult {
            self.streamed.push(`${program} ${args.join(" ")}`.trim());
            self.record(program, args)
        }
        /// The input is deliberately not recorded: it carries secrets.
        function feed(self, program: string, args: string[], input: string) -> CommandResult {
            self.fed.push(`${program} ${args.join(" ")}`.trim());
            self.record(program, args)
        }
    }
}

test "RecordingShell records the command line and replays canned output" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: { "echo hi": "hi\n" }, exit_codes: {} };
    let result = shell.capture("echo", ["hi"]);

    assert.equal(result.stdout, "hi\n");
    assert.equal(result.exit_code, 0);
    assert.equal(shell.commands, ["echo hi"])
}

test "RecordingShell returns empty output for an unscripted command" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };
    assert.equal(shell.capture("lsblk", []).stdout, "")
}

test "RecordingShell can script a failing command" {
    let shell = RecordingShell {
        commands: [],
        fed: [],
        streamed: [],
        replies: {},
        exit_codes: { "test -b /dev/nope": 1 },
    };
    assert.equal(shell.capture("test", ["-b", "/dev/nope"]).exit_code, 1);
    assert.equal(shell.capture("test", ["-b", "/dev/sda"]).exit_code, 0)
}

test "RecordingShell tells the two contracts apart" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };
    let _ = shell.capture("lsblk", ["-dpno", "NAME,TYPE"]);
    let _ = shell.stream("pacstrap", ["-K", "/mnt", "base"]);

    assert.equal(shell.commands, ["lsblk -dpno NAME,TYPE", "pacstrap -K /mnt base"]);
    assert.equal(shell.streamed, ["pacstrap -K /mnt base"])
}

test "feed keeps the input out of everything it records" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };
    let secret = "correct horse battery staple";

    let _ = shell.feed("cryptsetup", ["luksFormat", "--key-file", "-", "/dev/sda2"], secret);

    assert.equal(shell.fed, ["cryptsetup luksFormat --key-file - /dev/sda2"]);
    assert.equal(shell.commands, ["cryptsetup luksFormat --key-file - /dev/sda2"]);
    assert.is_true(!shell.commands.join(" ").includes(secret));
    assert.is_true(!shell.fed.join(" ").includes(secret))
}

/// A shell that gives every command a few environment variables on top of the
/// ones it already inherits, whatever shell underneath actually runs them.
///
/// The variables are handed over through `env`, which is a program and not a
/// property of the process, so this reads the same through every
/// implementation: the recording one sees them in the line it writes down, and
/// a command entered into another root gets them with it. Adding to the
/// environment rather than replacing it is what keeps a command's own `PATH`,
/// `HOME` and locale, which it needs as much as it needs the variable being set.
class ShellWithEnv {
    inner: Shell,
    env: map<string, string>,

    /// `env K=V ... program args`, wrapping whatever it was given.
    ///
    /// When the command is one being entered into another root, the wrapping
    /// happens outside: `env K=V arch-chroot /root program`, and not
    /// `arch-chroot /root env K=V program`. What is assumed is that neither
    /// `arch-chroot` nor `chroot` clears the environment, so what is set out
    /// here is still set for the command that ends up running inside. That
    /// holds, and it is why this can wrap a shell rather than being threaded
    /// through every caller that runs a command.
    ///
    /// The narrower form — the variables written inside the root, next to the
    /// program they are for — would not rest on that assumption. It is not what
    /// is done here because only the function that builds the chroot line could
    /// place them there, and then a caller wanting an environment would have to
    /// carry it down to every command it eventually runs.
    function prefixed(self, program: string, args: string[]) -> string[] {
        let out: string[] = [];
        for (let name in self.env.keys()) {
            out.push(`${name}=${self.env.get(name) ?? ""}`);
        }
        out.push(program);
        out.concat(args)
    }

    implements Shell {
        function capture(self, program: string, args: string[]) -> CommandResult {
            self.inner.capture("env", self.prefixed(program, args))
        }
        function stream(self, program: string, args: string[]) -> CommandResult {
            self.inner.stream("env", self.prefixed(program, args))
        }
        function feed(self, program: string, args: string[], input: string) -> CommandResult {
            self.inner.feed("env", self.prefixed(program, args), input)
        }
    }
}

/// The same shell, with variables added to what its commands run with. Asking
/// for none gives the shell back untouched, so nothing runs through `env` that
/// had no reason to.
function with_env(shell: Shell, env: map<string, string>) -> Shell {
    if (env.keys().length() == 0) {
        return shell;
    }
    ShellWithEnv { inner: shell, env: env }
}

test "a shell with an environment hands it over in front of the command" {
    let recorded = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };
    let shell = with_env(recorded, { "XDG_DATA_HOME": "/theme" });

    let _ = shell.capture("magick", ["-size", "10x10", "xc:none"]);

    assert.equal(recorded.commands, ["env XDG_DATA_HOME=/theme magick -size 10x10 xc:none"])
}

test "asking for no environment leaves the shell as it was" {
    let recorded = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    let _ = with_env(recorded, {}).capture("identify", ["-format", "%w", "logo.png"]);

    assert.equal(recorded.commands, ["identify -format %w logo.png"])
}

test "an environment reaches a command entered into another root" {
    let recorded = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };
    let shell = with_env(recorded, { "LC_ALL": "C.UTF-8" });

    let _ = run_in(shell, chroot_target("/mnt"), "fold", ["-s", "-w", "40"]);
    let _ = feed_in(shell, local_target(), "chpasswd", [], "user:secret\n");

    assert.equal(recorded.commands, [
        "env LC_ALL=C.UTF-8 arch-chroot /mnt fold -s -w 40",
        "env LC_ALL=C.UTF-8 chpasswd",
    ])
}

test "the environment a shell adds is really added, not put in place of the rest" {
    let plain = system_shell().capture("sh", ["-c", "printf %s \"${PATH:-EMPTY}\""]).stdout;
    let with_theme = with_env(system_shell(), { "XDG_DATA_HOME": "/theme" });

    assert.equal(with_theme.capture("sh", ["-c", "printf %s \"$XDG_DATA_HOME\""]).stdout, "/theme");
    //# the whole reason for going through `env`: a command keeps what it had
    assert.equal(with_theme.capture("sh", ["-c", "printf %s \"${PATH:-EMPTY}\""]).stdout, plain);
    assert.is_true(plain != "EMPTY")
}

/// Turns a command result into an error message, or "" when it succeeded.
/// Used so a phase reads as a sequence of checked steps: a command whose
/// failure is ignored is a command that corrupts the next one silently.
///
/// Everything the command said on standard error is carried, in full and in
/// order. What went wrong is not always in the first line or in the last one,
/// and a message that keeps one of them decides for the reader which part of
/// the failure mattered. What it wrote to standard output stays in the log,
/// where the verbose level governs it.
function must(result: CommandResult, what: string) -> string {
    if (result.exit_code == 0) {
        return "";
    }
    let complaint = nonempty_lines(result.stderr);
    if (complaint.length() == 0) {
        return `${what} failed with exit code ${result.exit_code}.`;
    }
    `${what} failed with exit code ${result.exit_code}:` + "\n" + complaint.join("\n")
}

test "must reports the failure and stays quiet on success" {
    assert.equal(must(CommandResult { exit_code: 0, stdout: "", stderr: "" }, "mount"), "");
    assert.equal(must(CommandResult { exit_code: 32, stdout: "", stderr: "" }, "mount"),
                 "mount failed with exit code 32.")
}

test "must carries every line of what the command complained about" {
    let refused = CommandResult {
        exit_code: 1,
        stdout: "resolving dependencies...\n",
        stderr: "error: target not found: ipxe\nerror: failed to commit transaction\n",
    };

    assert.equal(must(refused, "Installing the base system"),
                 "Installing the base system failed with exit code 1:\n"
                     + "error: target not found: ipxe\n"
                     + "error: failed to commit transaction");

    //# what it printed to standard output belongs to the log, not to the message
    assert.is_true(!must(refused, "Installing the base system").includes("resolving"))
}

test "a command that fails without a word is still reported" {
    assert.equal(must(CommandResult { exit_code: 1, stdout: "", stderr: "  \n\n" }, "cp"),
                 "cp failed with exit code 1.")
}

// ------------------------------------------------- running against a target

/// Runs a command against a target: directly when the target is the system this
/// program runs on or a volume that is merely mounted, and inside the target
/// when it is one the command has to see as its own root.
///
/// Where a command runs is a property of the target it is aimed at, not of
/// whoever aims it, which is why the answer is here and not above: a caller
/// that only ever works on the system it runs on passes a local target and
/// never has to know the other case exists.
function run_in(shell: Shell, target: Target, program: string, args: string[]) -> CommandResult {
    if (target.uses_chroot) {
        shell.capture("arch-chroot", [target.root, program].concat(args))
    } else {
        shell.capture(program, args)
    }
}

/// The same, for a command that reads from standard input. Secrets travel this
/// way whether or not a chroot is entered.
function feed_in(shell: Shell, target: Target, program: string, args: string[],
                 input: string) -> CommandResult {
    if (target.uses_chroot) {
        shell.feed("arch-chroot", [target.root, program].concat(args), input)
    } else {
        shell.feed(program, args, input)
    }
}

test "a local target runs commands directly, and a chroot target inside itself" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} };

    let _ = run_in(shell, local_target(), "locale-gen", []);
    let _ = run_in(shell, chroot_target("/mnt"), "locale-gen", []);
    let _ = feed_in(shell, chroot_target("/mnt"), "chpasswd", [], "user:secret\n");

    assert.equal(shell.commands, [
        "locale-gen",
        "arch-chroot /mnt locale-gen",
        "arch-chroot /mnt chpasswd",
    ])
}

test "a target that is entered is still written to by path" {
    let target = chroot_target("/mnt");

    //# entering it is for commands; files are written into it directly, and the
    //# same target answers both questions
    assert.equal(target_path(target, "/etc/fstab"), "/mnt/etc/fstab")
}

test "ok is the exit code read as a yes or a no" {
    assert.is_true(CommandResult { exit_code: 0, stdout: "", stderr: "" }.ok());
    assert.is_true(!CommandResult { exit_code: 1, stdout: "", stderr: "boom\n" }.ok())
}
