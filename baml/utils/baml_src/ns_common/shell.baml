// Running external commands. Every OpinionatedArch tool needs this, so it
// lives here rather than in any single tool.

/// The result of running an external command. The host produces these; BAML
/// only ever reads them.
class CommandResult {
    exit_code: int,
    stdout: string,
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

/// Wraps the closure the host passes at the entrypoint. Interfaces cannot
/// cross the bridge (see docs/decisions/015-installer-host-bridge.md), so this is where
/// a plain callback becomes a `Shell`.
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

    function record(self, program: string, args: string[]) -> CommandResult {
        let line = `${program} ${args.join(" ")}`.trim();
        self.commands.push(line);
        CommandResult {
            exit_code: self.exit_codes.get(line) ?? 0,
            stdout: self.replies.get(line) ?? "",
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

/// Turns a command result into an error message, or "" when it succeeded.
/// Used so a phase reads as a sequence of checked steps: a command whose
/// failure is ignored is a command that corrupts the next one silently.
function must(result: CommandResult, what: string) -> string {
    if (result.exit_code != 0) {
        return `${what} failed with exit code ${result.exit_code}.`;
    }
    ""
}

test "must reports the failure and stays quiet on success" {
    assert.equal(must(CommandResult { exit_code: 0, stdout: "" }, "mount"), "");
    assert.equal(must(CommandResult { exit_code: 32, stdout: "" }, "mount"),
                 "mount failed with exit code 32.")
}
