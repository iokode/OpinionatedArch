// Which user a tool runs as. A tool that reads or writes what only root may
// refuses every other user before it does anything else, and this is the check
// it makes.

/// An error message when this process does not run as root, or "" when it does.
/// `tool` is the name the message gives whoever is refusing. `id -u` answers
/// with the effective user, so a run through `sudo` is root's.
///
/// A user id that cannot be read is a refusal too: a tool that took it for root
/// would go on to do what it refuses everyone else.
function require_root(shell: Shell, tool: string) -> string {
    let user_id = shell.capture("id", ["-u"]);
    let failed = must(user_id, "reading the user id this runs as");
    if (failed != "") {
        return failed;
    }
    if (user_id.stdout.trim() != "0") {
        return `${tool} must be run as root`;
    }
    ""
}

test "a run as root goes on" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: { "id -u": "0\n" }, exit_codes: {} };

    assert.equal(require_root(shell, "oparch-tool"), "");
    assert.equal(shell.commands, ["id -u"])
}

test "a run as any other user is refused in the name of the tool" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: { "id -u": "1000\n" }, exit_codes: {} };

    assert.equal(require_root(shell, "oparch-tool"), "oparch-tool must be run as root")
}

test "a user id that cannot be read is refused rather than taken for root" {
    let shell = RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: { "id -u": 1 } };

    assert.equal(require_root(shell, "oparch-tool"),
                 "reading the user id this runs as failed with exit code 1.")
}
