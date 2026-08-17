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
    ["@", "@snapshots", "@log", "@pkg", "@dotfiles", "@swap"]
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
    let disk = config.disk;
    let efi_partition = partition_path(disk, 1);
    let recovery_partition = partition_path(disk, 2);
    let root_partition = partition_path(disk, 3);

    //# from here on the disk is being destroyed. Every command is checked:
    //# carrying on after one of these fails would encrypt and format a disk
    //# that was never partitioned.
    ui.step("Preparing the disk...");
    let steps = [
        Step { program: "wipefs", args: ["-af", disk] },
        Step { program: "sgdisk", args: ["--zap-all", disk] },
        Step { program: "sgdisk", args: ["-n", "1:0:+1G", "-t", "1:ef00", "-c", "1:EFI", disk] },
        Step { program: "sgdisk", args: ["-n", "2:0:+4G", "-t", "2:8300", "-c", "2:RECOVERY", disk] },
        Step { program: "sgdisk",
               args: ["-n", "3:0:0", "-t", "3:8300", "-c", "3:OpinionatedArch", disk] },
        Step { program: "partprobe", args: [disk] },
        Step { program: "udevadm", args: ["settle"] },
    ];
    for (let step in steps) {
        let result = shell.capture(step.program, step.args);
        if (result.exit_code != 0) {
            return `${step.program} failed with exit code ${result.exit_code}.`;
        }
    }

    let formatted = shell.capture("mkfs.fat", ["-F32", efi_partition]);
    if (formatted.exit_code != 0) {
        return `mkfs.fat failed with exit code ${formatted.exit_code}.`;
    }

    //# the recovery partition is made and left alone: it is outside the
    //# container, the installed system does not mount it, and what goes inside
    //# it is the recovery system, which is not built here.
    let recovery = shell.capture("mkfs.ext4", ["-F", "-L", "RECOVERY", recovery_partition]);
    if (recovery.exit_code != 0) {
        return `mkfs.ext4 failed with exit code ${recovery.exit_code}.`;
    }

    //# the passphrase goes in on standard input, never as an argument
    let created = shell.feed("cryptsetup",
        ["luksFormat", "--type", "luks2", "--batch-mode", "--key-file", "-", root_partition],
        config.shared_secret);
    if (created.exit_code != 0) {
        return `Creating the LUKS2 container failed with exit code ${created.exit_code}.`;
    }
    let opened = shell.feed("cryptsetup",
        ["open", "--key-file", "-", root_partition, "cryptroot"],
        config.shared_secret);
    if (opened.exit_code != 0) {
        return `Opening the LUKS2 container failed with exit code ${opened.exit_code}.`;
    }

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
    //# `home` only groups the per-context home subvolumes: nothing mounts it and
    //# nothing snapshots it, so a directory of the top-level subvolume is enough.
    files.mkdir(root.common.target_path(target, "/home"));

    for (let context in config.work_contexts) {
        let created = root.common.must(shell.capture("btrfs",
            ["subvolume", "create", root.common.target_path(target, `/home/@${context}`)]),
            `creating the home subvolume for ${context}`);
        if (created != "") { return created; }
    }
    let unmounted = root.common.must(shell.capture("umount", [target.root]), "umount");
    if (unmounted != "") { return unmounted; }

    //# now mount the layout the installed system will use
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

    for (let context in config.work_contexts) {
        files.mkdir(root.common.target_path(target, `/home/${context}`));
        let attached = root.common.must(shell.capture("mount",
            ["-o", `subvol=home/@${context}`, "/dev/mapper/cryptroot",
             root.common.target_path(target, `/home/${context}`)]),
            `mounting the home of ${context}`);
        if (attached != "") { return attached; }
        files.mkdir(root.common.target_path(target, `/snapshots/home/${context}/automatic`));
        files.mkdir(root.common.target_path(target, `/snapshots/home/${context}/manual`));
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
    config.work_contexts = ["ivan"];
    config
}

test "prepare_layout runs the whole sequence in order" {
    let shell = root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        exit_codes: {},
        replies: { "blkid -s UUID -o value /dev/sda3": "5f3a-uuid\n" },
    };
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();

    assert.equal(prepare_layout(shell, files, ui, config, root.common.chroot_target("/mnt")), "");

    assert.equal(shell.commands, [
        "wipefs -af /dev/sda",
        "sgdisk --zap-all /dev/sda",
        "sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI /dev/sda",
        "sgdisk -n 2:0:+4G -t 2:8300 -c 2:RECOVERY /dev/sda",
        "sgdisk -n 3:0:0 -t 3:8300 -c 3:OpinionatedArch /dev/sda",
        "partprobe /dev/sda",
        "udevadm settle",
        "mkfs.fat -F32 /dev/sda1",
        "mkfs.ext4 -F -L RECOVERY /dev/sda2",
        "cryptsetup luksFormat --type luks2 --batch-mode --key-file - /dev/sda3",
        "cryptsetup open --key-file - /dev/sda3 cryptroot",
        "mkfs.btrfs -f /dev/mapper/cryptroot",
        "mount /dev/mapper/cryptroot /mnt",
        "btrfs subvolume create /mnt/@",
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
        "blkid -s UUID -o value /dev/sda3",
    ])
}

test "prepare_layout keeps the passphrase off every command line" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };
    let config = layout_config();

    let _ = prepare_layout(shell, root.common.recording_files(), ui, config,
                           root.common.chroot_target("/mnt"));

    assert.is_true(!shell.commands.join(" ").includes(config.shared_secret));
    assert.equal(shell.fed, [
        "cryptsetup luksFormat --type luks2 --batch-mode --key-file - /dev/sda3",
        "cryptsetup open --key-file - /dev/sda3 cryptroot",
    ])
}

test "prepare_layout creates the directories the layout needs" {
    let files = root.common.recording_files();
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, files, ui, layout_config(), root.common.chroot_target("/mnt"));

    //# `/mnt/home` is created twice, and both are right: first the directory of
    //# the top-level subvolume that groups the per-context homes, and later the
    //# one inside `@` that those homes are mounted onto. The double records a
    //# path once, so the two show up here as the single entry that comes first.
    assert.equal(files.directories, [
        "/mnt/home",
        "/mnt/boot", "/mnt/var", "/mnt/var/log", "/mnt/var/cache",
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
        replies: { "blkid -s UUID -o value /dev/nvme0n1p3": "9c1e-2f77\n" },
    };
    let config = layout_config();
    config.disk = "/dev/nvme0n1";
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, root.common.recording_files(), ui, config,
                           root.common.chroot_target("/mnt"));

    assert.equal(config.root_part_uuid, "9c1e-2f77")
}

test "prepare_layout gives every work context a home subvolume and a mount" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let config = layout_config();
    config.work_contexts = ["ivan", "work"];
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, root.common.recording_files(), ui, config,
                           root.common.chroot_target("/mnt"));

    assert.is_true(shell.commands.includes("btrfs subvolume create /mnt/home/@ivan"));
    assert.is_true(shell.commands.includes("btrfs subvolume create /mnt/home/@work"));
    assert.is_true(shell.commands.includes("mount -o subvol=home/@work /dev/mapper/cryptroot /mnt/home/work"))
}

test "prepare_layout leaves the recovery partition formatted and unmounted" {
    let shell = plain_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                           root.common.chroot_target("/mnt"));

    assert.is_true(shell.commands.includes("mkfs.ext4 -F -L RECOVERY /dev/sda2"));
    //# nothing mounts it, and it is no longer a subvolume of the container
    assert.is_true(!shell.commands.join(" ").includes("/dev/sda2 /mnt"));
    assert.is_true(!shell.commands.join(" ").includes("@recovery"))
}

test "prepare_layout stops at the first destructive command that fails" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("wipefs -af /dev/sda", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.chroot_target("/mnt")),
        "wipefs failed with exit code 1.");
    //# nothing was encrypted or formatted on a disk that was not partitioned
    assert.equal(shell.commands, ["wipefs -af /dev/sda"]);
    assert.equal(shell.fed, [])
}

test "prepare_layout stops when the partition table cannot be written" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("sgdisk -n 3:0:0 -t 3:8300 -c 3:OpinionatedArch /dev/sda", 4);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.chroot_target("/mnt")),
        "sgdisk failed with exit code 4.");
    assert.is_true(!shell.commands.includes("mkfs.btrfs -f /dev/mapper/cryptroot"))
}

test "prepare_layout stops when the container cannot be created" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(
        "cryptsetup luksFormat --type luks2 --batch-mode --key-file - /dev/sda3", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.chroot_target("/mnt")),
        "Creating the LUKS2 container failed with exit code 1.");
    assert.is_true(!shell.commands.includes("mkfs.btrfs -f /dev/mapper/cryptroot"))
}

test "prepare_layout stops when the filesystem cannot be mounted" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("mount /dev/mapper/cryptroot /mnt", 32);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        prepare_layout(shell, root.common.recording_files(), ui, layout_config(),
                       root.common.chroot_target("/mnt")),
        "mount failed with exit code 32.");
    //# without this check the subvolumes would be created on the live system
    assert.is_true(!shell.commands.includes("btrfs subvolume create /mnt/@"))
}
