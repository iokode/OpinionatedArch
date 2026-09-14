// An unattended installation: a configuration file read, held to what this
// machine can do, and installed, with nobody there to ask anything.

/// Reads the configuration, checks it against the live system and installs it.
/// A file that cannot be used ends the run with 130 before anything is written.
function run(shell: root.common.Shell, files: root.common.Files, secrets: root.installer.Secrets,
             ui: root.installer.Ui, config_text: string, asset_dir: string) -> root.installer.InstallSummary {
    let parsed = parse_config_file(config_text);
    if (parsed.error != "") {
        ui.error(parsed.error);
        return root.installer.InstallSummary { disk: "", exit_code: 130 };
    }
    let problem = root.installer.check_config(shell, files, secrets, parsed.config, asset_dir);
    if (problem != "") {
        ui.error(problem);
        return root.installer.InstallSummary { disk: "", exit_code: 130 };
    }
    root.installer.install(shell, files, ui, parsed.config, asset_dir)
}

// -------------------------------------------------------------------- tests

function silent_ui() -> root.installer.ScriptedUi {
    root.installer.ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [] }
}

function full_run_files() -> root.common.RecordingFiles {
    let files = root.installer.packaged_files();
    files.write("/mnt/etc/locale.gen", "#en_US.UTF-8 UTF-8\n");
    files.write("/mnt/etc/mkinitcpio.conf", root.installer.stock_mkinitcpio_conf());
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
            "blkid -s UUID -o value /dev/sda3": "5f3a-uuid\n",
            "arch-chroot /mnt efibootmgr": root.installer.firmware_listing(),
        },
    }
}

test "a config file answers every question and nothing is asked" {
    let shell = root.common.RecordingShell {
        commands: [],
        fed: [],
        streamed: [],
        exit_codes: {},
        replies: {
            "timedatectl list-timezones": "Europe/Madrid\nUTC\n",
            "arch-chroot /mnt efibootmgr": root.installer.firmware_listing(),
        },
    };
    let ui = silent_ui();

    let summary = run(shell, full_run_files(), root.installer.recording_secrets(), ui,
                      full_config_text(), "/assets");

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
    let ui = silent_ui();

    let summary = run(shell, root.common.recording_files(), root.installer.recording_secrets(), ui,
                      "disk: /dev/sda\nwat: 1\n", "/assets");

    assert.equal(ui.errors, ["Unknown key in config file: wat"]);
    assert.equal(summary.exit_code, 130);
    assert.equal(shell.streamed, [])
}

test "the phases run in order and the installation reports success" {
    let ui = silent_ui();

    let summary = run(full_run_shell(), full_run_files(), root.installer.recording_secrets(), ui,
                      full_config_text(), "/assets");

    assert.equal(summary.exit_code, 0);
    //# the step list and the phases are one list, read in two forms, and the
    //# run ends past the end of it
    assert.equal(ui.outline.length(), 9);
    assert.equal(ui.steps, root.installer.install_phase_names(parse_config_file(full_config_text()).config));
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
    let ui = silent_ui();

    let summary = run(shell, full_run_files(), root.installer.recording_secrets(), ui,
                      full_message_config_text(), "/assets");

    assert.equal(summary.exit_code, 0);
    //# ten with the return message, which is the one phase that is optional
    assert.equal(ui.outline.length(), 10);
    assert.is_true(ui.outline.includes("Return message"));
    assert.equal(ui.steps,
                 root.installer.install_phase_names(parse_config_file(full_message_config_text()).config));
    //# plymouth is installed with the base system, and the theme is its own
    assert.is_true(shell.streamed.join(" ").includes(" plymouth"));
    assert.is_true(shell.commands.includes(
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes"));
    assert.is_true(shell.commands.includes(root.installer.rendered_with_logo()));
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
    let ui = silent_ui();

    let summary = run(shell, full_run_files(), root.installer.recording_secrets(), ui,
                      full_dotfiles_config_text(), "/assets");

    assert.equal(summary.exit_code, 0);
    //# ten with the dotfiles, and it is the last of them
    assert.equal(ui.outline.length(), 10);
    assert.equal(ui.outline.at(9) ?? "", "Dotfiles");
    assert.equal(ui.steps,
                 root.installer.install_phase_names(parse_config_file(full_dotfiles_config_text()).config));
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
    let ui = silent_ui();

    let summary = run(shell, full_run_files(), root.installer.recording_secrets(), ui,
                      full_config_text(), "/assets");

    assert.equal(summary.exit_code, 1);
    assert.equal(ui.errors, ["locale-gen failed with exit code 1."]);
    //# the phases after localization never ran
    assert.is_true(!ui.steps.includes("Creating users and groups"));
    assert.is_true(!shell.commands.includes("arch-chroot /mnt groupadd dotfiles"))
}

test "a file operation that fails stops the installation" {
    let files = full_run_files();
    files.fails_with = "cannot write /mnt/etc/fstab: read-only file system";
    let ui = silent_ui();

    let summary = run(full_run_shell(), files, root.installer.recording_secrets(), ui,
                      full_config_text(), "/assets");

    assert.equal(summary.exit_code, 1);
    assert.equal(ui.errors, ["cannot write /mnt/etc/fstab: read-only file system"]);
    //# it stopped where it stopped: the phases after the one that failed never ran
    assert.is_true(!ui.steps.includes("Installing the bootloader..."))
}
