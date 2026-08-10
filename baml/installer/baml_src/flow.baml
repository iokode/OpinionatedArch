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
function resolve_config(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                        asset_dir: string, config_text: string?) -> InstallConfig? {
    if let text: string = config_text {
        //# non-interactive: the file is the answer to every question
        let parsed = parse_config_file(text);
        if (parsed.error != "") {
            ui.error(parsed.error);
            return null;
        }
        let problem = check_config(shell, files, parsed.config, asset_dir);
        if (problem != "") {
            ui.error(problem);
            return null;
        }
        return parsed.config;
    }
    collect_config(shell, files, ui, asset_dir)
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
function run_phases(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                    config: InstallConfig, target: root.common.Target, asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
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

    run_phase(files, configure_initramfs(shell, files, ui, config, target))
}

function install(shell: root.common.Shell, files: root.common.Files, ui: Ui, asset_dir: string,
                 config_text: string?) -> InstallSummary {
    if let config: InstallConfig = resolve_config(shell, files, ui, asset_dir, config_text) {
        let problem = run_phases(shell, files, ui, config,
                                 root.common.mounted_target(install_root()), asset_dir)
            catch (e) { baml.errors.InvalidArgument => e.message };

        if (problem != "") {
            ui.error(problem);
            return InstallSummary { disk: config.disk, exit_code: 1 };
        }
        ui.step("Installation finished");
        InstallSummary { disk: config.disk, exit_code: 0 }
    } else {
        //# cancelled at the first screen, or a config file that cannot be used
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
    on_file_failure: () -> string? throws never,
    on_write: (string, string) -> void throws never,
    on_read: (string) -> string? throws never,
    on_exists: (string) -> bool throws never,
    on_mkdir: (string) -> void throws never,
    on_symlink: (string, string) -> void throws never,
    on_chmod: (string, string) -> void throws never,
    on_outline: (string[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_choose: (string, string, string[], int) -> int? throws never,
    on_choose_many: (string, string, string[], string[], int, int) -> string[]? throws never,
    on_text: (string, string, string, bool) -> string? throws never,
    on_pick_package: (string, string, string) -> string? throws never,
    on_pick_file: (string, string, string) -> string? throws never,
    on_review: (string, string[]) -> bool throws never,
) -> InstallSummary {
    install(
        root.common.HostShell {
            on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
        },
        root.common.HostFiles {
            on_failure: on_file_failure,
            on_write: on_write,
            on_read: on_read,
            on_exists: on_exists,
            on_mkdir: on_mkdir,
            on_symlink: on_symlink,
            on_chmod: on_chmod,
        },
        HostUi {
            on_outline: on_outline,
            on_step: on_step,
            on_error: on_error,
            on_choose: on_choose,
            on_choose_many: on_choose_many,
            on_text: on_text,
            on_pick_package: on_pick_package,
            on_pick_file: on_pick_file,
            on_review: on_review,
        },
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
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let summary = install(shell, full_run_files(), ui, "/assets", full_config_text());

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
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let summary = install(shell, root.common.recording_files(), ui, "/assets", "disk: /dev/sda\nwat: 1\n");

    assert.equal(ui.errors, ["Unknown key in config file: wat"]);
    assert.equal(summary.exit_code, 130);
    assert.equal(shell.streamed, [])
}

test "without a config file the form is asked" {
    let ui = scripted([
        "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none",
        "0", "0", "ivan", "s", "s", "es", "UTC", "oparch", "no", "no", "start",
    ]);

    let summary = install(fake_live_shell(), root.common.recording_files(), ui, "/assets", null);

    assert.equal(ui.steps.slice(0, step_names().length()), step_names());
    assert.equal(summary.disk, "/dev/sda")
}

function full_run_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/mnt/etc/locale.gen", "#en_US.UTF-8 UTF-8\n");
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());
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
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let summary = install(full_run_shell(), full_run_files(), ui, "/assets", full_config_text());

    assert.equal(summary.exit_code, 0);
    assert.equal(ui.steps, [
        "Partitioning /dev/sda",
        "Formatting EFI partition /dev/sda1",
        "Creating LUKS2 container on /dev/sda2",
        "Opening LUKS2 container on /dev/sda2",
        "Creating Btrfs filesystem",
        "Mounting the target layout",
        "Disk layout is ready",
        "Installing base system",
        "Writing the mount table",
        "Downloading the Arch netboot binary",
        "Configuring localization",
        "Configuring system identity",
        "Creating users and groups",
        "Enabling the network stack",
        "Configuring swap",
        "Building the initramfs",
        "Installation finished",
    ])
}

/// The same run, asking for a return message. The package the values are
/// checked against has to be on the live system, so the files are the ones the
/// configuration tests use, with the target's locale.gen added.
function full_run_message_files() -> root.common.RecordingFiles {
    let files = packaged_files();
    files.write("/mnt/etc/locale.gen", "#en_US.UTF-8 UTF-8\n");
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());
    files
}

function full_message_config_text() -> string {
    full_config_text()
        + "return_message:\n"
        + "  languages:\n    - \"es\"\n"
        + "  fields:\n    owner_name: \"Ivan\"\n    phone: \"+34 666 555 666\"\n"
        + "  logo:\n    origin: url\n    location: \"https://example.invalid/logo.png\"\n"
}

test "a return message adds its phase after swap, and the theme becomes the default" {
    let shell = full_run_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let summary = install(shell, full_run_message_files(), ui, "/assets", full_message_config_text());

    assert.equal(summary.exit_code, 0);
    assert.equal(ui.steps, [
        "Partitioning /dev/sda",
        "Formatting EFI partition /dev/sda1",
        "Creating LUKS2 container on /dev/sda2",
        "Opening LUKS2 container on /dev/sda2",
        "Creating Btrfs filesystem",
        "Mounting the target layout",
        "Disk layout is ready",
        "Installing base system",
        "Writing the mount table",
        "Downloading the Arch netboot binary",
        "Configuring localization",
        "Configuring system identity",
        "Creating users and groups",
        "Enabling the network stack",
        "Configuring swap",
        "Rendering the pre-boot return message",
        "Building the initramfs",
        "Installation finished",
    ]);
    //# plymouth is installed with the base system, and the theme is its own
    assert.is_true(shell.streamed.join(" ").includes(" plymouth"));
    assert.is_true(shell.commands.includes(
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes"));
    assert.is_true(shell.commands.includes(rendered_with_logo()));
    assert.is_true(shell.commands.includes(
        "arch-chroot /mnt plymouth-set-default-theme opinionatedarch"))
}

test "a phase that fails stops the ones after it" {
    let shell = full_run_shell();
    let _ = shell.exit_codes.set("arch-chroot /mnt locale-gen", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let summary = install(shell, full_run_files(), ui, "/assets", full_config_text());

    assert.equal(summary.exit_code, 1);
    assert.equal(ui.errors, ["locale-gen failed with exit code 1."]);
    //# the phases after localization never ran
    assert.is_true(!ui.steps.includes("Creating users and groups"));
    assert.is_true(!shell.commands.includes("arch-chroot /mnt groupadd dotfiles"))
}

test "a file operation that fails stops the installation" {
    let files = full_run_files();
    files.fails_with = "cannot write /mnt/etc/fstab: read-only file system";
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let summary = install(full_run_shell(), files, ui, "/assets", full_config_text());

    assert.equal(summary.exit_code, 1);
    assert.equal(ui.errors, ["cannot write /mnt/etc/fstab: read-only file system"]);
    assert.is_true(!ui.steps.includes("Installation finished"))
}
