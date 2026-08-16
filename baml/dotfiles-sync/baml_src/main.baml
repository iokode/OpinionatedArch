// `oparch-dotfiles-sync`: builds and validates the complete current-machine
// plan, then applies managed filesystem targets and installs declared packages.
//
// There is no interactive synchronization mode: behavior is declared by the map.

function default_source_root() -> string {
    "/dotfiles"
}

/// What the map is called inside a source. The default map is this file at the
/// top of whatever `--source` is, so pointing the tool at a package somewhere
/// else needs one option rather than two that have to agree.
function map_file_name() -> string {
    "main.dfmap"
}

function default_map_path() -> string {
    path_join(default_source_root(), map_file_name())
}

class Options {
    source: string,
    map_path: string,
    secrets_root: string,
    /// The machine to plan for, when it is not the one this is running on.
    /// Absent and empty mean "read it from here"; see `detect_machine`.
    hostname: string?,
    users: string[],
    dry_run: bool,
    list_secrets: bool,
}

/// Reads the options. Everything before the first one is the invocation itself.
function parse_options(argv: string[], diag: Diagnostics) -> Options {
    let args: string[] = [];
    let started = false;
    for (let argument in argv) {
        if (started || argument.starts_with("--")) {
            started = true;
            let _ = args.push(argument);
        }
    }

    let options = Options {
        source: default_source_root(),
        map_path: default_map_path(),
        secrets_root: default_secrets_root(),
        hostname: null,
        users: [],
        dry_run: false,
        list_secrets: false,
    };
    let named_map = false;
    let index = 0;
    while (index < args.length()) {
        let argument = args.at(index) ?? "";
        if (argument == "--dry-run") {
            options.dry_run = true;
            index = index + 1;
        } else if (argument == "--list-secrets") {
            options.list_secrets = true;
            index = index + 1;
        } else if (argument == "--source" || argument == "--map" || argument == "--secrets-root"
                       || argument == "--hostname" || argument == "--user") {
            if let value: string = args.at(index + 1) {
                if (argument == "--source") {
                    options.source = value;
                } else if (argument == "--map") {
                    options.map_path = value;
                    named_map = true;
                } else if (argument == "--secrets-root") {
                    options.secrets_root = value;
                } else if (argument == "--hostname") {
                    options.hostname = value;
                } else {
                    //# repeatable: a machine has as many login users as it has
                    let _ = options.users.push(value);
                }
            } else {
                diag.report(`option '${argument}' requires a value`);
            }
            index = index + 2;
        } else {
            diag.report(`unknown option '${argument}'`);
            index = index + 1;
        }
    }
    //# a source given without a map means the map inside it, not the one beside
    //# the source nobody asked for
    if (!named_map) {
        options.map_path = path_join(options.source, map_file_name());
    }
    options
}

test "the options default to this machine and its own store" {
    let diag = new_diagnostics();
    let options = parse_options(["oparch-dotfiles-sync"], diag);

    assert.equal(options.source, "/dotfiles");
    assert.equal(options.map_path, "/dotfiles/main.dfmap");
    assert.equal(options.secrets_root, "/etc/oparch/dotfiles-sync/secrets");
    assert.is_true(options.hostname == null);
    assert.equal(options.users, []);
    assert.is_true(!options.dry_run);
    assert.is_true(!options.list_secrets);
    assert.is_true(!diag.has_errors())
}

test "a machine is described by name, and its users one at a time" {
    let diag = new_diagnostics();
    let options = parse_options(
        ["oparch-dotfiles-sync", "--source", "/tmp/oparch/dotfiles",
         "--map", "/tmp/oparch/dotfiles/main.dfmap", "--secrets-root", "/tmp/oparch/secrets",
         "--hostname", "oparch", "--user", "ivan", "--user", "work", "--dry-run"],
        diag);

    assert.equal(options.source, "/tmp/oparch/dotfiles");
    assert.equal(options.map_path, "/tmp/oparch/dotfiles/main.dfmap");
    assert.equal(options.secrets_root, "/tmp/oparch/secrets");
    assert.equal(options.hostname, "oparch");
    assert.equal(options.users, ["ivan", "work"]);
    assert.is_true(options.dry_run);
    assert.is_true(!diag.has_errors())
}

test "a source given on its own carries its own map" {
    let diag = new_diagnostics();
    let options = parse_options(["oparch-dotfiles-sync", "--source", "/tmp/oparch/dotfiles"], diag);

    assert.equal(options.map_path, "/tmp/oparch/dotfiles/main.dfmap");
    //# and a map named explicitly is the one used, wherever it is
    let elsewhere = parse_options(
        ["oparch-dotfiles-sync", "--source", "/tmp/oparch/dotfiles", "--map", "/tmp/other.dfmap"],
        diag);
    assert.equal(elsewhere.map_path, "/tmp/other.dfmap")
}

test "an option that takes a value and is given none is reported" {
    let diag = new_diagnostics();
    let _ = parse_options(["oparch-dotfiles-sync", "--hostname"], diag);

    assert.equal(diag.errors, ["option '--hostname' requires a value"])
}

test "an option nobody has heard of is reported rather than ignored" {
    let diag = new_diagnostics();
    let _ = parse_options(["oparch-dotfiles-sync", "--force"], diag);

    assert.equal(diag.errors, ["unknown option '--force'"])
}

function print_errors(diag: Diagnostics) -> null {
    for (let message in diag.errors) {
        baml.io.eprintln(`error: ${message}`);
    }
    null
}

function describe_target(planned: PlannedTarget) -> string {
    let details: string[] = [];
    if let mode: string = planned.mode {
        let _ = details.push(`mode ${mode}`);
    }
    let _ = details.push(`${planned.owner}:${planned.group}`);
    if (planned.value_refs.length() > 0) {
        let _ = details.push(`values ${planned.value_refs.join(",")}`);
    }
    if (planned.secret_refs.length() > 0) {
        //# secret references are identified, their values are never printed
        let _ = details.push(`secrets ${planned.secret_refs.join(",")}`);
    }
    `${planned.action} ${planned.target} <- ${planned.sources.join(" + ")} [${details.join(" ")}]`
}

function print_plan(plan: Plan, document: MapDocument, machine: Machine, options: Options) -> null {
    baml.io
        .println(
            `map ${options.map_path} (format ${document.version.label()}, source ${options.source})`,
        );
    baml.io.println(`files ${document.files.join(" ")}`);
    baml.io.println(`host ${machine.hostname}`);
    baml.io.println(`dotfiles users ${machine.users.map((member) -> { member.name }).join(" ")}`);
    baml.io.println(`targets ${plan.targets.length()}`);
    for (let planned in plan.targets) {
        baml.io.println(`  ${describe_target(planned)}`);
    }
    if (plan.packages.length() > 0) {
        baml.io.println(`packages ${plan.packages.join(" ")}`);
    }
    if (plan.aur_packages.length() > 0) {
        //# the AUR execution policy is a separate decision, so AUR packages are
        //# planned but never applied
        baml.io.println(`aur-packages (not applied) ${plan.aur_packages.join(" ")}`);
    }
    null
}

/// What the plan needs from the store: each file once, relative to the store's
/// root, in a stable order. This is the list an archive of a store has to
/// satisfy, and an empty one is the answer that no store is needed at all.
function required_secret_files(plan: Plan) -> string[] {
    let wanted: string[] = [];
    for (let planned in plan.targets) {
        for (let relative in planned.secret_files) {
            if (!wanted.includes(relative)) {
                wanted.push(relative);
            }
        }
    }
    wanted
        .sort_by_key(
            (entry) -> {
                entry
            },
        )
}

function main() -> void {
    let diag = new_diagnostics();
    //# the ports, built once for the whole run: the port keeps the first file
    //# failure, and it has to survive until it is folded into the diagnostics
    let shell = root.common.system_shell();
    let files = root.common.system_files();
    let options = parse_options(baml.sys.argv(), diag);
    let source_root = path_normalize(options.source);
    let map_path = path_normalize(options.map_path);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(2);
    }
    //# 1-3: parse the map, validate its version, expand the include graph. A
    //# map that did not load is the end of the run, and saying so here is what
    //# leaves a document rather than maybe-a-document to everything below
    let document = load_map_document(files, map_path, source_root, diag) ?? {
        print_errors(diag);
        baml.sys.exit(1)
    };
    //# 4: resolve the hostname and the login users, here or as given
    let machine = detect_machine(shell, files, options.hostname, options.users, diag);
    //# 5-11: selectors, placeholders, paths, values, secrets, conflicts, packages
    let plan = build_plan(files, document, machine, source_root, options.secrets_root,
                          !options.list_secrets, diag);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(1);
    }

    //# what the plan needs from the store, for whoever has to supply one. It
    //# comes before the dry run because it is a different question: not what
    //# this machine would do, but what it is waiting for.
    if (options.list_secrets) {
        for (let relative in required_secret_files(plan)) {
            baml.io.println(relative);
        }
        return;
    }

    if (options.dry_run) {
        print_plan(plan, document, machine, options);
        return;
    }

    let catalog = Catalog {
        values: document.values,
        secrets: document.secrets,
        secrets_root: options.secrets_root,
    };
    let state_root = default_state_root();
    //# renders are staged and validated before any managed target changes
    let staged = stage_renders(shell, files, plan, catalog, machine, state_root, diag);
    absorb_file_failure(files, diag);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(1);
    }
    //# application order: remove stale targets, apply targets, install packages
    let removed = remove_stale_targets(shell, files, plan, state_root, diag);
    let applied = apply_targets(shell, files, plan, staged, diag);
    let installed = install_packages(shell, plan, diag);
    write_sync_state(
        shell,
        files,
        state_root,
        plan.targets
            .map(
                (planned) -> {
                    planned.target
                },
            ),
        diag,
    );

    baml.io
        .println(
            `applied ${applied} targets, removed ${removed} stale targets, installed ${installed} packages`,
        );
    if (plan.aur_packages.length() > 0) {
        baml.io.println(`aur-packages not applied: ${plan.aur_packages.join(" ")}`);
    }
    //# whatever the port recorded while the targets were applied
    absorb_file_failure(files, diag);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(1);
    }
}
