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
    //# the last four are every tool this project ships except the installer,
    //# which runs from a live environment and has no use on a machine that is
    //# installed, and the keyring, which is what lets the rest be updated from
    //# the repository they came from
    let packages = [
        "base", "linux", "linux-headers", "linux-firmware", "mkinitcpio",
        "btrfs-progs", "cryptsetup", "grub", "efibootmgr",
        "sudo", "networkmanager", "ipxe",
        "oparch-assets", "oparch-return-message-render", "oparch-dotfiles-sync",
        "oparch-keyring",
    ];
    if (config.ucode_package != "none") {
        packages.push(config.ucode_package);
    }
    //# the one that is a package. Everything else the kernel drives itself.
    if (config.gpu_driver == "nvidia-open") {
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

/// The directory this project owns on the EFI system partition, where the
/// images the machine starts from live, as `docs/decisions/001-disk-layout.md`
/// lays it out.
function esp_project_dir() -> string {
    "/boot/OpinionatedArch"
}

/// Where an installation puts the hooks it brings. `/etc/pacman.d/hooks` is
/// the administrator's directory; the one under `/usr/share` belongs to
/// packages, and these arrive with an installation rather than with one.
function pacman_hooks_dir() -> string {
    "/etc/pacman.d/hooks"
}

/// The hooks this machine gets: one for the netboot binary, one for GRUB, and
/// the one that matches the microcode package, if any was selected. Each is a
/// file kept in the assets and installed exactly as it is.
function pacman_hooks(config: InstallConfig) -> string[] {
    let hooks = ["90-oparch-netboot.hook", "90-oparch-grub.hook"];
    if (config.ucode_package == "amd-ucode") {
        hooks.push("90-oparch-microcode-amd.hook");
    } else if (config.ucode_package == "intel-ucode") {
        hooks.push("90-oparch-microcode-intel.hook");
    }
    hooks
}

/// The microcode image, at the path its own package installs it to.
function packaged_ucode_image(config: InstallConfig) -> string {
    if (config.ucode_package == "none") {
        ""
    } else {
        `/boot/${config.ucode_package}.img`
    }
}

/// What `pacstrap` is told before it is told what to install.
///
/// An installation without a network is given the medium's own pacman
/// configuration, which names the repository the medium carries and no other:
/// with it there is nothing to synchronise and nothing to reach for. An
/// installation with one is given nothing, which leaves the live system's
/// configuration, where this project's repository comes first, the official
/// ones after it, and the medium's is the last place looked.
///
/// `-c` is what leaves the configuration to say where the package cache is.
/// Without it `pacstrap` names one on its command line, and a command line
/// beats a configuration file: the medium's copies would then not be looked in
/// and every package would be fetched again, including the ones the medium
/// already holds at the very version being installed. It is passed only where
/// the medium says where its cache is, because a configuration that does not
/// would leave the packages going to the live system's own directories, which
/// are memory.
function pacstrap_options(config: InstallConfig, files: root.common.Files,
                          target: root.common.Target) -> string[] {
    let options = ["-K", target.root];
    if (medium_carries_packages(files)) {
        options = ["-c"].concat(options);
    }
    if (config.offline) {
        return ["-C", medium_pacman_conf()].concat(options);
    }
    options
}

//# installs the base system and writes the mount table
function bootstrap_base_system(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                               config: InstallConfig, target: root.common.Target,
                               asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Installing packages...");
    let install = shell.stream("pacstrap",
        pacstrap_options(config, files, target).concat(bootstrap_packages(config)));
    let installed = root.common.must(install, "Installing the base system");
    if (installed != "") {
        return installed;
    }

    //# the mount table has to describe the layout that was just mounted
    let fstab = shell.capture("genfstab", ["-U", target.root]);
    let read = root.common.must(fstab, "Reading the mount table");
    if (read != "") {
        return read;
    }
    files.write(root.common.target_path(target, "/etc/fstab"), fstab.stdout);

    let repository = configure_repository(files, target);
    if (repository != "") {
        return repository;
    }

    let hooks = install_pacman_hooks(files, config, target, asset_dir);
    if (hooks != "") {
        return hooks;
    }

    let moved = move_ucode_image(shell, files, config, target);
    if (moved != "") {
        return moved;
    }

    stage_netboot_binary(shell, files, ui, target)
}

/// This project's repository, as it is written into a pacman configuration.
///
/// The published one and never the medium's: what the medium carries is a copy
/// of one moment, on a filesystem that will not be there once the machine is
/// running, and a system pointed at it would have nothing to update from. The
/// tools an installation leaves behind are updated with everything else, from
/// where they were published.
function target_repository_stanza() -> string {
    `[oparch]\nSigLevel = Required TrustedOnly\nServer = ${package_repository()}\n`
}

/// A pacman configuration with a repository put in front of the ones already
/// in it.
///
/// Order is the whole of what decides which repository serves a name that two
/// of them carry, so it goes ahead of the first repository section rather than
/// at the end of the file, which is where adding to it would put it: below
/// every one that was already there. A commented-out repository is not a
/// section and is left where it was written.
function with_repository_first(conf: string, stanza: string) -> string {
    let out = "";
    let placed = false;
    for (let line in conf.lines()) {
        if (!placed && line.starts_with("[") && line.trim() != "[options]") {
            out = `${out}${stanza}\n`;
            placed = true;
        }
        out = `${out}${line}\n`;
    }
    if (!placed) {
        out = `${out}${stanza}\n`;
    }
    out
}

/// Puts this project's repository into the installed system, above the
/// official ones, so that `pacman -Syu` there updates the tools it was given
/// from the repository they came from. The file it edits is the one the
/// `pacman` package brought with it.
function configure_repository(files: root.common.Files,
                              target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    let path = root.common.target_path(target, "/etc/pacman.conf");
    if let conf: string = files.read(path) {
        files.write(path, with_repository_first(conf, target_repository_stanza()));
        return "";
    }
    `The installed system has no ${path} to add the repository to.`
}

/// Copies the hooks this machine gets into the target, as they are kept.
function install_pacman_hooks(files: root.common.Files, config: InstallConfig,
                              target: root.common.Target, asset_dir: string) -> string {
    files.mkdir(root.common.target_path(target, pacman_hooks_dir()));
    for (let hook in pacman_hooks(config)) {
        let source = root.common.in_directory(asset_dir, `pacman-hooks/${hook}`);
        let content = files.read(source);
        if (content == null) {
            return `The pacman hook is not in the assets: ${source}`;
        }
        files.write(root.common.target_path(target, `${pacman_hooks_dir()}/${hook}`), content);
    }
    ""
}

/// The microcode image `pacstrap` has just installed is moved where the boot
/// menu looks for it. The hook does this on every later update; this is the
/// first one, which no update announced.
function move_ucode_image(shell: root.common.Shell, files: root.common.Files,
                          config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    if (config.ucode_package == "none") {
        return "";
    }
    files.mkdir(root.common.target_path(target, esp_project_dir()));
    root.common.must(shell.capture("mv",
        [root.common.target_path(target, packaged_ucode_image(config)),
         root.common.target_path(target, `${esp_project_dir()}/${config.ucode_package}.img`)]),
        "moving the microcode image into the project's directory")
}

/// The Arch netboot binary is placed on the ESP so the machine can always be
/// booted into a live environment from its own disk. It is taken from the
/// package `pacstrap` has just installed, so the artifact arrives the way every
/// other one does and is vouched for the way every other one is.
function stage_netboot_binary(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                              target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {

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
        "btrfs-progs", "cryptsetup", "grub", "efibootmgr",
        "sudo", "networkmanager", "ipxe",
        "oparch-assets", "oparch-return-message-render", "oparch-dotfiles-sync",
        "oparch-keyring",
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

test "bootstrap_packages adds no driver for the graphics the kernel drives" {
    let config = empty_config();
    config.ucode_package = "none";

    config.gpu_driver = "none";
    assert.is_true(!bootstrap_packages(config).includes("nvidia-open"));

    config.gpu_driver = "none";
    assert.is_true(!bootstrap_packages(config).includes("none"))
}

/// The assets a bootstrap reads, which are the packaged ones: the hooks it
/// installs are kept there beside everything else this project ships.
function bootstrap_files() -> root.common.RecordingFiles {
    packaged_files()
}

/// The configuration the `pacman` package brings with it, which is the file an
/// installation finds in the target and adds this project's repository to.
function packaged_pacman_conf() -> string {
    "[options]\n"
        + "HoldPkg = pacman glibc\n"
        + "\n"
        + "[core]\n"
        + "Include = /etc/pacman.d/mirrorlist\n"
        + "\n"
        + "[extra]\n"
        + "Include = /etc/pacman.d/mirrorlist\n"
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
    let files = bootstrap_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "amd-ucode";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    assert.equal(shell.streamed, [
        "pacstrap -K /mnt base linux linux-headers linux-firmware mkinitcpio"
            + " btrfs-progs cryptsetup grub efibootmgr sudo networkmanager ipxe"
            + " oparch-assets oparch-return-message-render oparch-dotfiles-sync"
            + " oparch-keyring amd-ucode",
    ]);
    assert.equal(files.written.get("/mnt/etc/fstab"), "UUID=5f3a / btrfs subvol=@ 0 0\n");
    assert.is_true(files.directories.includes("/mnt/boot/EFI/OpinionatedArch"));
    assert.is_true(shell.commands.includes(
        "cp /mnt/usr/share/ipxe/x86_64/ipxe-arch.efi"
            + " /mnt/boot/EFI/OpinionatedArch/netbootx64.efi"))
}

test "an installation without a network installs from the medium alone" {
    let shell = bootstrap_shell();
    let files = medium_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "amd-ucode";
    config.gpu_driver = "none";
    config.offline = true;

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    //# the same packages, taken from somewhere else: the medium's own
    //# configuration names its repository and no other, so this run
    //# synchronises nothing and reaches for nothing
    assert.equal(shell.streamed, [
        "pacstrap -C /usr/share/oparch/medium.conf -c -K /mnt"
            + " base linux linux-headers linux-firmware mkinitcpio"
            + " btrfs-progs cryptsetup grub efibootmgr sudo networkmanager ipxe"
            + " oparch-assets oparch-return-message-render oparch-dotfiles-sync"
            + " oparch-keyring amd-ucode",
    ])
}

test "a medium carrying packages is where they are looked for first" {
    let shell = bootstrap_shell();
    let files = medium_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    //# with a network and on this project's medium: `-c` leaves the cache to
    //# the configuration, which names the medium's own copies, so a package
    //# already there at the version being installed is not fetched again
    assert.is_true((shell.streamed.at(0) ?? "").starts_with("pacstrap -c -K /mnt"))
}

test "a medium that carries nothing lets pacstrap name the cache" {
    let shell = bootstrap_shell();
    let files = bootstrap_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    //# the official Arch image says nothing about a cache, and what it would
    //# fall back to is the live system's own directories, which are memory
    assert.is_true((shell.streamed.at(0) ?? "").starts_with("pacstrap -K /mnt"))
}

test "the installed system is left pointed at the published repository" {
    let shell = bootstrap_shell();
    let files = medium_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";
    config.offline = true;

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    let written = files.written.get("/mnt/etc/pacman.conf") ?? "";
    //# the published repository and never the medium's, which will not be
    //# there once the machine is running
    assert.is_true(written.includes("Server = https://packages.oparch.iokode.dev"));
    assert.is_true(!written.includes("oparch-medium"));
    //# and above the official ones, which is the whole of what decides where a
    //# name two of them carry is served from
    let oparch = written.index_of("[oparch]") ?? 0;
    let core = written.index_of("[core]") ?? 0;
    assert.is_true(oparch < core)
}

test "with_repository_first puts one in front of the first repository there is" {
    let conf = "[options]\nHoldPkg = pacman\n\n#[core-testing]\n[core]\nInclude = x\n";
    let placed = with_repository_first(conf, "[oparch]\nServer = https://example.invalid\n");

    //# the options stay at the top, a commented-out repository is not one, and
    //# what was first is now second
    assert.is_true(placed.starts_with("[options]\nHoldPkg = pacman\n"));
    assert.is_true(placed.includes("#[core-testing]\n[oparch]"));
    assert.is_true((placed.index_of("[oparch]") ?? 0) < (placed.index_of("[core]") ?? 0))
}

test "with_repository_first adds one to a configuration that has no repository" {
    let placed = with_repository_first("[options]\nHoldPkg = pacman\n", "[oparch]\n");

    assert.is_true(placed.includes("[oparch]"))
}

test "the netboot binary is taken from the target, never fetched or staged" {
    let shell = bootstrap_shell();
    let files = bootstrap_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

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
    let files = bootstrap_files();
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
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"),
        "copying the netboot binary to the ESP failed with exit code 1.")
}

test "the hooks a machine gets follow the microcode package it took" {
    let config = layout_config();
    config.ucode_package = "amd-ucode";
    assert.equal(pacman_hooks(config),
                 ["90-oparch-netboot.hook", "90-oparch-grub.hook", "90-oparch-microcode-amd.hook"]);

    config.ucode_package = "intel-ucode";
    assert.equal(pacman_hooks(config),
                 ["90-oparch-netboot.hook", "90-oparch-grub.hook", "90-oparch-microcode-intel.hook"]);

    config.ucode_package = "none";
    assert.equal(pacman_hooks(config), ["90-oparch-netboot.hook", "90-oparch-grub.hook"])
}

test "the hooks are installed as they are kept, and the microcode image is moved" {
    let shell = bootstrap_shell();
    let files = bootstrap_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "intel-ucode";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    assert.equal(files.written.get("/mnt/etc/pacman.d/hooks/90-oparch-grub.hook"),
                 files.written.get("/assets/pacman-hooks/90-oparch-grub.hook"));
    assert.equal(files.written.get("/mnt/etc/pacman.d/hooks/90-oparch-microcode-intel.hook"),
                 files.written.get("/assets/pacman-hooks/90-oparch-microcode-intel.hook"));
    //# the hook that belongs to the other package is not on this machine
    assert.is_true(files.written.get("/mnt/etc/pacman.d/hooks/90-oparch-microcode-amd.hook") == null);
    assert.is_true(shell.commands.includes(
        "mv /mnt/boot/intel-ucode.img /mnt/boot/OpinionatedArch/intel-ucode.img"))
}

test "a machine that takes no microcode moves nothing" {
    let shell = bootstrap_shell();
    let files = bootstrap_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();
    config.ucode_package = "none";
    config.gpu_driver = "none";

    assert.equal(
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"), "");

    assert.is_true(!shell.commands.join(" ").includes("mv "))
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
        bootstrap_base_system(shell, files, ui, config, root.common.chroot_target("/mnt"), "/assets"),
        "Installing the base system failed with exit code 1.");
    assert.is_true(files.written.get("/mnt/etc/fstab") == null)
}
