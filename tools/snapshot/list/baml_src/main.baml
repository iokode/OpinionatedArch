// `oparch-snapshot-list`: lists the snapshots of the machine, one path per line,
// narrowed by what it is given. The command is documented in
// `docs/tools/snapshot/list/000-command.md`; what it runs is the snapshot
// library, and this is its command line.

/// What the options asked for, or what is wrong with them.
class Options {
    filter: root.snapshot.SnapshotFilter,
    error: string,
}

/// Reads the options. The packed executable is handed its own path and the name
/// of its entry point before what it was called with, so what it was called
/// with starts at the third. Every option is optional, which is why they are
/// read here rather than declared as parameters of the entry point.
function parse_options(argv: string[]) -> Options {
    let args = argv.slice(2, argv.length());
    let options = Options {
        filter: root.snapshot.SnapshotFilter { scope: "", work_context: "", since: null, until: null },
        error: "",
    };
    let work_context_given = false;
    let index = 0;
    while (index < args.length()) {
        let argument = args.at(index) ?? "";
        if (argument != "--scope" && argument != "--work-context" && argument != "--since" && argument != "--until") {
            options.error = `unknown option '${argument}'`;
            return options;
        }
        let given = args.at(index + 1);
        if (given == null) {
            options.error = `option '${argument}' requires a value`;
            return options;
        }
        let value = given ?? "";
        if (argument == "--scope") {
            if (value != "system" && value != "home") {
                options.error = `--scope takes system or home, not '${value}'`;
                return options;
            }
            options.filter.scope = value;
        } else if (argument == "--work-context") {
            options.filter.work_context = value;
            work_context_given = true;
        } else {
            let read = root.snapshot.read_utc_date_time(value);
            if (read.error != "") {
                options.error = `${argument}: ${read.error}`;
                return options;
            }
            if (argument == "--since") {
                options.filter.since = read.seconds;
            } else {
                options.filter.until = read.seconds;
            }
        }
        index = index + 2;
    }
    if (work_context_given && options.filter.scope != "home") {
        options.error = "--work-context is taken only with --scope home";
    }
    options
}

test "no option lists everything" {
    let options = parse_options(["/usr/bin/oparch-snapshot-list", "main"]);

    assert.equal(options.error, "");
    assert.equal(options.filter.scope, "");
    assert.equal(options.filter.work_context, "");
    assert.is_true(options.filter.since == null);
    assert.is_true(options.filter.until == null)
}

test "every option narrows what it names" {
    let options = parse_options(["/usr/bin/oparch-snapshot-list", "main", "--scope", "home",
                                 "--work-context", "work", "--since", "2026-09-14T10:00:00",
                                 "--until", "2000-02-29T23:59:59"]);

    assert.equal(options.error, "");
    assert.equal(options.filter.scope, "home");
    assert.equal(options.filter.work_context, "work");
    assert.equal(options.filter.since, 1789380000);
    assert.equal(options.filter.until, 951868799)
}

test "a work context without the home scope is refused" {
    let expected = "--work-context is taken only with --scope home";

    assert.equal(parse_options(["/usr/bin/oparch-snapshot-list", "main", "--work-context", "work"]).error, expected);
    assert.equal(parse_options(["/usr/bin/oparch-snapshot-list", "main", "--scope", "system",
                                "--work-context", "work"]).error,
                 expected)
}

test "a date carrying a zone is refused in the name of its option" {
    assert.equal(parse_options(["/usr/bin/oparch-snapshot-list", "main", "--since", "2026-09-14T10:00:00Z"]).error,
                 "--since: '2026-09-14T10:00:00Z' is not a date and time in UTC written YYYY-MM-DDTHH:MM:SS, with no zone")
}

test "a scope that is not one, an option with no value and an unknown option are refused" {
    assert.equal(parse_options(["/usr/bin/oparch-snapshot-list", "main", "--scope", "dotfiles"]).error,
                 "--scope takes system or home, not 'dotfiles'");
    assert.equal(parse_options(["/usr/bin/oparch-snapshot-list", "main", "--until"]).error,
                 "option '--until' requires a value");
    assert.equal(parse_options(["/usr/bin/oparch-snapshot-list", "main", "--manual"]).error,
                 "unknown option '--manual'")
}

/// What is printed for a snapshot: the work context whose home it is, or
/// `system`, a tab, and its path.
function listing_line(snapshot: root.snapshot.ListedSnapshot) -> string {
    let scope = if (snapshot.work_context == "") { "system" } else { snapshot.work_context };
    scope + "\t" + snapshot.path
}

test "a line names the work context, or the system, and then the path" {
    assert.equal(listing_line(root.snapshot.ListedSnapshot { work_context: "", path: "/snapshots/system/manual/@1778764800" }),
                 "system\t/snapshots/system/manual/@1778764800");
    assert.equal(listing_line(root.snapshot.ListedSnapshot { work_context: "work", path: "/snapshots/home/work/automatic/@1778761500" }),
                 "work\t/snapshots/home/work/automatic/@1778761500")
}

function main() -> void {
    let options = parse_options(baml.sys.argv());
    if (options.error != "") {
        baml.io.eprintln(`error: ${options.error}`);
        baml.sys.exit(2);
    }
    let listing = root.snapshot.list_snapshots(root.common.system_files(), options.filter);
    if (listing.error != "") {
        baml.io.eprintln(`error: ${listing.error}`);
        baml.sys.exit(1);
    }
    for (let snapshot in listing.snapshots) {
        baml.io.println(listing_line(snapshot));
    }
}
