// `oparch-snapshot-system-create`: takes a manual snapshot of the system, with
// the boot artifacts of that moment and the justification it was given. The
// command is documented in `docs/tools/snapshot/system-create/000-command.md`;
// what it runs is the snapshot library, and this is its command line.

/// What the command line gave: the justification, or what is wrong with it.
class Arguments {
    justification: string,
    error: string,
}

/// Reads the one argument the tool takes. The packed executable is handed its
/// own path and the name of its entry point before what it was called with,
/// so what it was called with starts at the third.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    if (given.length() != 1) {
        return Arguments {
            justification: "",
            error: "oparch-snapshot-system-create takes one argument, the justification of the snapshot",
        };
    }
    Arguments { justification: given.at(0) ?? "", error: "" }
}

test "the justification is the one argument, whatever it holds" {
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-system-create", "main", "--before a kernel upgrade"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.justification, "--before a kernel upgrade")
}

test "no justification, or more than one argument, is refused" {
    let expected = "oparch-snapshot-system-create takes one argument, the justification of the snapshot";

    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-system-create", "main"]).error, expected);
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-system-create", "main", "before", "a kernel upgrade"]).error,
                 expected)
}

function main() -> void {
    let shell = root.common.system_shell();
    let files = root.common.system_files();
    //# before anything else, the arguments included: the tool snapshots `/` and
    //# writes under /snapshots, which only root may do
    let refused = root.common.require_root(shell, "oparch-snapshot-system-create");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        baml.sys.exit(1);
    }
    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        baml.sys.exit(2);
    }
    let taken = root.snapshot.take_system_snapshot(shell, files, root.snapshot.snapshots_lock(),
                                                   root.snapshot.manual_kind(), arguments.justification);
    if (taken.error != "") {
        baml.io.eprintln(`error: ${taken.error}`);
        baml.sys.exit(1);
    }
    baml.io.println(taken.path);
}
