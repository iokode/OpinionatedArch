// Swap: compressed swap in RAM, and a swap file on disk. Both are optional and
// independent; asking for neither is a valid answer.

/// The kernel takes swap of higher priority first. The two numbers are what
/// makes `docs/decisions/003-swap.md` true: compressing a page and keeping it
/// in memory is what happens until the compressed pool is full, and the disk
/// is where pages go after that.
function zram_priority() -> int {
    2
}

function swapfile_priority() -> int {
    1
}

/// `zram-generator` reads sizes in megabytes. The compression algorithm is
/// decided in `docs/decisions/003-swap.md`.
function zram_config(gigabytes: int) -> string {
    `[zram0]` + "\n"
        + `zram-size = ${gigabytes * 1024}` + "\n"
        + `compression-algorithm = zstd` + "\n"
        + `swap-priority = ${zram_priority()}` + "\n"
}

/// The mount table entry for the swap file.
function swapfile_fstab_entry() -> string {
    `/swap/swapfile none swap defaults,pri=${swapfile_priority()} 0 0` + "\n"
}

//# compressed swap in RAM and the swap file on disk
function configure_swap(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                        config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    if (config.swap.zram_gb == 0 && config.swap.swapfile_gb == 0) {
        return "";
    }
    ui.step("Configuring swap...");

    //# zram is a systemd generator: the configuration file is all it needs
    if (config.swap.zram_gb > 0) {
    files.write(root.common.target_path(target, "/etc/systemd/zram-generator.conf"),
                    zram_config(config.swap.zram_gb));
    }

    //# the swap file lives on its own subvolume, mounted at /swap
    if (config.swap.swapfile_gb > 0) {
    let created = root.common.run_in(shell, target, "btrfs",
            ["filesystem", "mkswapfile", "--size", `${config.swap.swapfile_gb}G`, "/swap/swapfile"]);
        if (created.exit_code != 0) {
            return root.common.must(created, "Creating the swap file");
        }
        root.common.append_to_file(files, root.common.target_path(target, "/etc/fstab"),
                                   swapfile_fstab_entry());
    }
    ""
}

// -------------------------------------------------------------------- tests

function swap_config(zram: int, swapfile: int) -> InstallConfig {
    let config = empty_config();
    config.swap.zram_gb = zram;
    config.swap.swapfile_gb = swapfile;
    config
}

function target_with_fstab() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/mnt/etc/fstab", "UUID=5f3a / btrfs subvol=@ 0 0\n");
    files
}

test "zram_config asks for the size in megabytes and compresses with zstd" {
    assert.equal(zram_config(8),
                 "[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\nswap-priority = 2\n");
    assert.equal(zram_config(1),
                 "[zram0]\nzram-size = 1024\ncompression-algorithm = zstd\nswap-priority = 2\n")
}

test "the compressed swap in RAM is reached for before the swapfile on disk" {
    //# the kernel takes the higher priority first, and this is the whole of
    //# what makes the order the decision fixes true on a running machine
    assert.is_true(zram_priority() > swapfile_priority());
    assert.is_true(zram_config(8).includes(`swap-priority = ${zram_priority()}`));
    assert.is_true(swapfile_fstab_entry().includes(`pri=${swapfile_priority()}`))
}

test "swap configures both when both are asked for" {
    let shell = plain_shell();
    let files = target_with_fstab();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        configure_swap(shell, files, ui, swap_config(8, 16), root.common.chroot_target("/mnt")), "");

    assert.equal(files.written.get("/mnt/etc/systemd/zram-generator.conf"),
                 "[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\nswap-priority = 2\n");
    assert.equal(shell.commands,
                 ["arch-chroot /mnt btrfs filesystem mkswapfile --size 16G /swap/swapfile"]);
    assert.equal(files.written.get("/mnt/etc/fstab"),
                 "UUID=5f3a / btrfs subvol=@ 0 0\n/swap/swapfile none swap defaults,pri=1 0 0\n")
}

test "swap writes no zram configuration when none is asked for" {
    let shell = plain_shell();
    let files = target_with_fstab();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = configure_swap(shell, files, ui, swap_config(0, 4), root.common.chroot_target("/mnt"));

    assert.is_true(files.written.get("/mnt/etc/systemd/zram-generator.conf") == null);
    assert.equal(shell.commands,
                 ["arch-chroot /mnt btrfs filesystem mkswapfile --size 4G /swap/swapfile"])
}

test "swap creates no swap file when none is asked for" {
    let shell = plain_shell();
    let files = target_with_fstab();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    let _ = configure_swap(shell, files, ui, swap_config(4, 0), root.common.chroot_target("/mnt"));

    assert.equal(shell.commands, []);
    assert.equal(files.written.get("/mnt/etc/fstab"), "UUID=5f3a / btrfs subvol=@ 0 0\n");
    assert.equal(files.written.get("/mnt/etc/systemd/zram-generator.conf"),
                 "[zram0]\nzram-size = 4096\ncompression-algorithm = zstd\nswap-priority = 2\n")
}

test "swap does nothing at all when neither is asked for" {
    let shell = plain_shell();
    let files = target_with_fstab();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        configure_swap(shell, files, ui, swap_config(0, 0), root.common.chroot_target("/mnt")), "");

    assert.equal(shell.commands, []);
    assert.equal(ui.steps, []);
    assert.equal(files.written.get("/mnt/etc/fstab"), "UUID=5f3a / btrfs subvol=@ 0 0\n")
}

test "swap stops when the swap file cannot be created" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(
        "arch-chroot /mnt btrfs filesystem mkswapfile --size 16G /swap/swapfile", 1);
    let files = target_with_fstab();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] };

    assert.equal(
        configure_swap(shell, files, ui, swap_config(0, 16), root.common.chroot_target("/mnt")),
        "Creating the swap file failed with exit code 1.");
    assert.equal(files.written.get("/mnt/etc/fstab"), "UUID=5f3a / btrfs subvol=@ 0 0\n")
}
