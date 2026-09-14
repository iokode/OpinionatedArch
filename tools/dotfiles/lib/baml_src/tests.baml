// End-to-end tests over the parser, the include graph and the plan builder.
// The fixture map under `tests/fixtures/dotfiles` mirrors the example in
// `docs/tools/oparch-dotfiles-sync/001-map-format.md`.
//
// They are in the root namespace of the library rather than inside it, because
// they read fixtures by a path relative to this project, and a test inside the
// namespace also runs in every project the namespace is linked into.

/// The fixtures are real files on disk, so the tests read them through the
/// real port rather than through a double pretending to be one.
function fixture_files() -> root.common.Files {
    root.common.system_files()
}

function fixture_source_root() -> string {
    "tests/fixtures/dotfiles"
}

function fixture_secrets_root() -> string {
    "tests/fixtures/secrets"
}

function fixture_machine() -> root.dotfiles.Machine {
    root.dotfiles.Machine {
        hostname: "desktop",
        users: [
            root.dotfiles.DotfilesUser { name: "personal", home: "/home/personal", group: "personal" },
            root.dotfiles.DotfilesUser { name: "work", home: "/home/work", group: "work" },
        ],
    }
}

function targets_of(plan: root.dotfiles.Plan) -> string[] {
    plan.targets
        .map(
            (planned) -> {
                planned.target
            },
        )
}

function parse_fixture_text(text: string, diag: root.dotfiles.Diagnostics) -> root.dotfiles.MapFile? {
    root.dotfiles.parse_map_text(text, "memory.dfmap", diag)
}

test "parse the documented example map" {
    let diag = root.dotfiles.new_diagnostics();
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
        ?? root.dotfiles.MapFile {
            path: "",
            version: root.dotfiles.MapVersion { major: 0, minor: 0 },
            includes: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    assert.equal(parsed.version, root.dotfiles.MapVersion { major: 0, minor: 1 });
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
    assert.equal(render?.kind ?? root.dotfiles.OperationKind.Link, root.dotfiles.OperationKind.Render);
    assert.equal(render?.sources?.length() ?? 0, 2);
    assert.equal(render?.mode ?? "", "0600");

    let excepted = parsed.operations.at(1);
    assert.equal(excepted?.selectors?.at(0)?.label() ?? "", "except host laptop")
}

test "reject invalid map entries" {
    let diag = root.dotfiles.new_diagnostics();
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
    let missing_header = root.dotfiles.new_diagnostics();
    assert.is_true(root.dotfiles.parse_map_text("version = '0.1'\n", "m.dfmap", missing_header) == null);
    assert.is_true(missing_header.errors.at(0)?.includes("oparch dotfiles map") ?? false);

    let missing_version = root.dotfiles.new_diagnostics();
    assert
        .is_true(
            root.dotfiles.parse_map_text("oparch dotfiles map\n[packages]\nuwsm\n", "m.dfmap", missing_version)
                == null,
        );

    let late_version = root.dotfiles.new_diagnostics();
    let _ = root.dotfiles.parse_map_text("oparch dotfiles map\n[packages]\nversion = '0.1'\n", "m.dfmap", late_version);
    assert
        .is_true(late_version.errors.at(0)?.includes("must come before the first section") ?? false)
}

test "map version acceptance" {
    let unimplemented_major = root.dotfiles.new_diagnostics();
    root.dotfiles.check_map_version(root.dotfiles.MapVersion { major: 1, minor: 0 }, unimplemented_major);
    assert
        .is_true(
            unimplemented_major.errors.at(0)?.includes("is not implemented by this tool") ?? false,
        );

    let newer_minor = root.dotfiles.new_diagnostics();
    root.dotfiles.check_map_version(root.dotfiles.MapVersion { major: 0, minor: 9 }, newer_minor);
    assert
        .is_true(newer_minor.errors.at(0)?.includes("is newer than this tool implements") ?? false);

    let current = root.dotfiles.new_diagnostics();
    root.dotfiles.check_map_version(root.dotfiles.MapVersion { major: 0, minor: 1 }, current);
    assert.is_true(!current.has_errors())
}

test "expand the fixture include graph into a plan" {
    let diag = root.dotfiles.new_diagnostics();
    let document = root.dotfiles.load_map_document(fixture_files(), `${fixture_source_root()}/main.dfmap`, fixture_source_root(), diag);
    assert.not_null(document);

    let map = document
        ?? root.dotfiles.MapDocument {
            version: root.dotfiles.MapVersion { major: 0, minor: 0 },
            files: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    assert.equal(map.files.length(), 3);

    let plan = root.dotfiles.build_plan(fixture_files(), map, fixture_machine(), fixture_source_root(), fixture_secrets_root(), true, diag);
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

/// The fixture map, loaded, for a test that only cares about the plan built
/// from it.
function fixture_document(diag: root.dotfiles.Diagnostics) -> root.dotfiles.MapDocument {
    root.dotfiles.load_map_document(fixture_files(), `${fixture_source_root()}/main.dfmap`,
                                    fixture_source_root(), diag)
        ?? root.dotfiles.MapDocument {
            version: root.dotfiles.MapVersion { major: 0, minor: 0 },
            files: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        }
}

test "what a plan needs from the store can be asked for before there is one" {
    let diag = root.dotfiles.new_diagnostics();
    let document = fixture_document(diag);

    //# a store that is not there: the question is what would have to be in it
    let plan = root.dotfiles.build_plan(fixture_files(), document, fixture_machine(), fixture_source_root(),
                                        "tests/fixtures/no-such-store", false, diag);

    assert.equal(diag.errors, []);
    //# named as it sits inside the store, which is what an archive has to hold,
    //# and a user-scoped secret is a file per user rather than one file
    assert.equal(root.dotfiles.required_secret_files(plan),
                 ["user/personal/github.token", "user/work/github.token"])
}

test "the same plan, meant to be carried out, says the store file is missing" {
    let diag = root.dotfiles.new_diagnostics();
    let document = fixture_document(diag);

    let _ = root.dotfiles.build_plan(fixture_files(), document, fixture_machine(), fixture_source_root(),
                                     "tests/fixtures/no-such-store", true, diag);

    assert.is_true(diag.has_errors());
    assert.is_true(diag.errors.join("\n")
        .includes("secret 'github.token' is required but its store file is missing"))
}

test "a plan that needs no secrets asks for none" {
    let diag = root.dotfiles.new_diagnostics();
    let document = fixture_document(diag);
    //# the render belongs to a user target, so a machine with no users
    //# reaches no secret at all
    let empty = root.dotfiles.Machine { hostname: "desktop", users: [] };

    let plan = root.dotfiles.build_plan(fixture_files(), document, empty, fixture_source_root(),
                                        fixture_secrets_root(), false, diag);

    assert.equal(root.dotfiles.required_secret_files(plan), [])
}

test "the fixture plan renders with the staged secret store" {
    let diag = root.dotfiles.new_diagnostics();
    let document = root.dotfiles.load_map_document(fixture_files(), `${fixture_source_root()}/main.dfmap`, fixture_source_root(), diag);
    let map = document
        ?? root.dotfiles.MapDocument {
            version: root.dotfiles.MapVersion { major: 0, minor: 0 },
            files: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    let machine = fixture_machine();
    let plan = root.dotfiles.build_plan(fixture_files(), map, machine, fixture_source_root(), fixture_secrets_root(), true, diag);
    let catalog = root.dotfiles.Catalog { values: map.values, secrets: map.secrets, secrets_root: fixture_secrets_root() };

    let render = plan
        .targets
        .find(
            (planned) -> {
                planned.target == "/home/work/.config/opencode/mcp.conf"
            },
        );
    let content = root.dotfiles.render_target_content(
        fixture_files(),
        render ?? plan.targets.at(0)
            ?? root.dotfiles.PlannedTarget {
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
                secret_files: [],
                loc: root.dotfiles.SourceLoc { file: "", line: 0 },
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
    let diag = root.dotfiles.new_diagnostics();
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
        ?? root.dotfiles.MapFile {
            path: "",
            version: root.dotfiles.MapVersion { major: 0, minor: 0 },
            includes: [],
            packages: [],
            values: [],
            secrets: [],
            operations: [],
        };
    let document = root.dotfiles.MapDocument {
        version: parsed.version,
        files: [parsed.path],
        packages: parsed.packages,
        values: parsed.values,
        secrets: parsed.secrets,
        operations: parsed.operations,
    };
    let single_user = root.dotfiles.Machine {
        hostname: "desktop",
        users: [root.dotfiles.DotfilesUser { name: "personal", home: "/home/personal", group: "personal" }],
    };
    let _ = root.dotfiles.build_plan(fixture_files(), document, single_user, fixture_source_root(), fixture_secrets_root(), true, diag);

    let joined = diag.errors.join("\n");
    assert.is_true(joined.includes("is already produced by the active operation"));
    assert.is_true(joined.includes("user selectors are invalid on global target"));
    assert.is_true(joined.includes("escapes the source directory"));
    assert.is_true(joined.includes("does not resolve to an absolute path"));
    assert.is_true(joined.includes("unknown placeholder '&NOPE'"))
}

// ---------------------------------------------- failures folded into the diag

function failing_files(problem: string) -> root.common.RecordingFiles {
    root.common.RecordingFiles {
        fails_with: problem,
        written: {},
        directories: [],
        symlinks: {},
        modes: {},
        present: [],
    }
}

function silent_shell() -> root.common.RecordingShell {
    root.common.RecordingShell { commands: [], streamed: [], fed: [], replies: {}, exit_codes: {} }
}

test "what the filesystem port recorded becomes a diagnostic" {
    let diag = root.dotfiles.new_diagnostics();

    root.dotfiles.absorb_file_failure(failing_files("cannot write /etc/x: Permission denied"), diag);

    assert.equal(diag.errors, ["cannot write /etc/x: Permission denied"])
}

test "a port with nothing to report adds nothing" {
    let diag = root.dotfiles.new_diagnostics();

    root.dotfiles.absorb_file_failure(root.common.recording_files(), diag);

    assert.is_true(!diag.has_errors())
}

test "a write that failed is held by the port until it is folded in" {
    let diag = root.dotfiles.new_diagnostics();
    let problem = "cannot write /var/lib/oparch/dotfiles-sync/state.json: Permission denied";
    let files = failing_files(problem);

    root.dotfiles.write_sync_state(silent_shell(), files, "/var/lib/oparch/dotfiles-sync", ["/etc/x"], diag);

    //# the operation says nothing on its own: that is the contract of the port
    assert.is_true(!diag.has_errors());

    root.dotfiles.absorb_file_failure(files, diag);
    assert.equal(diag.errors, [problem])
}

test "a command that failed is reported where it happened, with what it said" {
    let diag = root.dotfiles.new_diagnostics();
    let shell = silent_shell();
    let _ = shell.exit_codes.set("rm -f /etc/x", 1);

    let gone = root.dotfiles.remove_target(shell, "/etc/x", diag);

    assert.is_true(!gone);
    assert.equal(diag.errors, ["removing '/etc/x' failed with exit code 1."])
}

// ----------------------------------------------------------- applying a plan

function planned_target(action: "link" | "copy" | "render", sources: string[],
                        target: string) -> root.dotfiles.PlannedTarget {
    root.dotfiles.PlannedTarget {
        action: action,
        sources: sources,
        target: target,
        mode: null,
        owner: "personal",
        group: "personal",
        username: "personal",
        home: "/home/personal",
        template: null,
        value_refs: [],
        secret_refs: [],
        secret_files: [],
        loc: root.dotfiles.SourceLoc { file: "main.dfmap", line: 1 },
    }
}

test "a link is made only after its parents exist and what was there is gone" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();

    let done = root.dotfiles.apply_link(shell, files,
        planned_target("link", ["/dotfiles/hypr/keybindings.lua"],
                       "/home/personal/.config/hypr/keybindings.lua"),
        diag);

    assert.is_true(done);
    //# the order is the point: a link written before its parent exists fails,
    //# and one written over a file that is still there fails too. `-h` owns the
    //# link rather than whatever it points at
    assert.equal(shell.commands, [
        "install -d -o personal -g personal /home",
        "install -d -o personal -g personal /home/personal",
        "install -d -o personal -g personal /home/personal/.config",
        "install -d -o personal -g personal /home/personal/.config/hypr",
        "rm -f /home/personal/.config/hypr/keybindings.lua",
        "ln -s /dotfiles/hypr/keybindings.lua /home/personal/.config/hypr/keybindings.lua",
        "chown -h personal:personal /home/personal/.config/hypr/keybindings.lua",
    ]);
    assert.is_true(!diag.has_errors())
}

test "a link whose target cannot be cleared is not made over it" {
    let shell = silent_shell();
    let _ = shell.exit_codes.set("rm -f /etc/held", 1);
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();

    let done = root.dotfiles.apply_link(shell, files, planned_target("link", ["/dotfiles/held"], "/etc/held"), diag);

    assert.is_true(!done);
    //# whatever is still there is left alone rather than linked over
    assert.is_true(!shell.commands.join(" ").includes("ln -s"));
    assert.is_true(diag.has_errors())
}

test "a copy carries the mode, owner and group it was planned with" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    let target = planned_target("copy", ["/dotfiles/grub/grub.cfg"], "/boot/grub/grub.cfg");
    target.mode = "0644";
    target.owner = "root";
    target.group = "root";

    assert.is_true(root.dotfiles.apply_copy(shell, files, target, diag));

    assert.is_true(shell.commands.includes(
        "install -m 0644 -o root -g root /dotfiles/grub/grub.cfg /boot/grub/grub.cfg"))
}

test "a copy with no mode of its own gets the default one" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();

    let _ = root.dotfiles.apply_copy(shell, files,
        planned_target("copy", ["/dotfiles/a"], "/home/personal/a"), diag);

    assert.is_true(shell.commands.includes(
        `install -m ${root.dotfiles.default_output_mode()} -o personal -g personal /dotfiles/a /home/personal/a`))
}

function render_plan(template: string, secret_refs: string[]) -> root.dotfiles.Plan {
    let target = planned_target("render", ["/dotfiles/mcp.conf.tpl"],
                                "/home/personal/.config/opencode/mcp.conf");
    target.template = template;
    target.secret_refs = secret_refs;
    root.dotfiles.Plan { targets: [target], packages: [], aur_packages: [] }
}

function token_catalog() -> root.dotfiles.Catalog {
    let loc = root.dotfiles.SourceLoc { file: "main.dfmap", line: 1 };
    root.dotfiles.Catalog {
        values: [],
        secrets: [root.dotfiles.SecretDecl { category: "github", key: "token", scope: "user", selectors: [], loc: loc }],
        secrets_root: root.dotfiles.default_secrets_root(),
    }
}

test "a render is staged into a file that was restricted before it had content" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    let staging = root.dotfiles.staging_root(root.dotfiles.default_state_root());

    let staged = root.dotfiles.stage_renders(shell, files, render_plan("host is {{HOST}}\n", []),
                                             token_catalog(), fixture_machine(), root.dotfiles.default_state_root(), diag);

    //# the mode is set on an empty file first: a staged render holds secrets,
    //# and a file created readable and restricted afterwards is readable in
    //# between
    assert.equal(shell.commands, [
        `install -d -m 0700 -o root -g root ${staging}`,
        `install -m 0600 -o root -g root /dev/null ${staging}/render-0`,
    ]);
    assert.equal(files.written.get(`${staging}/render-0`), "host is desktop\n");
    assert.equal(staged.length(), 1);
    assert.is_true(!diag.has_errors())
}

test "a secret reaches the file it belongs in and no command line" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    let secret = "test-token-personal";
    //# the store, as the tool would find it on the machine
    files.write(`${root.dotfiles.default_secrets_root()}/user/personal/github.token`, secret + "\n");

    let _ = root.dotfiles.stage_renders(shell, files,
        render_plan("personalAccessToken = \"{{github.token}}\"\n", ["github.token"]),
        token_catalog(), fixture_machine(), root.dotfiles.default_state_root(), diag);

    let written = files.written.get(`${root.dotfiles.staging_root(root.dotfiles.default_state_root())}/render-0`) ?? "";
    assert.equal(written, `personalAccessToken = "${secret}"` + "\n");

    //# it went into the file and nowhere else: not into an argument, where any
    //# user of the machine could read it out of the process list
    assert.is_true(!shell.commands.join(" ").includes(secret));
    assert.is_true(!diag.has_errors())
}

test "a render whose secret is not in the store stages nothing" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();

    let staged = root.dotfiles.stage_renders(shell, files,
        render_plan("token = \"{{github.token}}\"\n", ["github.token"]),
        token_catalog(), fixture_machine(), root.dotfiles.default_state_root(), diag);

    assert.equal(staged.length(), 0);
    assert.is_true(diag.has_errors());
    //# and nothing half-written was left behind for the apply step to install
    assert.equal(files.written.get(`${root.dotfiles.staging_root(root.dotfiles.default_state_root())}/render-0`), null)
}

test "the state directory is made private, and records what the run declared" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();

    root.dotfiles.write_sync_state(shell, files, root.dotfiles.default_state_root(), ["/etc/a", "/home/personal/b"], diag);

    assert.equal(shell.commands,
                 [`install -d -m 0700 -o root -g root ${root.dotfiles.default_state_root()}`]);
    let written = files.written.get(root.dotfiles.state_file_path(root.dotfiles.default_state_root())) ?? "";
    assert.is_true(written.includes("/etc/a"));
    assert.is_true(written.includes("/home/personal/b"));

    //# and it reads back as what was written
    assert.equal(root.dotfiles.read_sync_state(files, root.dotfiles.default_state_root()).targets,
                 ["/etc/a", "/home/personal/b"])
}

test "a state file that is not there leaves nothing to remove" {
    let files = root.common.recording_files();

    assert.equal(root.dotfiles.read_sync_state(files, root.dotfiles.default_state_root()).targets, [])
}

test "a target the plan dropped is removed, and one it still declares is not" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    root.dotfiles.write_sync_state(shell, files, root.dotfiles.default_state_root(), ["/etc/kept", "/etc/dropped"], diag);
    let plan = root.dotfiles.Plan {
        targets: [planned_target("link", ["/dotfiles/kept"], "/etc/kept")],
        packages: [],
        aur_packages: [],
    };

    let removed = root.dotfiles.remove_stale_targets(shell, files, plan, root.dotfiles.default_state_root(), diag);

    assert.equal(removed, 1);
    assert.is_true(shell.commands.includes("rm -f /etc/dropped"));
    assert.is_true(!shell.commands.includes("rm -f /etc/kept"))
}

test "only the packages that are missing are installed" {
    let shell = silent_shell();
    let diag = root.dotfiles.new_diagnostics();
    //# `pacman -Qq` answers nonzero for a package that is not installed
    let _ = shell.exit_codes.set("pacman -Qq hyprland", 1);
    let plan = root.dotfiles.Plan { targets: [], packages: ["git", "hyprland"], aur_packages: [] };

    assert.equal(root.dotfiles.install_packages(shell, plan, diag), 1);

    assert.is_true(shell.commands.includes("pacman -S --needed --noconfirm hyprland"));
    assert.is_true(!diag.has_errors())
}

test "nothing is installed when every package is already there" {
    let shell = silent_shell();
    let diag = root.dotfiles.new_diagnostics();
    let plan = root.dotfiles.Plan { targets: [], packages: ["git", "hyprland"], aur_packages: [] };

    assert.equal(root.dotfiles.install_packages(shell, plan, diag), 0);

    //# asked about, never installed
    assert.is_true(!shell.commands.join(" ").includes("pacman -S"))
}

test "packages that failed to install are reported with what pacman said" {
    let shell = silent_shell();
    let diag = root.dotfiles.new_diagnostics();
    let _ = shell.exit_codes.set("pacman -Qq hyprland", 1);
    let _ = shell.exit_codes.set("pacman -S --needed --noconfirm hyprland", 1);
    let plan = root.dotfiles.Plan { targets: [], packages: ["hyprland"], aur_packages: [] };

    assert.equal(root.dotfiles.install_packages(shell, plan, diag), 0);

    assert.equal(diag.errors, ["installing hyprland failed with exit code 1."])
}

test "each planned target is applied by the action it carries" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    let render = planned_target("render", ["/dotfiles/mcp.tpl"], "/home/personal/mcp.conf");
    let plan = root.dotfiles.Plan {
        targets: [
            planned_target("link", ["/dotfiles/a"], "/home/personal/a"),
            planned_target("copy", ["/dotfiles/b"], "/home/personal/b"),
            render,
        ],
        packages: [],
        aur_packages: [],
    };
    let staged = [root.dotfiles.StagedRender { target: render.target, staged_path: "/staged/render-0" }];

    assert.equal(root.dotfiles.apply_targets(shell, files, plan, staged, diag), 3);

    let ran = shell.commands.join("\n");
    assert.is_true(ran.includes("ln -s /dotfiles/a /home/personal/a"));
    assert.is_true(ran.includes("/dotfiles/b /home/personal/b"));
    assert.is_true(ran.includes("/staged/render-0 /home/personal/mcp.conf"));
    assert.is_true(!diag.has_errors())
}

test "a render that was never staged is not applied from nowhere" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    let plan = root.dotfiles.Plan {
        targets: [planned_target("render", ["/dotfiles/mcp.tpl"], "/home/personal/mcp.conf")],
        packages: [],
        aur_packages: [],
    };
    let nothing: root.dotfiles.StagedRender[] = [];

    assert.equal(root.dotfiles.apply_targets(shell, files, plan, nothing, diag), 0);

    assert.is_true(diag.has_errors());
    assert.is_true(!shell.commands.join(" ").includes("/home/personal/mcp.conf"))
}

test "a parent that is already there is left as it is" {
    let shell = silent_shell();
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();
    files.mkdir("/home");
    files.mkdir("/home/personal");

    let made = root.dotfiles.ensure_parent_directories(shell, files, "/home/personal/.config/hypr/a.lua",
                                                       "personal", "personal", diag);

    assert.is_true(made);
    //# only what was missing, and each with the ownership the target carries:
    //# remaking one that exists would take a directory somebody else owns
    assert.equal(shell.commands, [
        "install -d -o personal -g personal /home/personal/.config",
        "install -d -o personal -g personal /home/personal/.config/hypr",
    ])
}

test "a parent that cannot be made is reported and stops the target" {
    let shell = silent_shell();
    let _ = shell.exit_codes.set("install -d -o personal -g personal /home", 1);
    let files = root.common.recording_files();
    let diag = root.dotfiles.new_diagnostics();

    let done = root.dotfiles.apply_copy(shell, files,
        planned_target("copy", ["/dotfiles/a"], "/home/personal/a"), diag);

    assert.is_true(!done);
    assert.is_true(diag.has_errors());
    //# nothing was installed into a directory that is not there
    assert.is_true(!shell.commands.join(" ").includes("/dotfiles/a /home/personal/a"))
}
