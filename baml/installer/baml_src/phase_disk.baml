// Disk layout: partition table, encrypted container, filesystem, subvolumes
// and the mounts the rest of the installation writes into.
//
// This is the only phase that destroys data, and the first one that runs after
// the summary is confirmed.

class Step {
    program: string,
    args: string[],
}

/// The subvolumes created directly under the filesystem root.
function root_subvolumes() -> string[] {
    ["@", "@recovery", "home", "@snapshots", "@log", "@pkg", "@dotfiles", "@swap"]
}

/// Directories created inside the mounted root before the nested subvolumes
/// are mounted onto them.
function root_directories() -> string[] {
    [
        "/boot", "/home", "/var", "/var/log", "/var/cache", "/var/cache/pacman",
        "/var/cache/pacman/pkg", "/snapshots", "/dotfiles", "/swap",
    ]
}

class SubvolumeMount {
    path: string,
    subvolume: string,
}

/// Subvolume mounted at each path inside the target, in mount order. A list
/// rather than a map, because the order is part of the behaviour.
function nested_mounts() -> SubvolumeMount[] {
    [
        SubvolumeMount { path: "/var/log", subvolume: "@log" },
        SubvolumeMount { path: "/var/cache/pacman/pkg", subvolume: "@pkg" },
        SubvolumeMount { path: "/snapshots", subvolume: "@snapshots" },
        SubvolumeMount { path: "/dotfiles", subvolume: "@dotfiles" },
        SubvolumeMount { path: "/swap", subvolume: "@swap" },
    ]
}

//# partitions, encrypts, formats and mounts the target disk
function prepare_layout(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                        config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    if (config.install_mode == "keep-homes") {
        return "keep-homes install mode is not supported yet.";
    }

    let disk = config.disk;
    let efi_partition = partition_path(disk, 1);
    let root_partition = partition_path(disk, 2);

    //# from here on the disk is being destroyed. Every command is checked:
    //# carrying on after one of these fails would encrypt and format a disk
    //# that was never partitioned.
    ui.step("Preparing the disk...");
    ui.action(`Partitioning ${disk}...`);
    let steps = [
        Step { program: "wipefs", args: ["-af", disk] },
        Step { program: "sgdisk", args: ["--zap-all", disk] },
        Step { program: "sgdisk", args: ["-n", "1:0:+1G", "-t", "1:ef00", "-c", "1:EFI", disk] },
        Step { program: "sgdisk", args: ["-n", "2:0:0", "-t", "2:8300", "-c", "2:CRYPTROOT", disk] },
        Step { program: "partprobe", args: [disk] },
        Step { program: "udevadm", args: ["settle"] },
    ];
    for (let step in steps) {
        let result = shell.capture(step.program, step.args);
        if (result.exit_code != 0) {
            return `${step.program} failed with exit code ${result.exit_code}.`;
        }
    }

    ui.action(`Formatting the EFI partition ${efi_partition}...`);
    let formatted = shell.capture("mkfs.fat", ["-F32", efi_partition]);
    if (formatted.exit_code != 0) {
        return `mkfs.fat failed with exit code ${formatted.exit_code}.`;
    }

    //# the passphrase goes in on standard input, never as an argument
    ui.action(`Creating the LUKS2 container on ${root_partition}...`);
    let created = shell.feed("cryptsetup",
        ["luksFormat", "--type", "luks2", "--batch-mode", "--key-file", "-", root_partition],
        config.shared_secret);
    if (created.exit_code != 0) {
        return `Creating the LUKS2 container failed with exit code ${created.exit_code}.`;
    }
    ui.action(`Opening the LUKS2 container on ${root_partition}...`);
    let opened = shell.feed("cryptsetup",
        ["open", "--key-file", "-", root_partition, "cryptroot"],
        config.shared_secret);
    if (opened.exit_code != 0) {
        return `Opening the LUKS2 container failed with exit code ${opened.exit_code}.`;
    }

    ui.action("Creating the Btrfs filesystem and its subvolumes...");
    let filesystem = shell.capture("mkfs.btrfs", ["-f", "/dev/mapper/cryptroot"]);
    if (filesystem.exit_code != 0) {
        return `mkfs.btrfs failed with exit code ${filesystem.exit_code}.`;
    }

    //# mount the bare filesystem once, only to create the subvolumes. If this
    //# mount fails, everything below would be created on the live system.
    let mounted = root.common.must(
        shell.capture("mount", ["/dev/mapper/cryptroot", target.root]), "mount");
    if (mounted != "") { return mounted; }

    for (let subvolume in root_subvolumes()) {
        let created = root.common.must(shell.capture("btrfs",
            ["subvolume", "create", root.common.target_path(target, `/${subvolume}`)]),
            `creating subvolume ${subvolume}`);
        if (created != "") { return created; }
    }
    for (let user in config.login_users) {
        let created = root.common.must(shell.capture("btrfs",
            ["subvolume", "create", root.common.target_path(target, `/home/@${user}`)]),
            `creating the home subvolume for ${user}`);
        if (created != "") { return created; }
    }
    let unmounted = root.common.must(shell.capture("umount", [target.root]), "umount");
    if (unmounted != "") { return unmounted; }

    //# now mount the layout the installed system will use
    ui.action("Mounting the target layout...");
    let remounted = root.common.must(
        shell.capture("mount", ["-o", "subvol=@", "/dev/mapper/cryptroot", target.root]),
        "mounting the root subvolume");
    if (remounted != "") { return remounted; }

    for (let directory in root_directories()) {
        files.mkdir(root.common.target_path(target, directory));
    }
    for (let nested in nested_mounts()) {
        let attached = root.common.must(shell.capture("mount",
            ["-o", `subvol=${nested.subvolume}`, "/dev/mapper/cryptroot",
             root.common.target_path(target, nested.path)]),
            `mounting ${nested.subvolume}`);
        if (attached != "") { return attached; }
    }

    files.mkdir(root.common.target_path(target, "/snapshots/system/automatic"));
    files.mkdir(root.common.target_path(target, "/snapshots/system/manual"));

    for (let user in config.login_users) {
        files.mkdir(root.common.target_path(target, `/home/${user}`));
        let attached = root.common.must(shell.capture("mount",
            ["-o", `subvol=home/@${user}`, "/dev/mapper/cryptroot",
             root.common.target_path(target, `/home/${user}`)]),
            `mounting the home of ${user}`);
        if (attached != "") { return attached; }
        files.mkdir(root.common.target_path(target, `/snapshots/home/${user}/automatic`));
        files.mkdir(root.common.target_path(target, `/snapshots/home/${user}/manual`));
    }

    let boot = root.common.must(
        shell.capture("mount", [efi_partition, root.common.target_path(target, "/boot")]),
        "mounting the EFI partition");
    if (boot != "") { return boot; }

    //# the initramfs and the bootloader both need this later
    config.root_part_uuid =
        shell.capture("blkid", ["-s", "UUID", "-o", "value", root_partition]).stdout.trim();

    ""
}

// -------------------------------------------------------------------- tests

function layout_config() -> InstallConfig {
    let config = empty_config();
    config.disk = "/dev/sda";
    config.install_mode = "wipe-all";
    config.shared_secret = "correct horse battery staple";
    config.login_users = ["ivan"];
    config
}

test "prepare_layout runs the whole sequence in order" {
    let shell = root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        exit_codes: {},
        replies: { "blkid -s UUID -o value /dev/sda2": "5f3a-uuid\n" },
    };
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();

    assert.equal(prepare_layout(shell, files, ui, config, root.common.mounted_target("/mnt")), "");

    assert.equal(shell.commands, [
        "wipefs -af /dev/sda",
        "sgdisk --zap-all /dev/sda",
        "sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI /dev/sda",
        "sgdisk -n 2:0:0 -t 2:8300 -c 2:CRYPTROOT /dev/sda",
        "partprobe /dev/sda",
        "udevadm settle",
        "mkfs.fat -F32 /dev/sda1",
        "cryptsetup luksFormat --type luks2 --batch-mode --key-file - /dev/sda2",
        "cryptsetup open --key-file - /dev/sda2 cryptroot",
        "mkfs.btrfs -f /dev/mapper/cryptroot",
        "mount /dev/mapper/cryptroot /mnt",
        "btrfs subvolume create /mnt/@",
        "btrfs subvolume create /mnt/@recovery",
        "btrfs subvolume create /mnt/home",
        "btrfs subvolume create /mnt/@snapshots",
        "btrfs subvolume create /mnt/@log",
        "btrfs subvolume create /mnt/@pkg",
        "btrfs subvolume create /mnt/@dotfiles",
        "btrfs subvolume create /mnt/@swap",
        "btrfs subvolume create /mnt/home/@ivan",
        "umount /mnt",
        "mount -o subvol=@ /dev/mapper/cryptroot /mnt",
        "mount -o subvol=@log /dev/mapper/cryptroot /mnt/var/log",
        "mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg",
        "mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/snapshots",
        "mount -o subvol=@dotfiles /dev/mapper/cryptroot /mnt/dotfiles",
        "mount -o subvol=@swap /dev/mapper/cryptroot /mnt/swap",
        "mount -o subvol=home/@ivan /dev/mapper/cryptroot /mnt/home/ivan",
        "mount /dev/sda1 /mnt/boot",
        "blkid -s UUID -o value /dev/sda2",
    ])
}

test "prepare_layout keeps the passphrase off every command line" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();

    let _ = prepare_layout(shell, root.common.recording_files(), ui, config,
                           root.common.mounted_target("/mnt"));

    assert.is_true(!shell.commands.join(" ").includes(config.shared_secret));
    assert.equal(shell.fed, [
        "cryptsetup luksFormat --type luks2 --batch-mode --key-file - /dev/sda2",
        "cryptsetup open --key-file - /dev/sda2 cryptroot",
    ])
}

test "prepare_layout creates the directories the layout needs" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, files, ui, layout_config(), root.common.mounted_target("/mnt"));

    assert.equal(files.directories, [
        "/mnt/boot", "/mnt/home", "/mnt/var", "/mnt/var/log", "/mnt/var/cache",
        "/mnt/var/cache/pacman", "/mnt/var/cache/pacman/pkg", "/mnt/snapshots",
        "/mnt/dotfiles", "/mnt/swap",
        "/mnt/snapshots/system/automatic", "/mnt/snapshots/system/manual",
        "/mnt/home/ivan",
        "/mnt/snapshots/home/ivan/automatic", "/mnt/snapshots/home/ivan/manual",
    ])
}

test "prepare_layout records the root partition UUID for later phases" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "blkid -s UUID -o value /dev/nvme0n1p2": "9c1e-2f77\n" },
    };
    let config = layout_config();
    config.disk = "/dev/nvme0n1";
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, root.common.recording_files(), ui, config,
                           root.common.mounted_target("/mnt"));

    assert.equal(config.root_part_uuid, "9c1e-2f77")
}

test "prepare_layout gives every login user a home subvolume and a mount" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let config = layout_config();
    config.login_users = ["ivan", "work"];
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, root.common.recording_files(), ui, config,
                           root.common.mounted_target("/mnt"));

    assert.is_true(shell.commands.includes("btrfs subvolume create /mnt/home/@ivan"));
    assert.is_true(shell.commands.includes("btrfs subvolume create /mnt/home/@work"));
    assert.is_true(shell.commands.includes("mount -o subvol=home/@work /dev/mapper/cryptroot /mnt/home/work"))
}

test "prepare_layout refuses keep-homes without touching the disk" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let config = layout_config();
    config.install_mode = "keep-homes";
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(prepare_layout(shell, root.common.recording_files(), ui, config,
                                root.common.mounted_target("/mnt")),
                 "keep-homes install mode is not supported yet.");
    assert.equal(shell.commands, [])
}

test "prepare_layout stops at the first destructive command that fails" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("wipefs -af /dev/sda", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.mounted_target("/mnt")),
        "wipefs failed with exit code 1.");
    //# nothing was encrypted or formatted on a disk that was not partitioned
    assert.equal(shell.commands, ["wipefs -af /dev/sda"]);
    assert.equal(shell.fed, [])
}

test "prepare_layout stops when the partition table cannot be written" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("sgdisk -n 2:0:0 -t 2:8300 -c 2:CRYPTROOT /dev/sda", 4);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.mounted_target("/mnt")),
        "sgdisk failed with exit code 4.");
    assert.is_true(!shell.commands.includes("mkfs.btrfs -f /dev/mapper/cryptroot"))
}

test "prepare_layout stops when the container cannot be created" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(
        "cryptsetup luksFormat --type luks2 --batch-mode --key-file - /dev/sda2", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.mounted_target("/mnt")),
        "Creating the LUKS2 container failed with exit code 1.");
    assert.is_true(!shell.commands.includes("mkfs.btrfs -f /dev/mapper/cryptroot"))
}

test "prepare_layout stops when the filesystem cannot be mounted" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("mount /dev/mapper/cryptroot /mnt", 32);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.mounted_target("/mnt")),
        "mount failed with exit code 32.");
    //# without this check the subvolumes would be created on the live system
    assert.is_true(!shell.commands.includes("btrfs subvolume create /mnt/@"))
}
