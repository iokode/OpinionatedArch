// Application of a validated plan, and the synchronization state that records
// what the tool owns.

/// Where synchronization state and staged renders live.
function default_state_root() -> string {
    "/var/lib/oparch/dotfiles-sync"
}

function state_file_path(state_root: string) -> string {
    `${state_root}/state.json`
}

function staging_root(state_root: string) -> string {
    `${state_root}/staging`
}

/// The managed targets created by the previous synchronization.
class SyncState {
    version: int,
    targets: string[],
}

/// A render that has been composed and substituted, waiting to be written.
class StagedRender {
    target: string,
    staged_path: string,
}

function read_sync_state(state_root: string) -> SyncState {
    if let text: string = read_text_file(state_file_path(state_root)) {
        baml.json.from_string<SyncState>(text) catch_all (e) {
            _ => SyncState { version: 1, targets: [] }
        }
    } else {
        SyncState { version: 1, targets: [] }
    }
}

function write_sync_state(state_root: string, targets: string[], diag: Diagnostics) -> null {
    let state = SyncState { version: 1, targets: targets };
    let result = run_command("install", ["-d", "-m", "0700", "-o", "root", "-g", "root", state_root]);
    if (!result.ok()) {
        diag.report(`cannot create the state directory '${state_root}': ${result.stderr.trim()}`);
        return null;
    }
    let written = baml.fs.write(state_file_path(state_root), baml.json.to_string(state)) catch_all (e) {
        _ => -1
    };
    if (written < 0) {
        diag.report(`cannot write synchronization state to '${state_file_path(state_root)}'`);
    }
    null
}

/// Creates every missing parent directory of `target`, owned by the target's
/// user, or by `root:root` for a global target.
function ensure_parent_directories(
    target: string,
    owner: string,
    group: string,
    diag: Diagnostics,
) -> bool {
    let ok = true;
    for (let directory in path_ancestors(path_dirname(target))) {
        if (!file_exists(directory)) {
            let created = run_command("install", ["-d", "-o", owner, "-g", group, directory]);
            if (!created.ok()) {
                diag.report(`cannot create directory '${directory}': ${created.stderr.trim()}`);
                ok = false;
            }
        }
    }
    ok
}

function remove_target(target: string, diag: Diagnostics) -> bool {
    let removed = run_command("rm", ["-f", target]);
    if (!removed.ok()) {
        diag.report(`cannot remove '${target}': ${removed.stderr.trim()}`);
    }
    removed.ok()
}

function apply_link(planned: PlannedTarget, diag: Diagnostics) -> bool {
    let source = planned.sources.at(0) ?? "";
    if (!ensure_parent_directories(planned.target, planned.owner, planned.group, diag)) {
        return false;
    }
    if (!remove_target(planned.target, diag)) {
        return false;
    }
    let linked = run_command("ln", ["-s", source, planned.target]);
    if (!linked.ok()) {
        diag.report(`cannot link '${planned.target}' to '${source}': ${linked.stderr.trim()}`);
        return false;
    }
    //# -h so the link itself is owned, not the file it points at
    let owned = run_command("chown", ["-h", `${planned.owner}:${planned.group}`, planned.target]);
    if (!owned.ok()) {
        diag.report(`cannot set ownership of '${planned.target}': ${owned.stderr.trim()}`);
        return false;
    }
    true
}

function apply_copy(planned: PlannedTarget, diag: Diagnostics) -> bool {
    let source = planned.sources.at(0) ?? "";
    if (!ensure_parent_directories(planned.target, planned.owner, planned.group, diag)) {
        return false;
    }
    let installed = run_command(
        "install",
        [
            "-m",
            planned.mode ?? default_output_mode(),
            "-o",
            planned.owner,
            "-g",
            planned.group,
            source,
            planned.target,
        ],
    );
    if (!installed.ok()) {
        diag.report(`cannot copy '${source}' to '${planned.target}': ${installed.stderr.trim()}`);
        return false;
    }
    true
}

/// Writes a staged render to its target. The content never passes through a
/// command argument.
function apply_render(planned: PlannedTarget, staged_path: string, diag: Diagnostics) -> bool {
    if (!ensure_parent_directories(planned.target, planned.owner, planned.group, diag)) {
        return false;
    }
    let installed = run_command(
        "install",
        [
            "-m",
            planned.mode ?? default_output_mode(),
            "-o",
            planned.owner,
            "-g",
            planned.group,
            staged_path,
            planned.target,
        ],
    );
    if (!installed.ok()) {
        diag.report(`cannot write rendered target '${planned.target}': ${installed.stderr.trim()}`);
        return false;
    }
    true
}

/// Substitutes a planned render. This is the only place a secret value is read.
function render_target_content(
    planned: PlannedTarget,
    catalog: Catalog,
    hostname: string,
    diag: Diagnostics,
) -> string? {
    let template = planned.template ?? "";
    let context = SelectorContext { hostname: hostname, username: planned.username };
    let substitutions: map<string, string> = {};
    let _host = substitutions.set("HOST", hostname);
    if let username: string = planned.username {
        let _user = substitutions.set("USER", username);
    }
    if let home: string = planned.home {
        let _home = substitutions.set("HOME", home);
    }

    let ok = true;
    for (let name in planned.value_refs) {
        match (catalog.resolve_value(name, context)) {
            let resolved: Resolved => {
                let _ = substitutions.set(name, resolved.text);
            },
            let failure: Unresolved => {
                diag.at(planned.loc, failure.message);
                ok = false;
            },
        }
    }
    for (let name in planned.secret_refs) {
        match (catalog.locate_secret(name, context)) {
            let location: SecretLocation => {
                //# the value goes straight into the substitution map: it is never
                //# logged and never passed as a command argument
                match (read_secret_value(location.path)) {
                    let value: Resolved => {
                        let _ = substitutions.set(name, value.text);
                    },
                    let failure: Unresolved => {
                        diag.at(
                            planned.loc,
                            `secret '${name}' cannot be read from the secret store`,
                        );
                        ok = false;
                    },
                }
            },
            let failure: Unresolved => {
                diag.at(planned.loc, failure.message);
                ok = false;
            },
        }
    }
    if (!ok) {
        return null;
    }
    match (render_segments(scan_template(template), substitutions)) {
        let rendered: Resolved => rendered.text,
        let failure: Unresolved => {
            diag.at(planned.loc, failure.message);
            null
        },
    }
}

/// Composes and substitutes every render into the state directory before any
/// managed target is changed.
function stage_renders(
    plan: Plan,
    catalog: Catalog,
    machine: Machine,
    state_root: string,
    diag: Diagnostics,
) -> StagedRender[] {
    let staged: StagedRender[] = [];
    let renders = plan
        .targets
        .filter(
            (planned) -> {
                planned.action == "render"
            },
        );
    if (renders.length() == 0) {
        return staged;
    }
    let directory = staging_root(state_root);
    let created = run_command("install", ["-d", "-m", "0700", "-o", "root", "-g", "root", directory]);
    if (!created.ok()) {
        diag.report(`cannot create the staging directory '${directory}': ${created.stderr.trim()}`);
        return staged;
    }

    let index = 0;
    for (let planned in renders) {
        let staged_path = `${directory}/render-${index}`;
        if let content: string = render_target_content(planned, catalog, machine.hostname, diag) {
            //# create the staged file restricted before its content exists
            let _ = run_command("install", ["-m", "0600", "-o", "root", "-g", "root", "/dev/null", staged_path]);
            let written = baml.fs.write(staged_path, content) catch_all (e) {
                _ => -1
            };
            if (written < 0) {
                diag.report(`cannot stage rendered output for '${planned.target}'`);
            } else {
                let _ = staged.push(StagedRender { target: planned.target, staged_path: staged_path });
            }
        }
        index = index + 1;
    }
    staged
}

/// Removes managed targets recorded by the previous synchronization that the
/// current plan no longer declares.
function remove_stale_targets(plan: Plan, state_root: string, diag: Diagnostics) -> int {
    let current = plan
        .targets
        .map(
            (planned) -> {
                planned.target
            },
        );
    let previous = read_sync_state(state_root);
    let removed = 0;
    for (let target in previous.targets) {
        if (!current.includes(target)) {
            if (remove_target(target, diag)) {
                removed = removed + 1;
            }
        }
    }
    removed
}

/// Applies copies, renders and links. Filesystem targets are applied before
/// packages are installed, so a map-managed pacman configuration is in place
/// before pacman resolves anything.
function apply_targets(plan: Plan, staged: StagedRender[], diag: Diagnostics) -> int {
    let applied = 0;
    for (let planned in plan.targets) {
        let done = match (planned.action) {
            "link" => apply_link(planned, diag),
            "copy" => apply_copy(planned, diag),
            "render" => {
                let entry = staged
                    .find(
                        (candidate) -> {
                            candidate.target == planned.target
                        },
                    );
                if let render: StagedRender = entry {
                    apply_render(planned, render.staged_path, diag)
                } else {
                    diag.at(planned.loc, `rendered output for '${planned.target}' was not staged`);
                    false
                }
            },
        };
        if (done) {
            applied = applied + 1;
        }
    }
    applied
}

function package_installed(name: string) -> bool {
    run_command("pacman", ["-Qq", name]).ok()
}

/// Installs the declared official repository packages that are missing.
/// Package synchronization is additive: nothing is ever uninstalled.
function install_packages(plan: Plan, diag: Diagnostics) -> int {
    let missing = plan
        .packages
        .filter(
            (name) -> {
                !package_installed(name)
            },
        );
    if (missing.length() == 0) {
        return 0;
    }
    let installed = run_command("pacman", ["-S", "--needed", "--noconfirm"].concat(missing));
    if (!installed.ok()) {
        diag.report(`pacman failed to install ${missing.join(" ")}: ${installed.stderr.trim()}`);
        return 0;
    }
    missing.length()
}
