// `oparch-work-context-list`: the work contexts of the machine, one name per
// line. What it reads is the work context library; this is its command line.
//
// It takes no arguments and needs no privileges: the group it reads is readable
// by every account.

/// What the command line was given after the invocation itself. The packed
/// executable is called with its own path and the name of its entry point
/// before anything it was given.
function given_arguments(argv: string[]) -> string[] {
    argv.slice(2, argv.length())
}

/// A message for arguments this tool does not take, or "" when it was given
/// none.
function unexpected_arguments(argv: string[]) -> string {
    let given = given_arguments(argv);
    if (given.length() > 0) {
        return `unexpected argument '${given.at(0) ?? ""}': oparch-work-context-list takes no arguments`;
    }
    ""
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let refused = unexpected_arguments(baml.sys.argv());
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        return baml.sys.exit(2);
    }

    let contexts = root.work_context.list_work_contexts(root.common.system_shell());
    if (contexts.error != "") {
        baml.io.eprintln(`error: ${contexts.error}`);
        return baml.sys.exit(1);
    }
    for (let name in contexts.names) {
        baml.io.println(name);
    }
    baml.sys.exit(0)
}

test "a run with no arguments is a run" {
    assert.equal(unexpected_arguments(["/usr/bin/oparch-work-context-list", "main"]), "")
}

test "an argument is reported rather than ignored" {
    assert.equal(unexpected_arguments(["/usr/bin/oparch-work-context-list", "main", "--all"]),
                 "unexpected argument '--all': oparch-work-context-list takes no arguments")
}
