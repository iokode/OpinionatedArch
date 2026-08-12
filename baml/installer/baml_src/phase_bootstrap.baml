// Bootstrap: the base system is installed onto the mounted layout, and the
// files that must exist before the first chroot step are put in place.

/// A return message, for tests that need one present.
function sample_return_message() -> ReturnMessageInput {
    let message = empty_return_message_input();
    message.values.languages = ["es"];
    message
}

/// Where transient installation files are staged in the live system.
function live_staging_dir() -> string {
    "/tmp/oparch"
}

/// Where the `ipxe` package puts the Arch-scripted netboot binary inside the
/// target. Its embedded script is what makes it the Arch one rather than a
/// plain iPXE build, and it is the file `pacstrap` has just installed.
function packaged_netboot_binary() -> string {
    "/usr/share/ipxe/x86_64/ipxe-arch.efi"
}

/// The package set from `docs/tools/oparch-installer/002-inputs-and-bootstrap-baseline.md`,
/// plus the packages the selected hardware and options require.
function bootstrap_packages(config: InstallConfig) -> string[] {
    let packages = [
        "base", "linux", "linux-headers", "linux-firmware", "mkinitcpio",
        "iptables-nft", "btrfs-progs", "cryptsetup", "grub", "efibootmgr",
        "sudo", "networkmanager", "ipxe",
    ];
    if (config.ucode_package != "none") {
        packages.push(config.ucode_package);
    }
    if (config.gpu_driver == "nvidia" || config.gpu_driver == "nvidia-open") {
        packages.push(config.gpu_driver);
    }
    if (config.return_message != null) {
        packages.push("plymouth");
    }
    //# compressed swap in RAM is provided by systemd's zram generator
    if (config.swap.zram_gb > 0) {
        packages.push("zram-generator");
    }
    packages
}

//# installs the base system and writes the mount table
function bootstrap_base_system(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                               config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Installing packages...");
    ui.action(`Installing ${bootstrap_packages(config).length()} packages with pacstrap...`);
    let install = shell.stream("pacstrap", ["-K", target.root].concat(bootstrap_packages(config)));
    let installed = root.common.must(install, "Installing the base system");
    if (installed != "") {
        return installed;
    }

    //# the mount table has to describe the layout that was just mounted
    ui.action("Writing the mount table...");
    let fstab = shell.capture("genfstab", ["-U", target.root]);
    let read = root.common.must(fstab, "Reading the mount table");
    if (read != "") {
        return read;
    }
    files.write(root.common.target_path(target, "/etc/fstab"), fstab.stdout);

    stage_netboot_binary(shell, files, ui, target)
}

/// The Arch netboot binary is placed on the ESP so the machine can always be
/// booted into a live environment from its own disk. It is taken from the
/// package `pacstrap` has just installed, so the artifact arrives the way every
/// other one does and is vouched for the way every other one is.
function stage_netboot_binary(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                              target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    ui.action("Placing the Arch netboot binary on the EFI partition...");

    files.mkdir(root.common.target_path(target, "/boot/EFI"));
    files.mkdir(root.common.target_path(target, "/boot/EFI/OpinionatedArch"));
    root.common.must(shell.capture("cp",
        [root.common.target_path(target, packaged_netboot_binary()),
         root.common.target_path(target, "/boot/EFI/OpinionatedArch/netbootx64.efi")]),
        "copying the netboot binary to the ESP")
}

// -------------------------------------------------------------------- tests

test "bootstrap_packages is the documented baseline when nothing is selected" {
    let config = empty_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    assert.equal(bootstrap_packages(config), [
        "base", "linux", "linux-headers", "linux-firmware", "mkinitcpio",
        "iptables-nft", "btrfs-progs", "cryptsetup", "grub", "efibootmgr",
        "sudo", "networkmanager", "ipxe",
    ])
}

test "bootstrap_packages adds what the selected hardware needs" {
    let config = empty_config();
    config.ucode_package = "amd-ucode";
    config.gpu_driver = "nvidia-open";
    config.return_message = sample_return_message();
    config.swap.zram_gb = 8;

    let packages = bootstrap_packages(config);
    assert.is_true(packages.includes("amd-ucode"));
    assert.is_true(packages.includes("nvidia-open"));
    assert.is_true(packages.includes("plymouth"));
    assert.is_true(packages.includes("zram-generator"))
}

test "bootstrap_packages leaves out the zram generator when no zram is asked for" {
    let config = empty_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";
    config.swap.zram_gb = 0;

    assert.is_true(!bootstrap_packages(config).includes("zram-generator"))
}

test "bootstrap_packages adds no driver for nouveau or none" {
    let config = empty_config();
    config.ucode_package = "none";

    config.gpu_driver = "nouveau";
    assert.is_true(!bootstrap_packages(config).includes("nouveau"));

    config.gpu_driver = "none";
    assert.is_true(!bootstrap_packages(config).includes("none"))
}

function bootstrap_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        exit_codes: {},
        replies: { "genfstab -U /mnt": "UUID=5f3a / btrfs subvol=@ 0 0\n" },
    }
}

test "bootstrap installs, writes fstab and stages the netboot binary" {
    let shell = bootstrap_shell();
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "amd-ucode";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt")), "");

    assert.equal(shell.streamed, [
        "pacstrap -K /mnt base linux linux-headers linux-firmware mkinitcpio iptables-nft"
            + " btrfs-progs cryptsetup grub efibootmgr sudo networkmanager ipxe amd-ucode",
    ]);
    assert.equal(files.written.get("/mnt/etc/fstab"), "UUID=5f3a / btrfs subvol=@ 0 0\n");
    assert.is_true(files.directories.includes("/mnt/boot/EFI/OpinionatedArch"));
    assert.is_true(shell.commands.includes(
        "cp /mnt/usr/share/ipxe/x86_64/ipxe-arch.efi"
            + " /mnt/boot/EFI/OpinionatedArch/netbootx64.efi"))
}

test "the netboot binary is taken from the target, never fetched or staged" {
    let shell = bootstrap_shell();
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt")), "");

    //# one source and one transfer path: nothing reaches the network for it,
    //# and nothing passes through the live environment on its way to the ESP
    let ran = shell.commands.join(" ");
    assert.is_true(!ran.includes("curl"));
    assert.is_true(!ran.includes("http"));
    assert.is_true(!ran.includes(live_staging_dir()));
    assert.is_true(!files.directories.includes(live_staging_dir()))
}

test "a netboot binary that cannot be placed stops the installation" {
    let shell = bootstrap_shell();
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    let copying = `cp /mnt${packaged_netboot_binary()}`
        + " /mnt/boot/EFI/OpinionatedArch/netbootx64.efi";
    let _ = shell.exit_codes.set(copying, 1);

    //# a recovery convenience is still a required step: the run does not go on
    //# without it, as `AGENTS.md` section 5 requires
    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt")),
        "copying the netboot binary to the ESP failed with exit code 1.")
}

test "bootstrap stops and says so when pacstrap fails" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: {}, exit_codes: {},
    };
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = empty_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    //# make the one command that matters fail
    let failing = `pacstrap ${(["-K", "/mnt"].concat(bootstrap_packages(config))).join(" ")}`;
    let _ = shell.exit_codes.set(failing, 1);

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt")),
        "Installing the base system failed with exit code 1.");
    assert.is_true(files.written.get("/mnt/etc/fstab") == null)
}
