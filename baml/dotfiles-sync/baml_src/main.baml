// `oparch-dotfiles-sync`: builds and validates the complete current-machine
// plan, then applies managed filesystem targets and installs declared packages.
//
// There is no interactive synchronization mode: behavior is declared by the map.

function default_source_root() -> string {
    "/dotfiles"
}

function default_map_path() -> string {
    "/dotfiles/main.dfmap"
}

class Options {
    source: string,
    map_path: string,
    dry_run: bool,
}

/// Reads `--source`, `--map` and `--dry-run`. Everything before the first
/// option is the invocation itself.
function parse_options(argv: string[], diag: Diagnostics) -> Options {
    let args: string[] = [];
    let started = false;
    for (let argument in argv) {
        if (started || argument.starts_with("--")) {
            started = true;
            let _ = args.push(argument);
        }
    }

    let options = Options { source: default_source_root(), map_path: default_map_path(), dry_run: false };
    let index = 0;
    while (index < args.length()) {
        let argument = args.at(index) ?? "";
        if (argument == "--dry-run") {
            options.dry_run = true;
            index = index + 1;
        } else if (argument == "--source" || argument == "--map") {
            if let value: string = args.at(index + 1) {
                if (argument == "--source") {
                    options.source = value;
                } else {
                    options.map_path = value;
                }
            } else {
                diag.report(`option '${argument}' requires a path`);
            }
            index = index + 2;
        } else {
            diag.report(`unknown option '${argument}'`);
            index = index + 1;
        }
    }
    options
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

function main() -> null {
    let diag = new_diagnostics();
    let options = parse_options(baml.sys.argv(), diag);
    let source_root = path_normalize(options.source);
    let map_path = path_normalize(options.map_path);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(2);
    }
    //# 1-3: parse the map, validate its version, expand the include graph
    let document = load_map_document(map_path, source_root, diag);
    if (document == null) {
        print_errors(diag);
        baml.sys.exit(1);
    }
    //# 4: resolve the current hostname and the members of the dotfiles group
    let machine = detect_machine(diag);
    //# 5-11: selectors, placeholders, paths, values, secrets, conflicts, packages
    let plan = build_plan(document, machine, source_root, default_secrets_root(), diag);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(1);
    }

    if (options.dry_run) {
        print_plan(plan, document, machine, options);
        return null;
    }

    let catalog = Catalog {
        values: document.values,
        secrets: document.secrets,
        secrets_root: default_secrets_root(),
    };
    let state_root = default_state_root();
    //# renders are staged and validated before any managed target changes
    let staged = stage_renders(plan, catalog, machine, state_root, diag);
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(1);
    }
    //# application order: remove stale targets, apply targets, install packages
    let removed = remove_stale_targets(plan, state_root, diag);
    let applied = apply_targets(plan, staged, diag);
    let installed = install_packages(plan, diag);
    write_sync_state(
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
    if (diag.has_errors()) {
        print_errors(diag);
        baml.sys.exit(1);
    }
    null
}
