// `oparch-snapshot-work-context-create`: takes a manual snapshot of the home of
// one work context, with the justification it was given. The command is
// documented in `docs/tools/snapshot/work-context-create/000-command.md`; what
// it runs is the snapshot library, and this is its command line.

/// What the command line gave: the work context and the justification, or
/// what is wrong with them.
class Arguments {
    work_context: string,
    justification: string,
    error: string,
}

/// Reads the two arguments the tool takes. The packed executable is handed its
/// own path and the name of its entry point before what it was called with,
/// so what it was called with starts at the third.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    if (given.length() != 2) {
        return Arguments {
            work_context: "",
            justification: "",
            error: "oparch-snapshot-work-context-create takes two arguments, the work context and the justification of the snapshot",
        };
    }
    Arguments { work_context: given.at(0) ?? "", justification: given.at(1) ?? "", error: "" }
}

test "the work context comes first and the justification second" {
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-work-context-create", "main",
                                     "work", "before the client project import"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.work_context, "work");
    assert.equal(arguments.justification, "before the client project import")
}

test "anything but two arguments is refused" {
    let expected = "oparch-snapshot-work-context-create takes two arguments, the work context and the justification of the snapshot";

    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-work-context-create", "main", "work"]).error, expected);
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-work-context-create", "main",
                                  "work", "before", "the import"]).error,
                 expected)
}

function main() -> void {
    let shell = root.common.system_shell();
    let files = root.common.system_files();
    //# before anything else, the arguments included: the tool snapshots a
    //# subvolume and writes under /snapshots, which only root may do
    let refused = root.common.require_root(shell, "oparch-snapshot-work-context-create");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        baml.sys.exit(1);
    }
    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        baml.sys.exit(2);
    }
    let taken = root.snapshot.take_home_snapshot(shell, files, root.snapshot.snapshots_lock(),
                                                 arguments.work_context, root.snapshot.manual_kind(),
                                                 arguments.justification);
    if (taken.error != "") {
        baml.io.eprintln(`error: ${taken.error}`);
        baml.sys.exit(1);
    }
    baml.io.println(taken.path);
}
