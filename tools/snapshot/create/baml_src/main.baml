// `oparch-snapshot-create`: takes a snapshot of the system or of the home of a
// work context, manual with the justification it was given, or automatic with
// the retention that follows it. The command is documented in
// `docs/tools/snapshot/create/000-command.md`; what it runs is the snapshot
// library, and this is its command line.

/// What the command line gave: the scope, for a home the work context by name
/// or by UID, whether the snapshot is automatic, and the justification of a
/// manual one, or what is wrong with them.
class Arguments {
    scope: string,
    work_context: string,
    automatic: bool,
    justification: string,
    error: string,
}

function refused_arguments(error: string) -> Arguments {
    Arguments { scope: "", work_context: "", automatic: false, justification: "", error: error }
}

/// Reads the scope, the work context and the kind of snapshot. The packed
/// executable is handed its own path and the name of its entry point before
/// what it was called with, so what it was called with starts at the third.
function parse_arguments(argv: string[]) -> Arguments {
    let given = argv.slice(2, argv.length());
    let positional: string[] = [];
    let kinds = 0;
    let automatic = false;
    let justification = "";
    let index = 0;
    while (index < given.length()) {
        let argument = given.at(index) ?? "";
        if (argument == "--automatic") {
            automatic = true;
            kinds = kinds + 1;
            index = index + 1;
        } else if (argument == "--justification") {
            let text = given.at(index + 1);
            if (text == null) {
                return refused_arguments("option '--justification' requires a value");
            }
            justification = text ?? "";
            kinds = kinds + 1;
            index = index + 2;
        } else if (argument.starts_with("--")) {
            return refused_arguments(`unknown option '${argument}'`);
        } else {
            positional.push(argument);
            index = index + 1;
        }
    }
    if (positional.length() == 0 || positional.length() > 2) {
        return refused_arguments("oparch-snapshot-create takes a scope, system or home, and for home the work context");
    }
    let scope = positional.at(0) ?? "";
    if (scope != "system" && scope != "home") {
        return refused_arguments(`unknown scope '${scope}': the scope is system or home`);
    }
    if (scope == "system" && positional.length() != 1) {
        return refused_arguments("the system scope takes no work context");
    }
    if (scope == "home" && positional.length() != 2) {
        return refused_arguments("the home scope takes the work context whose home is snapshotted, by name or by UID");
    }
    if (kinds != 1) {
        return refused_arguments("oparch-snapshot-create takes exactly one of --justification and --automatic");
    }
    Arguments {
        scope: scope, work_context: positional.at(1) ?? "", automatic: automatic,
        justification: justification, error: "",
    }
}

test "a manual snapshot is given its justification, whatever it holds" {
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-create", "main",
                                     "system", "--justification", "--before a kernel upgrade"]);

    assert.equal(arguments.error, "");
    assert.equal(arguments.scope, "system");
    assert.is_true(!arguments.automatic);
    assert.equal(arguments.justification, "--before a kernel upgrade")
}

test "an automatic snapshot of a home is given its work context, by name or by UID" {
    let named = parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "home", "work", "--automatic"]);
    let numbered = parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "home", "1001", "--automatic"]);

    assert.equal(named.error, "");
    assert.equal(named.scope, "home");
    assert.is_true(named.automatic);
    assert.equal(named.work_context, "work");
    assert.equal(numbered.work_context, "1001")
}

test "neither or both of --justification and --automatic are refused" {
    let expected = "oparch-snapshot-create takes exactly one of --justification and --automatic";

    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "system"]).error, expected);
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "system",
                                  "--automatic", "--justification", "before a kernel upgrade"]).error,
                 expected)
}

test "a work context with the system scope, and none with the home scope, are refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "system", "work", "--automatic"]).error,
                 "the system scope takes no work context");
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "home", "--automatic"]).error,
                 "the home scope takes the work context whose home is snapshotted, by name or by UID")
}

test "no scope, too many arguments, a scope that is not one, an unknown option and a justification with no text are refused" {
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "--automatic"]).error,
                 "oparch-snapshot-create takes a scope, system or home, and for home the work context");
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "home", "work", "x", "--automatic"]).error,
                 "oparch-snapshot-create takes a scope, system or home, and for home the work context");
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "dotfiles", "--automatic"]).error,
                 "unknown scope 'dotfiles': the scope is system or home");
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "system", "--manual"]).error,
                 "unknown option '--manual'");
    assert.equal(parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "system", "--justification"]).error,
                 "option '--justification' requires a value")
}

/// Takes the snapshot the arguments ask for, through the snapshot library. The
/// work context of a home is resolved first, from its name or its UID.
function take_snapshot(shell: root.common.Shell, files: root.common.Files, lock: root.snapshot.SnapshotLock,
                       arguments: Arguments) -> root.snapshot.Taken {
    if (arguments.scope == "system") {
        if (arguments.automatic) {
            return root.snapshot.take_automatic_system_snapshot(shell, files, lock);
        }
        return root.snapshot.take_system_snapshot(shell, files, lock, root.snapshot.manual_kind(),
                                                  arguments.justification);
    }
    let resolved = root.snapshot.resolve_work_context(shell, arguments.work_context);
    if (resolved.error != "") {
        return root.snapshot.Taken { path: "", error: resolved.error };
    }
    if (arguments.automatic) {
        return root.snapshot.take_automatic_home_snapshot(shell, files, lock, resolved.work_context);
    }
    root.snapshot.take_home_snapshot(shell, files, lock, resolved.work_context, root.snapshot.manual_kind(),
                                     arguments.justification)
}

test "a manual snapshot of a home given by UID is taken of that account's home" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: {
            "getent passwd 1001": "work:x:1001:1001::/home/work:/bin/bash\n",
            "date +%s": "1778765100\n",
        },
    };
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-create", "main",
                                     "home", "1001", "--justification", "before a bulk move"]);

    let taken = take_snapshot(shell, files, root.snapshot.recording_lock(shell), arguments);

    assert.equal(taken.error, "");
    assert.equal(taken.path, "/snapshots/home/work/manual/@1778765100");
    assert.equal(shell.commands, [
        "getent passwd 1001",
        "lock /snapshots/lock",
        "date +%s",
        "btrfs subvolume snapshot -r /home/work /snapshots/home/work/manual/@1778765100",
        "unlock /snapshots/lock",
    ]);
    assert.equal(root.snapshot.read_labels(files).entries.get("home/work/manual/@1778765100"), "before a bulk move")
}

test "an automatic snapshot of a home given by UID is kept to sixty in that account's scope" {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/home/work/automatic");
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: {
            "getent passwd 1001": "work:x:1001:1001::/home/work:/bin/bash\n",
            "date +%s": "1778761500\n",
        },
    };
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "home", "1001", "--automatic"]);

    let taken = take_snapshot(shell, files, root.snapshot.recording_lock(shell), arguments);

    assert.equal(taken.error, "");
    assert.equal(taken.path, "/snapshots/home/work/automatic/@1778761500");
    assert.equal(shell.commands, [
        "getent passwd 1001",
        "date +%s",
        "btrfs subvolume snapshot -r /home/work /snapshots/home/work/automatic/@1778761500",
    ])
}

test "a UID no account has takes no snapshot" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: {}, exit_codes: { "getent passwd 4242": 2 },
    };
    let arguments = parse_arguments(["/usr/bin/oparch-snapshot-create", "main", "home", "4242", "--automatic"]);

    let taken = take_snapshot(shell, files, root.snapshot.recording_lock(shell), arguments);

    assert.equal(taken.error, "no account has the user id 4242");
    assert.equal(shell.commands, ["getent passwd 4242"])
}

function main() -> void {
    let shell = root.common.system_shell();
    let files = root.common.system_files();
    //# before anything else, the arguments included: the tool snapshots and
    //# deletes subvolumes and writes under /snapshots, which only root may do
    let refused = root.common.require_root(shell, "oparch-snapshot-create");
    if (refused != "") {
        baml.io.eprintln(`error: ${refused}`);
        baml.sys.exit(1);
    }
    let arguments = parse_arguments(baml.sys.argv());
    if (arguments.error != "") {
        baml.io.eprintln(`error: ${arguments.error}`);
        baml.sys.exit(2);
    }
    let taken = take_snapshot(shell, files, root.snapshot.snapshots_lock(), arguments);
    if (taken.error != "") {
        baml.io.eprintln(`error: ${taken.error}`);
        baml.sys.exit(1);
    }
    baml.io.println(taken.path);
}
