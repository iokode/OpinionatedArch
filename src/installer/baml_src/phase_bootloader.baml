// The bootloader: GRUB on the EFI partition, and the menu the project designed.
//
// The policy is `docs/decisions/008-bootloader.md`. `grub-mkconfig` is
// not used: the menu is an artifact this project owns, kept in `assets/grub/`,
// and it is installed exactly as it is. What differs from one machine to the
// next is written beside it, and the menu reads it.

/// Where GRUB reads its own files from: its modules, the menu, and the values
/// written beside it. It is inside the directory this project owns, because
/// nothing of this system lives outside it.
function grub_directory() -> string {
    `${esp_project_dir()}/grub`
}

function grub_config_path() -> string {
    `${grub_directory()}/grub.cfg`
}

/// Where the values this machine needs are written. The menu's first line
/// reads this, so the menu itself never has to be edited.
function grub_settings_path() -> string {
    `${grub_directory()}/oparch.cfg`
}

/// The label the firmware shows for the entry that starts a live environment
/// over the network, and the file it starts.
function netboot_entry_label() -> string {
    "Arch Netboot"
}

function netboot_loader_path() -> string {
    "\\EFI\\OpinionatedArch\\netbootx64.efi"
}

/// The menu, as the project keeps it.
function grub_asset_path(asset_dir: string) -> string {
    root.common.in_directory(asset_dir, "grub/grub.cfg")
}

/// The microcode image the kernel loads before anything else, or nothing when
/// this machine takes none. `initrd` collapses the empty value away.
function ucode_image(config: InstallConfig) -> string {
    if (config.ucode_package == "none") {
        ""
    } else {
        `/OpinionatedArch/${config.ucode_package}.img`
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

/// The boot order the firmware reports, in the order it reports it.
function parse_boot_order(output: string) -> string[] {
    for (let line in output.lines()) {
        if (line.trim().starts_with("BootOrder:")) {
            return (line.split(":").at(1) ?? "")
                .split(",")
                .map((n) -> { n.trim() })
                .filter((n) -> { n != "" });
        }
    }
    []
}

/// The number of the entry carrying a label, or nothing when the firmware has
/// no such entry. A line reads `Boot0004* OpinionatedArch\tHD(1,GPT,…)`: four
/// digits after `Boot`, a mark saying whether the entry is active, and then
/// the label, which ends where the device path begins.
function boot_entry_number(output: string, label: string) -> string? {
    for (let line in output.lines()) {
        if (line.starts_with("Boot") && line.length() > 9) {
            let named = (line.slice(9, line.length()).split("\t").at(0) ?? "").trim();
            if (named == label) {
                return line.slice(4, 8);
            }
        }
    }
    null
}

/// The order the firmware is left in: the labels given, in the order given,
/// and everything else after them as it was. An entry that is not there is
/// skipped, and entries this installation did not make are kept: the disk may
/// carry another system, and its way of starting is not this project's to drop.
function boot_order_led_by(output: string, labels: string[]) -> string[] {
    let leading: string[] = [];
    for (let label in labels) {
        if let number: string = boot_entry_number(output, label) {
            leading.push(number);
        }
    }
    let order = leading;
    for (let number in parse_boot_order(output)) {
        if (!leading.includes(number)) {
            order.push(number);
        }
    }
    order
}

/// Gives the firmware a way to start the netboot binary without the boot menu,
/// and leaves the bootloader first in the order, as
/// `docs/decisions/007-boot-image-format.md` decides. `efibootmgr` puts what it
/// creates at the head of the order, so the order is written again afterwards.
function register_boot_entries(shell: root.common.Shell, config: InstallConfig,
                               target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    let created = root.common.must(
        root.common.run_in(shell, target, "efibootmgr",
            ["--create", "--disk", config.disk, "--part", "1",
             "--loader", netboot_loader_path(), "--label", netboot_entry_label()]),
        "registering the netboot entry with the firmware");
    if (created != "") {
        return created;
    }

    let listed = root.common.run_in(shell, target, "efibootmgr", []);
    let read = root.common.must(listed, "reading the firmware's boot entries");
    if (read != "") {
        return read;
    }

    let order = boot_order_led_by(listed.stdout, ["OpinionatedArch", netboot_entry_label()]);
    if (order.length() == 0) {
        return "The firmware reports no boot entry to order.";
    }
    root.common.must(
        root.common.run_in(shell, target, "efibootmgr", ["--bootorder", order.join(",")]),
        "leaving the bootloader first in the boot order")
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
                   `--boot-directory=${esp_project_dir()}`,
                   "--bootloader-id=OpinionatedArch"]),
        "grub-install");
    if (installed != "") {
        return installed;
    }

    let registered = register_boot_entries(shell, config, target);
    if (registered != "") {
        return registered;
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
    config.disk = "/dev/sda";
    config.ucode_package = ucode;
    config.root_part_uuid = "9c1e-2f77";
    if (with_message) {
        config.return_message = sample_return_message();
    }
    config
}

/// What the firmware answers once the netboot entry has been created: the
/// bootloader's own entry, another system's, and the one just made, which
/// `efibootmgr` has put at the head of the order.
function firmware_listing() -> string {
    "BootCurrent: 0001\n"
        + "Timeout: 1 seconds\n"
        + "BootOrder: 0002,0001,0000\n"
        + "Boot0000* Windows Boot Manager\tHD(1,GPT,0f0f)/File(\\EFI\\Microsoft\\bootmgfw.efi)\n"
        + "Boot0001* OpinionatedArch\tHD(1,GPT,0f0f)/File(\\EFI\\OpinionatedArch\\grubx64.efi)\n"
        + "Boot0002* Arch Netboot\tHD(1,GPT,0f0f)/File(\\EFI\\OpinionatedArch\\netbootx64.efi)\n"
}

function bootloader_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "arch-chroot /mnt efibootmgr": firmware_listing() },
    }
}

function bootloader_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/assets/grub/grub.cfg", "source ${prefix}/oparch.cfg\nmenuentry 'OpinionatedArch' {}\n");
    files
}

test "the menu is installed exactly as the project keeps it" {
    let shell = bootloader_shell();
    let files = bootloader_files();
    let ui = silent_ui();

    assert.equal(
        configure_bootloader(shell, files, ui, bootloader_config(true, "amd-ucode"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "");

    //# byte for byte: nothing generates it and nothing edits it
    assert.equal(files.written.get("/mnt/boot/OpinionatedArch/grub/grub.cfg"),
                 files.written.get("/assets/grub/grub.cfg"));
    assert.equal(shell.commands, [
        "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot"
            + " --boot-directory=/boot/OpinionatedArch --bootloader-id=OpinionatedArch",
        "arch-chroot /mnt efibootmgr --create --disk /dev/sda --part 1"
            + " --loader \\EFI\\OpinionatedArch\\netbootx64.efi --label Arch Netboot",
        "arch-chroot /mnt efibootmgr",
        "arch-chroot /mnt efibootmgr --bootorder 0001,0002,0000",
    ]);
    assert.equal(ui.steps, ["Installing the bootloader..."])
}

test "what the machine needs is written beside the menu, not into it" {
    let files = bootloader_files();
    let shell = bootloader_shell();

    assert.equal(
        configure_bootloader(shell, files, silent_ui(), bootloader_config(true, "amd-ucode"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(files.written.get("/mnt/boot/OpinionatedArch/grub/oparch.cfg"),
                 "set root_part_uuid=9c1e-2f77\nset ucode_image=/OpinionatedArch/amd-ucode.img\n"
                     + "set linux_extra=\"quiet splash\"\n")
}

test "a machine with no microcode and no message says so in what it writes" {
    let files = bootloader_files();
    let shell = bootloader_shell();

    assert.equal(
        configure_bootloader(shell, files, silent_ui(), bootloader_config(false, "none"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(files.written.get("/mnt/boot/OpinionatedArch/grub/oparch.cfg"),
                 "set root_part_uuid=9c1e-2f77\nset ucode_image=\nset linux_extra=\"quiet\"\n")
}

test "the bootloader is left first, and what this installation did not make is kept" {
    //# the firmware answers with another system's entry, ours, and the netboot
    //# one `efibootmgr` has just put at the head of the order
    assert.equal(boot_order_led_by(firmware_listing(), ["OpinionatedArch", "Arch Netboot"]),
                 ["0001", "0002", "0000"])
}

test "an entry the firmware does not carry is skipped rather than invented" {
    assert.equal(boot_order_led_by(firmware_listing(), ["OpinionatedArch", "Recovery"]),
                 ["0001", "0002", "0000"]);
    assert.equal(boot_entry_number(firmware_listing(), "Recovery"), null)
}

test "the boot order and the entries are read from what the firmware prints" {
    assert.equal(parse_boot_order(firmware_listing()), ["0002", "0001", "0000"]);
    assert.equal(parse_boot_order("Timeout: 1 seconds\n"), []);
    assert.equal(boot_entry_number(firmware_listing(), "Arch Netboot"), "0002")
}

test "the microcode image follows the package that was selected" {
    assert.equal(ucode_image(bootloader_config(false, "intel-ucode")),
                 "/OpinionatedArch/intel-ucode.img");
    assert.equal(ucode_image(bootloader_config(false, "amd-ucode")),
                 "/OpinionatedArch/amd-ucode.img");
    assert.equal(ucode_image(bootloader_config(false, "none")), "")
}

test "a failing grub-install stops before anything is written" {
    let shell = bootloader_shell();
    let _ = shell.exit_codes.set(
        "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot"
            + " --boot-directory=/boot/OpinionatedArch --bootloader-id=OpinionatedArch", 1);
    let files = bootloader_files();

    assert.equal(
        configure_bootloader(shell, files, silent_ui(), bootloader_config(true, "none"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "grub-install failed with exit code 1.");
    assert.is_true(files.written.get("/mnt/boot/OpinionatedArch/grub/grub.cfg") == null)
}

test "assets without the menu are reported, and nothing is written" {
    let shell = bootloader_shell();

    assert.equal(
        configure_bootloader(shell, root.common.recording_files(), silent_ui(),
                             bootloader_config(true, "none"),
                             root.common.chroot_target("/mnt"), "/assets"),
        "The boot menu is not in the assets: /assets/grub/grub.cfg")
}
