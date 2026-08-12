// Plan construction. The complete current-machine plan is built and validated
// before any managed filesystem target is changed.

/// One managed filesystem target, fully expanded: no placeholders, no
/// selectors and no directory sources are left to resolve.
class PlannedTarget {
    action: "link" | "copy" | "render",
    sources: string[],
    target: string,
    mode: string?,
    owner: string,
    group: string,
    username: string?,
    home: string?,
    template: string?,
    value_refs: string[],
    secret_refs: string[],
    loc: SourceLoc,
}

class Plan {
    targets: PlannedTarget[],
    packages: string[],
    aur_packages: string[],
}

/// The default mode of every copy and every rendered file.
function default_output_mode() -> string {
    "0440"
}

function is_upper_ascii(c: string) -> bool {
    c >= "A" && c <= "Z"
}

/// The first `&NAME` placeholder left in `text`, if any.
function unknown_placeholder(text: string) -> string? {
    let chars = text.chars();
    let count = chars.length();
    let found: string? = null;
    let i = 0;
    while (i < count && found == null) {
        if ((chars.at(i) ?? "") == "&") {
            let name = "";
            let j = i + 1;
            while (j < count && is_upper_ascii(chars.at(j) ?? "")) {
                name = name + (chars.at(j) ?? "");
                j = j + 1;
            }
            if (name != "") {
                found = "&" + name;
            }
            i = j;
        } else {
            i = i + 1;
        }
    }
    found
}

/// Expands `&USER`, `&HOME` and `&HOST` in a target path.
function expand_target_path(
    text: string,
    user: DotfilesUser?,
    hostname: string,
    loc: SourceLoc,
    diag: Diagnostics,
) -> string? {
    let expanded = if let member: DotfilesUser = user {
        text.replace_all("&USER", member.name).replace_all("&HOME", member.home)
    } else {
        text
    };
    let resolved = expanded.replace_all("&HOST", hostname);
    if let leftover: string = unknown_placeholder(resolved) {
        diag.at(loc, `unknown placeholder '${leftover}' in target '${text}'`);
        null
    } else {
        resolved
    }
}

/// Expands `&USER` and `&HOST` in a source path. `&HOME` is a target-only
/// placeholder.
function expand_source_path(
    text: string,
    user: DotfilesUser?,
    hostname: string,
    loc: SourceLoc,
    diag: Diagnostics,
) -> string? {
    if (text.includes("&HOME")) {
        diag.at(loc, `placeholder '&HOME' is invalid in source path '${text}'`);
        return null;
    }
    let expanded = if let member: DotfilesUser = user {
        text.replace_all("&USER", member.name)
    } else {
        text
    };
    let resolved = expanded.replace_all("&HOST", hostname);
    if let leftover: string = unknown_placeholder(resolved) {
        diag.at(loc, `unknown placeholder '${leftover}' in source '${text}'`);
        null
    } else {
        resolved
    }
}

/// A target holding `&HOME` or `&USER` is expanded once per member of the
/// `dotfiles` group; any other target is global and applies once.
function is_user_target(target: string) -> bool {
    target.includes("&HOME") || target.includes("&USER")
}

/// What the filesystem holds at `path`: `file`, `directory`, `symlink`,
/// `special` or `missing`. Determined from the parent listing, so a symlink is
/// never followed.
function classify_path(files: root.common.Files, path: string) -> string {
    let normalized = path_normalize(path);
    let parent = path_dirname(normalized);
    let name = path_basename(normalized);
    let entries = files.read_dir(parent);
    if (entries != null) {
        if let entry: root.common.DirEntry = entries
            .find(
                (candidate) -> {
                    candidate.name == name
                },
            ) {
            if (entry.is_symlink) {
                "symlink"
            } else if (entry.is_dir) {
                "directory"
            } else if (entry.is_file) {
                "file"
            } else {
                "special"
            }
        } else {
            "missing"
        }
    } else {
        "missing"
    }
}

/// The normal files under `root`/`prefix`, as paths relative to `root`.
function collect_relative_files(
    files: root.common.Files,
    root: string,
    prefix: string,
    loc: SourceLoc,
    diag: Diagnostics,
) -> string[] {
    let out: string[] = [];
    let directory = if (prefix == "") {
        root
    } else {
        path_join(root, prefix)
    };
    let entries = files.read_dir(directory);
    if (entries != null) {
        for (let entry in entries) {
            let relative = if (prefix == "") {
                entry.name
            } else {
                prefix + "/" + entry.name
            };
            if (entry.is_symlink) {
                diag.at(loc, `source '${relative}' is a symlink, which is invalid`);
            } else if (entry.is_dir) {
                for (let nested in collect_relative_files(files, root, relative, loc, diag)) {
                    let _ = out.push(nested);
                }
            } else if (entry.is_file) {
                let _ = out.push(relative);
            } else {
                diag.at(loc, `source '${relative}' is a special file, which is invalid`);
            }
        }
    } else {
        diag.at(loc, `cannot read source directory '${directory}'`);
    }
    out
}

/// Validates one source path and returns its absolute location.
function resolve_source_path(
    files: root.common.Files,
    text: string,
    source_root: string,
    loc: SourceLoc,
    diag: Diagnostics,
) -> string? {
    if (path_is_absolute(text)) {
        diag.at(loc, `absolute source path '${text}' is invalid`);
        return null;
    }
    let resolved = path_normalize(path_join(source_root, text));
    if (!path_within(source_root, resolved)) {
        diag.at(loc, `source path '${text}' escapes the source directory '${source_root}'`);
        return null;
    }
    let kind = classify_path(files, resolved);
    if (kind == "missing") {
        diag.at(loc, `source '${text}' does not exist under '${source_root}'`);
        null
    } else if (kind == "symlink") {
        diag.at(loc, `source '${text}' is a symlink, which is invalid`);
        null
    } else if (kind == "special") {
        diag.at(loc, `source '${text}' is a special file, which is invalid`);
        null
    } else {
        resolved
    }
}

function action_of(kind: OperationKind) -> "link" | "copy" | "render" {
    match (kind) {
        OperationKind.Link => "link",
        OperationKind.Copy => "copy",
        OperationKind.Render => "render",
    }
}

/// Resolves every value and secret a composed template references, recording
/// the reference names on the planned target. Secret values are never read
/// here; only the existence of the store file is checked.
function bind_template_references(
    files: root.common.Files,
    planned: PlannedTarget,
    template: string,
    catalog: Catalog,
    context: SelectorContext,
    diag: Diagnostics,
) -> null {
    for (let name in template_builtin_references(template)) {
        if (context.username == null && (name == "USER" || name == "HOME")) {
            diag.at(planned.loc, `built-in reference '{{${name}}}' has no value on a global target`);
        }
    }
    for (let name in template_references(template)) {
        match (catalog.classify_reference(name)) {
            let unresolved: Unresolved => {
                diag.at(planned.loc, unresolved.message);
            },
            let kind: Resolved => {
                if (kind.text == "value") {
                    match (catalog.resolve_value(name, context)) {
                        let failure: Unresolved => {
                            diag.at(planned.loc, failure.message);
                        },
                        let _resolved: Resolved => {
                            let _ = planned.value_refs.push(name);
                        },
                    }
                } else {
                    match (catalog.locate_secret(name, context)) {
                        let failure: Unresolved => {
                            diag.at(planned.loc, failure.message);
                        },
                        let location: SecretLocation => {
                            if (!files.exists(location.path)) {
                                diag.at(
                                    planned.loc,
                                    `secret '${name}' is required but its store file is missing`,
                                );
                            }
                            let _ = planned.secret_refs.push(name);
                        },
                    }
                }
            },
        }
    }
    null
}

/// Expands one rule into planned targets for one evaluation context.
function expand_operation(
    files: root.common.Files,
    operation: Operation,
    context: SelectorContext,
    user: DotfilesUser?,
    source_root: string,
    catalog: Catalog,
    plan: Plan,
    diag: Diagnostics,
) -> null {
    let loc = operation.loc;
    let target_text = expand_target_path(operation.target, user, context.hostname, loc, diag);
    if (target_text == null) {
        return null;
    }
    if (!path_is_absolute(target_text)) {
        diag.at(loc, `target '${operation.target}' does not resolve to an absolute path`);
        return null;
    }
    let target_base = path_normalize(target_text);

    let sources: string[] = [];
    for (let raw in operation.sources) {
        if let expanded: string = expand_source_path(raw, user, context.hostname, loc, diag) {
            if let resolved: string = resolve_source_path(files, expanded, source_root, loc, diag) {
                let _ = sources.push(resolved);
            }
        }
    }
    if (sources.length() != operation.sources.length()) {
        return null;
    }

    let owner = if (operation.root_ownership) {
        "root"
    } else {
        user?.name ?? "root"
    };
    let group = if (operation.root_ownership) {
        "root"
    } else {
        user?.group ?? "root"
    };
    let mode = if (operation.kind == OperationKind.Link) {
        null
    } else {
        operation.mode ?? default_output_mode()
    };
    let action = action_of(operation.kind);

    if (operation.kind == OperationKind.Render) {
        //# render: one or more regular files, concatenated in listed order
        let composed = "";
        let readable = true;
        for (let source in sources) {
            if (classify_path(files, source) != "file") {
                diag.at(loc, `render source '${source}' is a directory, which is invalid`);
                readable = false;
            } else if let text: string = files.read(source) {
                composed = composed + text;
            } else {
                diag.at(loc, `cannot read render source '${source}'`);
                readable = false;
            }
        }
        if (!readable) {
            return null;
        }
        let planned = PlannedTarget {
            action: action,
            sources: sources,
            target: target_base,
            mode: mode,
            owner: owner,
            group: group,
            username: context.username,
            home: user?.home,
            template: composed,
            value_refs: [],
            secret_refs: [],
            loc: loc,
        };
        bind_template_references(files, planned, composed, catalog, context, diag);
        let _ = plan.targets.push(planned);
    } else if (classify_path(files, sources.at(0) ?? "") == "directory") {
        //# a directory source maps every normal file under it, preserving
        //# relative paths, and never maps the directory itself
        let root = sources.at(0) ?? "";
        let relatives = collect_relative_files(files, root, "", loc, diag)
            .sort_by_key(
                (entry) -> {
                    entry
                },
            );
        for (let relative in relatives) {
            let _ = plan
                .targets
                .push(
                    PlannedTarget {
                        action: action,
                        sources: [path_join(root, relative)],
                        target: path_normalize(path_join(target_base, relative)),
                        mode: mode,
                        owner: owner,
                        group: group,
                        username: context.username,
                        home: user?.home,
                        template: null,
                        value_refs: [],
                        secret_refs: [],
                        loc: loc,
                    },
                );
        }
    } else {
        let _ = plan
            .targets
            .push(
                PlannedTarget {
                    action: action,
                    sources: sources,
                    target: target_base,
                    mode: mode,
                    owner: owner,
                    group: group,
                    username: context.username,
                    home: user?.home,
                    template: null,
                    value_refs: [],
                    secret_refs: [],
                    loc: loc,
                },
            );
    }
    null
}

/// Two active operations that expand to the same target are invalid, and so is
/// a target that would have to be both a file and a directory.
function check_target_conflicts(plan: Plan, diag: Diagnostics) -> null {
    let seen: map<string, string> = {};
    for (let planned in plan.targets) {
        if let previous: string = seen.get(planned.target) {
            diag.at(
                planned.loc,
                `target '${planned.target}' is already produced by the active operation at ${previous}`,
            );
        } else {
            let _ = seen.set(planned.target, planned.loc.label());
        }
    }
    for (let planned in plan.targets) {
        for (let ancestor in path_ancestors(path_dirname(planned.target))) {
            if (seen.has(ancestor)) {
                diag.at(
                    planned.loc,
                    `target '${planned.target}' requires '${ancestor}' to be a directory, but it is a managed file target`,
                );
            }
        }
    }
    null
}

function collect_packages(
    document: MapDocument,
    machine: Machine,
    plan: Plan,
    diag: Diagnostics,
) -> null {
    let context = global_context(machine.hostname);
    for (let declaration in document.packages) {
        if (user_selectors(declaration.selectors).length() > 0) {
            diag.at(
                declaration.loc,
                `user selectors are invalid for package entry '${declaration.name}' because packages are system-wide`,
            );
        } else if (selectors_pass(declaration.selectors, context)) {
            let bucket = if (declaration.aur) {
                plan.aur_packages
            } else {
                plan.packages
            };
            if (!bucket.includes(declaration.name)) {
                let _ = bucket.push(declaration.name);
            }
        }
    }
    null
}

/// Builds and validates the complete current-machine plan.
function build_plan(
    files: root.common.Files,
    document: MapDocument,
    machine: Machine,
    source_root: string,
    secrets_root: string,
    diag: Diagnostics,
) -> Plan {
    let plan = Plan { targets: [], packages: [], aur_packages: [] };
    let catalog = Catalog { values: document.values, secrets: document.secrets, secrets_root: secrets_root };

    collect_packages(document, machine, plan, diag);

    for (let operation in document.operations) {
        if (is_user_target(operation.target)) {
            //# a user target is expanded once per member of the dotfiles group
            for (let member in machine.users) {
                let context = user_context(machine.hostname, member.name);
                if (selectors_pass(operation.selectors, context)) {
                    expand_operation(files, operation, context, member, source_root, catalog, plan, diag);
                }
            }
        } else {
            let bound = user_selectors(operation.selectors);
            if (bound.length() > 0) {
                diag.at(
                    operation.loc,
                    `user selectors are invalid on global target '${operation.target}'`,
                );
            } else {
                let context = global_context(machine.hostname);
                if (selectors_pass(operation.selectors, context)) {
                    expand_operation(files, operation, context, null, source_root, catalog, plan, diag);
                }
            }
        }
    }

    check_target_conflicts(plan, diag);
    plan
}
