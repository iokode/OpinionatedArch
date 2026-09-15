// `oparch-work-context-remove`: removes a work context. What it does is the
// work context library's; this is its command line.

/// What the command line asks for, or why it asks for nothing.
class Arguments {
    removal: root.work_context.Removal,
    error: string,
}

/// Reads the name and the two options. The packed executable is called with its
/// own path and the name of its entry point before anything it was given.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    let removal = root.work_context.Removal { name: "", preserve_home: "", preserve_snapshots: false };
    let names: string[] = [];
    let index = 0;
    while (index < given.length()) {
        let argument = given.at(index) ?? "";
        if (argument == "--preserve-snapshots") {
            removal.preserve_snapshots = true;
            index = index + 1;
        } else if (argument == "--preserve-home") {
            if let target: string = given.at(index + 1) {
                removal.preserve_home = target;
            } else {
                return Arguments { removal: removal, error: "option '--preserve-home' requires a value" };
            }
            index = index + 2;
        } else if (argument.starts_with("--")) {
            return Arguments { removal: removal, error: `unknown option '${argument}'` };
        } else {
            names.push(argument);
            index = index + 1;
        }
    }
    if (names.length() == 0) {
        return Arguments { removal: removal, error: "the name of the work context to remove is required" };
    }
    if (names.length() > 1) {
        return Arguments {
            removal: removal,
            error: `unexpected argument '${names.at(1) ?? ""}': oparch-work-context-remove takes one name`,
        };
    }
    removal.name = names.at(0) ?? "";
    Arguments { removal: removal, error: "" }
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let shell = root.common.system_shell();
    //# before anything else, the arguments included: what this removes is an
    //# account, a mount, a subvolume, snapshots and a line of the mount table,
    //# and only root may
    let refused = root.common.require_root(shell, "oparch-work-context-remove");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        return baml.sys.exit(1);
    }

    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        return baml.sys.exit(2);
    }

    let removed = root.work_context.remove_work_context(shell, root.common.system_files(),
                                                        root.snapshot.snapshots_lock(), arguments.removal);
    //# where the home was copied to is said even when a later step failed: the
    //# copy is there either way
    if (removed.copy != "") {
        baml.io.println(removed.copy);
    }
    if (removed.error != "") {
        baml.io.eprintln(`error: ${removed.error}`);
        return baml.sys.exit(1);
    }
    baml.sys.exit(0)
}

test "the name alone removes the context and its snapshots, and keeps no home" {
    let arguments = parse_arguments(["/usr/bin/oparch-work-context-remove", "main", "project"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.removal.name, "project");
    assert.equal(arguments.removal.preserve_home, "");
    assert.is_true(!arguments.removal.preserve_snapshots)
}

test "the options may come before or after the name" {
    let arguments = parse_arguments(["/usr/bin/oparch-work-context-remove", "main",
                                     "--preserve-home", "personal", "project", "--preserve-snapshots"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.removal.name, "project");
    assert.equal(arguments.removal.preserve_home, "personal");
    assert.is_true(arguments.removal.preserve_snapshots)
}

test "a command line that does not name one context is refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-work-context-remove", "main"]).error,
                 "the name of the work context to remove is required");
    assert.equal(parse_arguments(["/usr/bin/oparch-work-context-remove", "main", "project", "work"]).error,
                 "unexpected argument 'work': oparch-work-context-remove takes one name")
}

test "an option without its value, or one nobody has heard of, is refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-work-context-remove", "main", "project", "--preserve-home"]).error,
                 "option '--preserve-home' requires a value");
    assert.equal(parse_arguments(["/usr/bin/oparch-work-context-remove", "main", "project", "--force"]).error,
                 "unknown option '--force'")
}
