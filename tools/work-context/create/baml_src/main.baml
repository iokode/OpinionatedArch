// `oparch-work-context-create`: creates a work context. What it does is the
// work context library's; this is its command line.

/// The name of the work context to create, or why the command line does not
/// give one.
class Arguments {
    name: string,
    error: string,
}

/// Reads the one name this tool takes. The packed executable is called with its
/// own path and the name of its entry point before anything it was given.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    if (given.length() == 0) {
        return Arguments { name: "", error: "the name of the work context to create is required" };
    }
    if (given.length() > 1) {
        return Arguments {
            name: "",
            error: `unexpected argument '${given.at(1) ?? ""}': oparch-work-context-create takes one name`,
        };
    }
    Arguments { name: given.at(0) ?? "", error: "" }
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let shell = root.common.system_shell();
    //# before anything else, the arguments included: what this creates is an
    //# account, a subvolume, a mount and the mount table, and only root may
    let refused = root.common.require_root(shell, "oparch-work-context-create");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        return baml.sys.exit(1);
    }

    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        return baml.sys.exit(2);
    }

    let failed = root.work_context.create_work_context(shell, root.common.system_files(), arguments.name);
    if (failed != "") {
        baml.io.eprintln(`error: ${failed}`);
        return baml.sys.exit(1);
    }
    baml.sys.exit(0)
}

test "the one name given is the work context to create" {
    let arguments = parse_arguments(["/usr/bin/oparch-work-context-create", "main", "project"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.name, "project")
}

test "a command line with no name is refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-work-context-create", "main"]).error,
                 "the name of the work context to create is required")
}

test "a second argument is reported rather than ignored" {
    assert.equal(parse_arguments(["/usr/bin/oparch-work-context-create", "main", "project", "work"]).error,
                 "unexpected argument 'work': oparch-work-context-create takes one name")
}
