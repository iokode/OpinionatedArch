// The installer flow. Everything here programs against Shell and Ui, so it
// runs identically against the real host and against test doubles.

/// Reads the selectable disks, filling in size and model per device.
function list_disks(shell: root.common.Shell) -> DiskTarget[] {
    let out = shell.capture("lsblk", ["-dpno", "NAME,TYPE"]);
    let disks: DiskTarget[] = [];
    for (let path in parse_disk_paths(out.stdout)) {
        disks
            .push(
                DiskTarget {
                    path: path,
                    size: parse_lsblk_field(shell.capture("lsblk", ["-dno", "SIZE", path]).stdout),
                    model: parse_lsblk_field(shell.capture("lsblk", ["-dno", "MODEL", path]).stdout),
                },
            );
    }
    disks
}

//# the flow itself

/// The config either comes from a file or from the person at the terminal.
/// Both produce the same `InstallConfig`, and everything after this point is
/// identical for the two.
function resolve_config(shell: root.common.Shell, files: root.common.Files, secrets: Secrets,
                        ui: Ui, asset_dir: string, config_text: string?) -> InstallConfig? {
    if let text: string = config_text {
        //# non-interactive: the file is the answer to every question
        let parsed = parse_config_file(text);
        if (parsed.error != "") {
            ui.error(parsed.error);
            return null;
        }
        let problem = check_config(shell, files, secrets, parsed.config, asset_dir);
        if (problem != "") {
            ui.error(problem);
            return null;
        }
        return parsed.config;
    }
    collect_config(shell, files, secrets, ui, asset_dir)
}

/// Where the system being installed is mounted while the installer runs.
function install_root() -> string {
    "/mnt"
}

/// Runs one phase and reports the first thing that went wrong: the phase's own
/// error, or a file operation that failed inside it.
function run_phase(files: root.common.Files, problem: string) -> string {
    if (problem != "") {
        return problem;
    }
    files.failure() ?? ""
}

//# every phase, in order, stopping at the first failure
/// The phases, in the order they run, each in the three forms it is read in.
///
/// The list on the left names the thing without the verb, because the column is
/// narrow and the verb would be the same in every row; the log says
/// what is being done while it is being done, and the state it left once the
/// next phase has begun. A test holds every `ui.step` of a run to this list, so a
/// phase cannot be added without appearing in it.
///
/// The return message is here only when one was asked for, because a list that
/// shows a phase that will not run is a list that lies about how much is left.
function install_phases(config: InstallConfig) -> Phase[] {
    let phases = [
        Phase { to_do: "Disk", doing: "Preparing the disk...",
                done: "Disk prepared." },
        Phase { to_do: "Packages", doing: "Installing packages...",
                done: "Packages installed." },
        Phase { to_do: "Localization", doing: "Configuring localization...",
                done: "Localization configured." },
        Phase { to_do: "System identity", doing: "Configuring system identity...",
                done: "System identity configured." },
        Phase { to_do: "Users and groups", doing: "Creating users and groups...",
                done: "Users and groups created." },
        Phase { to_do: "Network stack", doing: "Enabling the network stack...",
                done: "Network stack enabled." },
        Phase { to_do: "Swap", doing: "Configuring swap...",
                done: "Swap configured." },
    ];
    if (config.return_message != null) {
        phases.push(Phase {
            to_do: "Return message",
            doing: "Rendering the pre-boot return message...",
            done: "Pre-boot return message rendered.",
        });
    }
    phases.push(Phase { to_do: "Initramfs", doing: "Building the initramfs...",
                        done: "Initramfs built." });
    phases.push(Phase { to_do: "Bootloader", doing: "Installing the bootloader...",
                        done: "Bootloader installed." });
    if (config.dotfiles != null) {
        phases.push(Phase {
            to_do: "Dotfiles",
            doing: "Applying the dotfiles...",
            done: "Dotfiles applied.",
        });
    }
    phases
}

/// What each phase says while it runs, which is what `ui.step` is given.
function install_phase_names(config: InstallConfig) -> string[] {
    let names: string[] = [];
    for (let phase in install_phases(config)) {
        names.push(phase.doing);
    }
    names
}

function run_phases(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                    config: InstallConfig, target: root.common.Target, asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
    //# the form is done with, so the step list becomes the installation
    ui.outline(install_phases(config));

    let problem = run_phase(files, prepare_layout(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, bootstrap_base_system(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_localization(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_identity(files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_users(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_network(shell, ui, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_swap(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    //# before the initramfs is built: the plymouth hook packs the theme, and
    //# the images the renderer put in it, into the image it builds
    let problem = run_phase(files, configure_return_message(shell, files, ui, config, target, asset_dir));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_initramfs(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    //# the one whose failure means the machine does not start
    let problem = run_phase(files, configure_bootloader(shell, files, ui, config, target, asset_dir));
    if (problem != "") { return problem; }

    //# last: it expands over the users the fifth phase made, installs what its
    //# map declares with the package manager the second one brought, and lays
    //# a `grub/` directory of its own over the menu just written
    run_phase(files, configure_dotfiles(shell, files, ui, config, target, live_staging_dir()))
}

function install(shell: root.common.Shell, files: root.common.Files, secrets: Secrets, ui: Ui,
                 asset_dir: string, config_text: string?) -> InstallSummary {
    if let config: InstallConfig = resolve_config(shell, files, secrets, ui, asset_dir, config_text) {
        let problem = run_phases(shell, files, ui, config,
                                 root.common.chroot_target(install_root()), asset_dir)
            catch (e) { baml.errors.InvalidArgument => e.message };

        if (problem != "") {
            ui.error(problem);
            return InstallSummary { disk: config.disk, exit_code: 1 };
        }
        InstallSummary { disk: config.disk, exit_code: 0 }
    } else {
        //# a config file that cannot be used. The form itself no longer ends
        //# this way: nothing behind its first screen means nothing to back out to
        InstallSummary { disk: "", exit_code: 130 }
    }
}

/// ENTRYPOINT. The only function the host calls, and the only place closures
/// appear. Keep the closure types inline: the `rust` generator drops any
/// function whose callback hides behind a `type` alias.
function run_installer(
    asset_dir: string,
    config_text: string?,
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
    on_sealed: (string) -> bool throws never,
    on_unseal: (string, string, string) -> string throws never,
    on_outline: (Phase[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_warn: (string) -> void throws never,
    on_tip: (string[]) -> void throws never,
    on_choose: (string, string, string[], int) -> int? throws never,
    on_choose_many: (string, string, string[], string[], int, int) -> string[]? throws never,
    on_text: (string, string, string, bool) -> string? throws never,
    on_pick_package: (string, string, string) -> string? throws never,
    on_pick_file: (string, string, string) -> string? throws never,
    on_review: (string, SummaryRow[]) -> bool throws never,
) -> InstallSummary {
    //# Only commands arrive from the host. Touching files needs neither a
    //# terminal nor output read while it is produced, which is all a host is
    //# for, as `docs/development/004-host-bridge.md` decides — so `baml.fs`
    //# does it here. `system_files()` is built once for the whole run: the
    //# first failure among the operations is asked for once per phase, and it
    //# has to survive until it is asked.
    let ui = HostUi {
            on_outline: on_outline,
            on_step: on_step,
            on_action: on_action,
            on_error: on_error,
            on_warn: on_warn,
            on_tip: on_tip,
            on_choose: on_choose,
            on_choose_many: on_choose_many,
            on_text: on_text,
            on_pick_package: on_pick_package,
            on_pick_file: on_pick_file,
            on_review: on_review,
    };
    install(
        root.common.HostShell {
            on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
        },
        AnnouncingFiles { inner: root.common.system_files(), ui: ui },
        HostSecrets { on_sealed: on_sealed, on_unseal: on_unseal },
        ui,
        asset_dir,
        config_text,
    )
}

test "a config file answers every question and the form is never shown" {
    let shell = root.common.RecordingShell {
        commands: [],
        fed: [],
        streamed: [],
        exit_codes: {},
        replies: {
            "timedatectl list-timezones": "Europe/Madrid\nUTC\n",
        },
    };
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(shell, full_run_files(), recording_secrets(), ui, "/assets", full_config_text());

    assert.equal(ui.asked, []);
    assert.equal(ui.errors, []);
    assert.equal(summary.disk, "/dev/sda");
    assert.equal(summary.exit_code, 0)
}

test "a config file that cannot be used stops before anything runs" {
    let shell = root.common.RecordingShell {
        commands: [],
        fed: [],
        streamed: [],
        exit_codes: {},
        replies: { "timedatectl list-timezones": "Europe/Madrid\n" },
    };
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(shell, root.common.recording_files(), recording_secrets(), ui, "/assets", "disk: /dev/sda\nwat: 1\n");

    assert.equal(ui.errors, ["Unknown key in config file: wat"]);
    assert.equal(summary.exit_code, 130);
    assert.equal(shell.streamed, [])
}

test "without a config file the form is asked" {
    let ui = scripted([
        "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none",
        "0", "0", "ivan", "s", "s", "UTC", "oparch", "no", "no", "start",
    ]);

    let summary = install(fake_live_shell(), root.common.recording_files(), recording_secrets(), ui, "/assets", null);

    assert.equal(ui.steps.slice(0, step_names().length()), step_names());
    assert.equal(summary.disk, "/dev/sda")
}

function full_run_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/mnt/etc/locale.gen", "#en_US.UTF-8 UTF-8\n");
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());
    files.write("/assets/grub/grub.cfg", "source ${prefix}/oparch.cfg\n");
    files
}

function full_run_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        exit_codes: {},
        replies: {
            "timedatectl list-timezones": "Europe/Madrid\n",
            "genfstab -U /mnt": "UUID=5f3a / btrfs subvol=@ 0 0\n",
            "blkid -s UUID -o value /dev/sda2": "5f3a-uuid\n",
        },
    }
}

test "the phases run in order and the installation reports success" {
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(full_run_shell(), full_run_files(), recording_secrets(), ui, "/assets", full_config_text());

    assert.equal(summary.exit_code, 0);
    //# the step list and the phases are one list, read in two forms, and the
    //# run ends past the end of it
    assert.equal(ui.outline.length(), 9);
    assert.equal(ui.steps, install_phase_names(parse_config_file(full_config_text()).config));
}

/// The same run, asking for a return message. The package the values are
/// checked against has to be on the live system, so the files are the ones the
/// configuration tests use, with the target's locale.gen added.
function full_run_message_files() -> root.common.RecordingFiles {
    let files = packaged_files();
    files.write("/mnt/etc/locale.gen", "#en_US.UTF-8 UTF-8\n");
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());
    files.write("/assets/grub/grub.cfg", "source ${prefix}/oparch.cfg\n");
    files
}

function full_message_config_text() -> string {
    full_config_text()
        + "return_message:\n"
        + "  languages:\n    - \"es\"\n"
        + "  fields:\n    owner_name: \"Ivan\"\n    phone: \"+376 000 000\"\n"
        + "  logo:\n    origin: url\n    location: \"https://example.invalid/logo.png\"\n"
}

test "a return message adds its phase after swap, and the theme becomes the default" {
    let shell = full_run_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(shell, full_run_message_files(), recording_secrets(), ui, "/assets", full_message_config_text());

    assert.equal(summary.exit_code, 0);
    //# ten with the return message, which is the one phase that is optional
    assert.equal(ui.outline.length(), 10);
    assert.is_true(ui.outline.includes("Return message"));
    assert.equal(ui.steps,
                 install_phase_names(parse_config_file(full_message_config_text()).config));
    //# plymouth is installed with the base system, and the theme is its own
    assert.is_true(shell.streamed.join(" ").includes(" plymouth"));
    assert.is_true(shell.commands.includes(
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes"));
    assert.is_true(shell.commands.includes(rendered_with_logo()));
    assert.is_true(shell.commands.includes(
        "arch-chroot /mnt plymouth-set-default-theme opinionatedarch"))
}

function full_dotfiles_config_text() -> string {
    full_config_text()
        + "dotfiles:\n  origin: git\n  location: \"https://example.invalid/dotfiles.git\"\n"
}

test "a dotfiles package adds its phase after the bootloader, and the tool is entered" {
    let shell = full_run_shell();
    let _ = shell.replies.set("which oparch-dotfiles-sync", "/usr/bin/oparch-dotfiles-sync\n");
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(shell, full_run_files(), recording_secrets(), ui, "/assets",
                          full_dotfiles_config_text());

    assert.equal(summary.exit_code, 0);
    //# ten with the dotfiles, and it is the last of them
    assert.equal(ui.outline.length(), 10);
    assert.equal(ui.outline.at(9) ?? "", "Dotfiles");
    assert.equal(ui.steps, install_phase_names(parse_config_file(full_dotfiles_config_text()).config));
    //# cloned whole, judged before the disk was touched, and entered at the end
    assert.is_true(shell.commands.includes(
        "git clone https://example.invalid/dotfiles.git /tmp/oparch/dotfiles"));
    assert.is_true(shell.commands.includes(
        "oparch-dotfiles-sync --list-secrets --source /tmp/oparch/dotfiles --hostname oparch"
            + " --user ivan"));
    assert.equal(shell.commands.at(shell.commands.length() - 1) ?? "",
                 "arch-chroot /mnt oparch-dotfiles-sync")
}

test "a phase that fails stops the ones after it" {
    let shell = full_run_shell();
    let _ = shell.exit_codes.set("arch-chroot /mnt locale-gen", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(shell, full_run_files(), recording_secrets(), ui, "/assets", full_config_text());

    assert.equal(summary.exit_code, 1);
    assert.equal(ui.errors, ["locale-gen failed with exit code 1."]);
    //# the phases after localization never ran
    assert.is_true(!ui.steps.includes("Creating users and groups"));
    assert.is_true(!shell.commands.includes("arch-chroot /mnt groupadd dotfiles"))
}

test "a file operation that fails stops the installation" {
    let files = full_run_files();
    files.fails_with = "cannot write /mnt/etc/fstab: read-only file system";
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let summary = install(full_run_shell(), files, recording_secrets(), ui, "/assets", full_config_text());

    assert.equal(summary.exit_code, 1);
    assert.equal(ui.errors, ["cannot write /mnt/etc/fstab: read-only file system"]);
    //# it stopped where it stopped: the phases after the one that failed never ran
    assert.is_true(!ui.steps.includes("Installing the bootloader..."))
}
