// The work contexts of a machine: the accounts that are members of the group
// that marks them, as `docs/decisions/000-work-contexts-and-accounts.md`
// decides. Other accounts exist on the same machine, so which contexts there
// are is read from that group and from nothing else.

/// The group whose members are the work contexts of a machine.
function work_contexts_group() -> string {
    "work-contexts"
}

/// The work contexts read from a machine, or why they could not be read.
class WorkContexts {
    names: string[],
    /// "" when the names were read.
    error: string,
}

/// The members of `work-contexts`, in the order the group lists them. A group
/// with no members is a machine with no work contexts, which is an answer and
/// not a failure.
function list_work_contexts(shell: root.common.Shell) -> WorkContexts {
    let group = shell.capture("getent", ["group", work_contexts_group()]);
    let failed = root.common.must(group, `reading the '${work_contexts_group()}' group`);
    if (failed != "") {
        return WorkContexts { names: [], error: failed };
    }
    let names = (group.stdout.trim().split(":").at(3) ?? "")
        .split(",")
        .filter(
            (name) -> {
                name != ""
            },
        );
    WorkContexts { names: names, error: "" }
}

// -------------------------------------------------------------------- tests

function contexts_shell(replies: map<string, string>, exit_codes: map<string, int>) -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: replies, exit_codes: exit_codes,
    }
}

test "the work contexts are the members of the group, in its order" {
    let shell = contexts_shell({ "getent group work-contexts": "work-contexts:x:1002:personal,work\n" }, {});

    let contexts = list_work_contexts(shell);

    assert.equal(contexts.error, "");
    assert.equal(contexts.names, ["personal", "work"]);
    assert.equal(shell.commands, ["getent group work-contexts"])
}

test "a group with no members is a machine with no work contexts" {
    let shell = contexts_shell({ "getent group work-contexts": "work-contexts:x:1002:\n" }, {});

    let contexts = list_work_contexts(shell);

    assert.equal(contexts.error, "");
    assert.equal(contexts.names, [])
}

test "a group that cannot be read is reported as the command that failed" {
    let shell = contexts_shell({}, { "getent group work-contexts": 1 });

    assert.equal(list_work_contexts(shell).error,
                 "reading the 'work-contexts' group failed with exit code 1.")
}
