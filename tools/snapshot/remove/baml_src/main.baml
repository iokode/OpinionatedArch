// `oparch-snapshot-remove`: removes one snapshot, with its line in the boot
// table, a set of boot artifacts nothing points at any more, and its label.
// The command is documented in `docs/tools/snapshot/remove/000-command.md`;
// what it runs is the snapshot library, and this is its command line.

/// What the command line gave: the path of the snapshot, or what is wrong with
/// it.
class Arguments {
    snapshot: string,
    error: string,
}

/// Reads the one argument the tool takes. The packed executable is handed its
/// own path and the name of its entry point before what it was called with,
/// so what it was called with starts at the third.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    if (given.length() != 1) {
        return Arguments {
            snapshot: "",
            error: "oparch-snapshot-remove takes one argument, the path of the snapshot as oparch-snapshot-list prints it",
        };
    }
    Arguments { snapshot: given.at(0) ?? "", error: "" }
}

test "the snapshot is the one argument" {
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-remove", "main", "/snapshots/system/manual/@1778764800"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.snapshot, "/snapshots/system/manual/@1778764800")
}

test "no snapshot, or more than one argument, is refused" {
    let expected = "oparch-snapshot-remove takes one argument, the path of the snapshot as oparch-snapshot-list prints it";

    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-remove", "main"]).error, expected);
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-remove", "main",
                                  "/snapshots/system/manual/@1778764800", "/snapshots/system/manual/@1778761200"]).error,
                 expected)
}

function main() -> void {
    let shell = root.common.system_shell();
    let files = root.common.system_files();
    //# before anything else, the arguments included: the tool deletes
    //# subvolumes and writes under /snapshots, which only root may do
    let refused = root.common.require_root(shell, "oparch-snapshot-remove");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        baml.sys.exit(1);
    }
    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        baml.sys.exit(2);
    }
    let removed = root.snapshot.remove_snapshot(shell, files, root.snapshot.snapshots_lock(), arguments.snapshot);
    if (removed != "") {
        baml.io.eprintln(`error: ${removed}`);
        baml.sys.exit(1);
    }
}
