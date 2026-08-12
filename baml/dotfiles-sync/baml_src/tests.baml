// End-to-end tests over the parser, the include graph and the plan builder.
// The fixture map under `tests/fixtures/dotfiles` mirrors the example in
// `docs/tools/oparch-dotfiles-sync/001-map-format.md`.

function fixture_source_root() -> string {
    "tests/fixtures/dotfiles"
}

function fixture_secrets_root() -> string {
    "tests/fixtures/secrets"
}

function fixture_machine() -> Machine {
    Machine {
        hostname: "desktop",
        users: [
            DotfilesUser { name: "personal", home: "/home/personal", group: "personal" },
            DotfilesUser { name: "work", home: "/home/work", group: "work" },
        ],
    }
}

function targets_of(plan: Plan) -> string[] {
    plan.targets
        .map(
            (planned) -> {
                planned.target
            },
        )
}

function parse_fixture_text(text: string, diag: Diagnostics) -> MapFile? {
    parse_map_text(text, "memory.dfmap", diag)
}

test "parse the documented example map" {
    let diag = new_diagnostics();
    let file = parse_fixture_text(
        "oparch dotfiles map\n"
            + "version = '0.1'\n"
            + "\n"
            + "include 'common.dfmap'\n"
            + "include 'hosts/desktop.dfmap' for host 'desktop'\n"
            + "\n"
            + "[packages]\n"
            + "hyprland\n"
            + "uwsm\n"
            + "\n"
            + "[aur-packages]\n"
            + "opencode\n"
            + "\n"
            + "[values.github]\n"
            + "# a comment line\n"
            + "username = 'personal-account' for user 'personal'\n"
            + "username = 'work-account'     for user 'work'\n"
            + "\n"
            + "[secrets.github]\n"
            + "token with scope 'user'\n"
            + "\n"
            + "[dotfiles.hypr]\n"
            + "link 'hypr/keybindings.lua' to '&HOME/.config/hypr/keybindings.lua'\n"
            + "link 'hypr/animations.lua' to '&HOME/.config/hypr/animations.lua' except host 'laptop' # inline comment\n"
            + "\n"
            + "[dotfiles.opencode]\n"
            + "link 'opencode/agent/' to '&HOME/.config/opencode/agent/'\n"
            + "render 'opencode/mcp/common.conf.tpl' + 'opencode/mcp/github.conf.tpl' to '&HOME/.config/opencode/mcp.conf' with mode '0600'\n"
            + "\n"
            + "[dotfiles.boot]\n"
            + "copy 'grub/' to '/boot/'\n",
        diag,
    );
    assert.is_true(!diag.has_errors());
    assert.not_null(file);

    let parsed = file
        ?? MapFile {
            path: "",
            version: MapVersion { major: 0, minor: 0 },
            includes: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    assert.equal(parsed.version, MapVersion { major: 0, minor: 1 });
    assert.equal(parsed.includes.length(), 2);
    assert.equal(parsed.includes.at(1)?.selectors?.length() ?? 0, 1);
    assert.equal(parsed.packages.length(), 3);
    assert
        .equal(
            parsed
                .packages
                .filter(
                    (entry) -> {
                        entry.aur
                    },
                )
                .length(),
            1,
        );
    assert.equal(parsed.values.length(), 2);
    assert.equal(parsed.secrets.at(0)?.scope ?? "global", "user");
    assert.equal(parsed.secrets.at(0)?.full_name() ?? "", "github.token");
    assert.equal(parsed.operations.length(), 5);

    let render = parsed.operations.at(3);
    assert.equal(render?.kind ?? OperationKind.Link, OperationKind.Render);
    assert.equal(render?.sources?.length() ?? 0, 2);
    assert.equal(render?.mode ?? "", "0600");

    let excepted = parsed.operations.at(1);
    assert.equal(excepted?.selectors?.at(0)?.label() ?? "", "except host laptop")
}

test "reject invalid map entries" {
    let diag = new_diagnostics();
    let _ = parse_fixture_text(
        "oparch dotfiles map\n"
            + "version = '0.1'\n"
            + "[dotfiles.broken]\n"
            + "link 'a' to '/b' with mode '0640'\n"
            + "copy 'a' to '/b' with mode '9999'\n"
            + "move 'a' to '/b'\n"
            + "copy 'a' to '/b' for user 'x' for user 'y'\n"
            + "copy 'a' to '/b' with ownership 'nobody'\n"
            + "copy 'a' to '/b' for group 'x'\n"
            + "[unknown.section]\n",
        diag,
    );
    assert.equal(diag.errors.length(), 7);
    assert.is_true(diag.errors.at(0)?.includes("'mode' is invalid for 'link'") ?? false);
    assert.is_true(diag.errors.at(1)?.includes("invalid mode '9999'") ?? false);
    assert.is_true(diag.errors.at(2)?.includes("unknown operation 'move'") ?? false);
    assert.is_true(diag.errors.at(3)?.includes("duplicate 'for user' selector") ?? false);
    assert.is_true(diag.errors.at(4)?.includes("invalid ownership 'nobody'") ?? false);
    assert
        .is_true(diag.errors.at(5)?.includes("'for' must be followed by 'user' or 'host'") ?? false);
    assert.is_true(diag.errors.at(6)?.includes("unknown section 'unknown.section'") ?? false)
}

test "reject a file without the header or without a version" {
    let missing_header = new_diagnostics();
    assert.is_true(parse_map_text("version = '0.1'\n", "m.dfmap", missing_header) == null);
    assert.is_true(missing_header.errors.at(0)?.includes("oparch dotfiles map") ?? false);

    let missing_version = new_diagnostics();
    assert
        .is_true(
            parse_map_text("oparch dotfiles map\n[packages]\nuwsm\n", "m.dfmap", missing_version)
                == null,
        );

    let late_version = new_diagnostics();
    let _ = parse_map_text("oparch dotfiles map\n[packages]\nversion = '0.1'\n", "m.dfmap", late_version);
    assert
        .is_true(late_version.errors.at(0)?.includes("must come before the first section") ?? false)
}

test "map version acceptance" {
    let unimplemented_major = new_diagnostics();
    check_map_version(MapVersion { major: 1, minor: 0 }, unimplemented_major);
    assert
        .is_true(
            unimplemented_major.errors.at(0)?.includes("is not implemented by this tool") ?? false,
        );

    let newer_minor = new_diagnostics();
    check_map_version(MapVersion { major: 0, minor: 9 }, newer_minor);
    assert
        .is_true(newer_minor.errors.at(0)?.includes("is newer than this tool implements") ?? false);

    let current = new_diagnostics();
    check_map_version(MapVersion { major: 0, minor: 1 }, current);
    assert.is_true(!current.has_errors())
}

test "expand the fixture include graph into a plan" {
    let diag = new_diagnostics();
    let document = load_map_document(`${fixture_source_root()}/main.dfmap`, fixture_source_root(), diag);
    assert.not_null(document);

    let map = document
        ?? MapDocument {
            version: MapVersion { major: 0, minor: 0 },
            files: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    assert.equal(map.files.length(), 3);

    let plan = build_plan(map, fixture_machine(), fixture_source_root(), fixture_secrets_root(), diag);
    assert.equal(diag.errors, []);
    //# host selectors keep the laptop-only package out of the desktop plan
    assert.equal(plan.packages, ["hyprland", "uwsm", "nvidia"]);
    assert.equal(plan.aur_packages, ["opencode"]);

    let targets = targets_of(plan);
    assert.is_true(targets.includes("/home/personal/.config/hypr/keybindings.lua"));
    assert.is_true(targets.includes("/home/work/.config/hypr/keybindings.lua"));
    //# `except host 'laptop'` stays active on the desktop
    assert.is_true(targets.includes("/home/personal/.config/hypr/animations.lua"));
    //# the selector on the include entry is inherited by the included rule
    assert.is_true(targets.includes("/home/personal/.config/hypr/monitors.lua"));
    //# a directory source maps every normal file under it, recursively
    assert.is_true(targets.includes("/home/work/.config/opencode/agent/build.md"));
    assert.is_true(targets.includes("/home/work/.config/opencode/agent/nested/plan.md"));
    //# a target with no user placeholder is global and applies once
    assert.is_true(targets.includes("/boot/grub.cfg"));
    assert.equal(targets.length(), 13);

    let render = plan
        .targets
        .find(
            (planned) -> {
                planned.action == "render"
            },
        );
    assert.equal(render?.mode ?? "", "0600");
    assert.equal(render?.value_refs ?? [], ["github.username"]);
    assert.equal(render?.secret_refs ?? [], ["github.token"]);
    assert.equal(render?.owner ?? "", "personal");
    assert.equal(render?.group ?? "", "personal");

    let global_copy = plan
        .targets
        .find(
            (planned) -> {
                planned.target == "/boot/grub.cfg"
            },
        );
    assert.equal(global_copy?.owner ?? "", "root");
    assert.equal(global_copy?.mode ?? "", "0440");

    let link = plan
        .targets
        .find(
            (planned) -> {
                planned.target == "/home/work/.config/hypr/keybindings.lua"
            },
        );
    assert.equal(link?.mode ?? "unset", "unset");
    assert.equal(link?.sources ?? [], ["tests/fixtures/dotfiles/hypr/keybindings.lua"])
}

test "the fixture plan renders with the staged secret store" {
    let diag = new_diagnostics();
    let document = load_map_document(`${fixture_source_root()}/main.dfmap`, fixture_source_root(), diag);
    let map = document
        ?? MapDocument {
            version: MapVersion { major: 0, minor: 0 },
            files: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    let machine = fixture_machine();
    let plan = build_plan(map, machine, fixture_source_root(), fixture_secrets_root(), diag);
    let catalog = Catalog { values: map.values, secrets: map.secrets, secrets_root: fixture_secrets_root() };

    let render = plan
        .targets
        .find(
            (planned) -> {
                planned.target == "/home/work/.config/opencode/mcp.conf"
            },
        );
    let content = render_target_content(
        render ?? plan.targets.at(0)
            ?? PlannedTarget {
                action: "render",
                sources: [],
                target: "",
                mode: null,
                owner: "",
                group: "",
                username: null,
                home: null,
                template: "",
                value_refs: [],
                secret_refs: [],
                loc: SourceLoc { file: "", line: 0 },
            },
        catalog,
        machine.hostname,
        diag,
    );
    assert.equal(diag.errors, []);
    assert
        .equal(
            content ?? "",
            "{\n    \"user\": \"work\",\n    \"github\": {\n        \"account\": \"work-account\",\n        \"personalAccessToken\": \"test-token-work\"\n    }\n}\n",
        )
}

test "reject conflicting and out-of-bounds rules" {
    let diag = new_diagnostics();
    let file = parse_fixture_text(
        "oparch dotfiles map\n"
            + "version = '0.1'\n"
            + "[dotfiles.conflict]\n"
            + "link 'hypr/keybindings.lua' to '&HOME/.config/a.lua'\n"
            + "link 'hypr/animations.lua' to '&HOME/.config/a.lua'\n"
            + "link 'hypr/keybindings.lua' to '/etc/global.lua' for user 'work'\n"
            + "link '../outside.lua' to '&HOME/.config/b.lua'\n"
            + "link 'hypr/keybindings.lua' to 'relative/c.lua'\n"
            + "link 'hypr/keybindings.lua' to '&HOME/.config/&NOPE/d.lua'\n",
        diag,
    );
    let parsed = file
        ?? MapFile {
            path: "",
            version: MapVersion { major: 0, minor: 0 },
            includes: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    let document = MapDocument {
        version: parsed.version,
        files: [parsed.path],
        packages: parsed.packages,
        values: parsed.values,
        secrets: parsed.secrets,
        operations: parsed.operations,
    };
    let single_user = Machine {
        hostname: "desktop",
        users: [DotfilesUser { name: "personal", home: "/home/personal", group: "personal" }],
    };
    let _ = build_plan(document, single_user, fixture_source_root(), fixture_secrets_root(), diag);

    let joined = diag.errors.join("\n");
    assert.is_true(joined.includes("is already produced by the active operation"));
    assert.is_true(joined.includes("user selectors are invalid on global target"));
    assert.is_true(joined.includes("escapes the source directory"));
    assert.is_true(joined.includes("does not resolve to an absolute path"));
    assert.is_true(joined.includes("unknown placeholder '&NOPE'"))
}
