// `oparch-snapshot-automatic-create`: takes an automatic snapshot of a scope and
// deletes the automatic snapshots of that scope the retention policy no longer
// keeps. The command is documented in
// `docs/tools/snapshot/automatic-create/000-command.md`; what it runs is the
// snapshot library, and this is its command line.

/// What the command line gave: the scope and, for a home, the work context by
/// name or by UID, or what is wrong with them.
class Arguments {
    scope: string,
    work_context: string,
    error: string,
}

function usage_error() -> Arguments {
    Arguments {
        scope: "",
        work_context: "",
        error: "oparch-snapshot-automatic-create takes a scope, system or home, and for home the work context",
    }
}

/// Reads the scope and the work context. The packed executable is handed its
/// own path and the name of its entry point before what it was called with,
/// so what it was called with starts at the third.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    if (given.length() == 0 || given.length() > 2) {
        return usage_error();
    }
    let scope = given.at(0) ?? "";
    if (scope == "system") {
        if (given.length() != 1) {
            return Arguments { scope: "", work_context: "", error: "the system scope takes no work context" };
        }
        return Arguments { scope: scope, work_context: "", error: "" };
    }
    if (scope == "home") {
        if (given.length() != 2) {
            return Arguments {
                scope: "", work_context: "",
                error: "the home scope takes the work context whose home is snapshotted, by name or by UID",
            };
        }
        return Arguments { scope: scope, work_context: given.at(1) ?? "", error: "" };
    }
    Arguments { scope: "", work_context: "", error: `unknown scope '${scope}': the scope is system or home` }
}

test "the system scope is given alone" {
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "system"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.scope, "system")
}

test "the home scope is given with its work context, by name or by UID" {
    let named = parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "home", "work"]);
    let numbered = parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "home", "1001"]);

    assert.equal(named.error, "");
    assert.equal(named.work_context, "work");
    assert.equal(numbered.work_context, "1001")
}

test "a work context with the system scope is refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "system", "work"]).error,
                 "the system scope takes no work context")
}

test "the home scope without a work context is refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "home"]).error,
                 "the home scope takes the work context whose home is snapshotted, by name or by UID")
}

test "no scope, too many arguments, or a scope that is not one are refused" {
    let usage = "oparch-snapshot-automatic-create takes a scope, system or home, and for home the work context";

    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main"]).error, usage);
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "home", "work", "x"]).error,
                 usage);
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-automatic-create", "main", "dotfiles"]).error,
                 "unknown scope 'dotfiles': the scope is system or home")
}

function main() -> void {
    let shell = root.common.system_shell();
    let files = root.common.system_files();
    //# before anything else, the arguments included: the tool snapshots and
    //# deletes subvolumes and writes under /snapshots, which only root may do
    let refused = root.common.require_root(shell, "oparch-snapshot-automatic-create");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        baml.sys.exit(1);
    }
    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        baml.sys.exit(2);
    }
    let lock = root.snapshot.snapshots_lock();
    let taken = if (arguments.scope == "system") {
        root.snapshot.take_automatic_system_snapshot(shell, files, lock)
    } else {
        root.snapshot.take_automatic_home_snapshot(shell, files, lock, arguments.work_context)
    };
    if (taken.error != "") {
        baml.io.eprintln(`error: ${taken.error}`);
        baml.sys.exit(1);
    }
    baml.io.println(taken.path);
}
