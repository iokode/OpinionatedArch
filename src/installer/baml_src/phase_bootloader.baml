// The bootloader: GRUB on the EFI partition, and the menu the project designed.
//
// The policy is `docs/decisions/008-bootloader.md`. `grub-mkconfig` is
// not used: the menu is an artifact this project owns, kept in `assets/grub/`,
// and it is installed exactly as it is. What differs from one machine to the
// next is written beside it, and the menu reads it.

function grub_directory() -> string {
    "/boot/grub"
}

function grub_config_path() -> string {
    "/boot/grub/grub.cfg"
}

/// Where the values this machine needs are written. The menu's first line
/// reads this, so the menu itself never has to be edited.
function grub_settings_path() -> string {
    "/boot/grub/oparch.cfg"
}

/// The menu, as the project keeps it.
function grub_asset_path(asset_dir: string) -> string {
    root.common.in_directory(asset_dir, "grub/grub.cfg")
}

/// The microcode image the kernel loads before anything else, or nothing when
/// this machine takes none. `initrd` collapses the empty value away.
function ucode_image(config: InstallConfig) -> string {
    if (config.ucode_package == "intel-ucode") {
        "/intel-ucode.img"
    } else if (config.ucode_package == "amd-ucode") {
        "/amd-ucode.img"
    } else {
        ""
    }
}

/// What is added to the kernel's command line. `splash` is only meaningful
/// where there is a splash to show, which is where there is a return message.
function linux_extra(config: InstallConfig) -> string {
    if (config.return_message == null) {
        "quiet"
    } else {
        "quiet splash"
    }
}

/// The values the menu reads. Three settings, each of them a fact about this
/// machine that the menu cannot know.
function grub_settings(config: InstallConfig) -> string {
    `set root_part_uuid=${config.root_part_uuid}` + "\n"
        + `set ucode_image=${ucode_image(config)}` + "\n"
        + `set linux_extra="${linux_extra(config)}"` + "\n"
}

/// Installs GRUB and the menu. This is the one path whose failure means the
/// machine does not start, so every step of it is checked.
function configure_bootloader(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                              config: InstallConfig, target: root.common.Target,
                              asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Installing the bootloader...");

    let installed = root.common.must(
        root.common.run_in(shell, target, "grub-install",
                  ["--target=x86_64-efi", "--efi-directory=/boot",
                   "--bootloader-id=OpinionatedArch"]),
        "grub-install");
    if (installed != "") {
        return installed;
    }

    let menu = files.read(grub_asset_path(asset_dir));
    if (menu == null) {
        return `The boot menu is not in the assets: ${grub_asset_path(asset_dir)}`;
    }

    files.mkdir(root.common.target_path(target, grub_directory()));
    files.write(root.common.target_path(target, grub_settings_path()), grub_settings(config));
    files.write(root.common.target_path(target, grub_config_path()), menu);

    if let failed: string = files.failure() {
        return failed;
    }
    ""
}

// -------------------------------------------------------------------- tests

function bootloader_config(with_message: bool, ucode: string) -> InstallConfig {
    let config = empty_config();
    config.ucode_package = ucode;
    config.root_part_uuid = "9c1e-2f77";
    if (with_message) {
        config.return_message = sample_return_message();
    }
    config
}

function bootloader_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/assets/grub/grub.cfg", "source ${prefix}/oparch.cfg\nmenuentry 'OpinionatedArch' {}\n");
    files
}

test "the menu is installed exactly as the project keeps it" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let files = bootloader_files();
    let ui = silent_ui();

    assert.equal(
        configure_bootloader(shell, files, ui, bootloader_config(true, "amd-ucode"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "");

    //# byte for byte: nothing generates it and nothing edits it
    assert.equal(files.written.get("/mnt/boot/grub/grub.cfg"),
                 files.written.get("/assets/grub/grub.cfg"));
    assert.equal(shell.commands, [
        "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot"
            + " --bootloader-id=OpinionatedArch",
    ]);
    assert.equal(ui.steps, ["Installing the bootloader..."])
}

test "what the machine needs is written beside the menu, not into it" {
    let files = bootloader_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };

    assert.equal(
        configure_bootloader(shell, files, silent_ui(), bootloader_config(true, "amd-ucode"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(files.written.get("/mnt/boot/grub/oparch.cfg"),
                 "set root_part_uuid=9c1e-2f77\nset ucode_image=/amd-ucode.img\n"
                     + "set linux_extra=\"quiet splash\"\n")
}

test "a machine with no microcode and no message says so in what it writes" {
    let files = bootloader_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };

    assert.equal(
        configure_bootloader(shell, files, silent_ui(), bootloader_config(false, "none"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(files.written.get("/mnt/boot/grub/oparch.cfg"),
                 "set root_part_uuid=9c1e-2f77\nset ucode_image=\nset linux_extra=\"quiet\"\n")
}

test "the microcode image follows the package that was selected" {
    assert.equal(ucode_image(bootloader_config(false, "intel-ucode")), "/intel-ucode.img");
    assert.equal(ucode_image(bootloader_config(false, "amd-ucode")), "/amd-ucode.img");
    assert.equal(ucode_image(bootloader_config(false, "none")), "")
}

test "a failing grub-install stops before anything is written" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let _ = shell.exit_codes.set(
        "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot"
            + " --bootloader-id=OpinionatedArch", 1);
    let files = bootloader_files();

    assert.equal(
        configure_bootloader(shell, files, silent_ui(), bootloader_config(true, "none"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "grub-install failed with exit code 1.");
    assert.is_true(files.written.get("/mnt/boot/grub/grub.cfg") == null)
}

test "assets without the menu are reported, and nothing is written" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };

    assert.equal(
        configure_bootloader(shell, root.common.recording_files(), silent_ui(),
                             bootloader_config(true, "none"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "The boot menu is not in the assets: /assets/grub/grub.cfg")
}
