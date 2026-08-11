// Initramfs: the hooks that make the boot path work, and the images built
// from them.
//
// Which hooks, and in what order, is decided in
// `docs/decisions/009-mkinitcpio-hooks-policy.md`. The order is part of that
// policy: nothing here reorders it, and `plymouth` comes before `encrypt`
// because the screen has to be up before the passphrase is asked for.

function mkinitcpio_conf_path() -> string {
    "/etc/mkinitcpio.conf"
}

/// The two lists the policy defines. They differ by one hook: `plymouth`,
/// which is only there when there is a return message for it to show.
function initramfs_hooks(config: InstallConfig) -> string[] {
    if (config.return_message == null) {
        [
            "base", "udev", "autodetect", "microcode", "kms", "keyboard", "keymap",
            "block", "encrypt", "filesystems",
        ]
    } else {
        [
            "base", "udev", "autodetect", "microcode", "kms", "keyboard", "keymap",
            "block", "plymouth", "encrypt", "filesystems",
        ]
    }
}

function hooks_line(config: InstallConfig) -> string {
    `HOOKS=(${initramfs_hooks(config).join(" ")})`
}

/// Rewrites the `HOOKS` line of a configuration, leaving every other line as
/// it was. Answers with nothing when there is no such line: writing one where
/// none was found would leave `mkinitcpio` building with its own defaults and
/// nothing to say so, and an initramfs without `encrypt` is a machine that
/// does not boot.
function set_hooks_line(content: string, line: string) -> string? {
    let out: string[] = [];
    let replaced = false;

    for (let existing in content.lines()) {
        if (!replaced && existing.trim().starts_with("HOOKS=")) {
            out.push(line);
            replaced = true;
        } else {
            out.push(existing);
        }
    }

    if (!replaced) {
        return null;
    }
    out.join("\n") + "\n"
}

/// Sets the hooks and builds every image. This runs after the return message
/// has been rendered and its theme installed, because the `plymouth` hook
/// packs that theme, and the images in it, into what it builds.
function configure_initramfs(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                             config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Building the initramfs...");

    let path = root.common.target_path(target, mkinitcpio_conf_path());
    let content = files.read(path);
    if (content == null) {
        return `${mkinitcpio_conf_path()} is not in the target.`;
    }

    ui.action("Setting the HOOKS line in /etc/mkinitcpio.conf...");
    let rewritten = set_hooks_line(content, hooks_line(config));
    if (rewritten == null) {
        return `${mkinitcpio_conf_path()} has no HOOKS line to set.`;
    }
    files.write(path, rewritten);

    ui.action("Running mkinitcpio for every installed kernel...");
    root.common.must(in_target(shell, target, "mkinitcpio", ["-P"]), "mkinitcpio -P")
}

// -------------------------------------------------------------------- tests

/// What `mkinitcpio` ships, near enough: comments, other settings, and one
/// `HOOKS` line among them.
function stock_mkinitcpio_conf() -> string {
    "# vim:set ft=sh\n"
        + "MODULES=()\n"
        + "BINARIES=()\n"
        + "FILES=()\n"
        + "# HOOKS=(base udev autodetect modconf block filesystems fsck)\n"
        + "HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)\n"
        + "COMPRESSION=\"zstd\"\n"
}

function initramfs_config(with_message: bool) -> InstallConfig {
    let config = empty_config();
    config.console_keymap = "es";
    if (with_message) {
        config.return_message = sample_return_message();
    }
    config
}

test "the hooks are the ones the policy lists, in its order" {
    assert.equal(hooks_line(initramfs_config(false)),
                 "HOOKS=(base udev autodetect microcode kms keyboard keymap block encrypt filesystems)");
    assert.equal(hooks_line(initramfs_config(true)),
                 "HOOKS=(base udev autodetect microcode kms keyboard keymap block plymouth encrypt filesystems)")
}

test "plymouth comes before encrypt, so the screen is up before the passphrase is asked for" {
    let hooks = initramfs_hooks(initramfs_config(true));
    let plymouth = hooks.index_of("plymouth") ?? -1;
    let encrypt = hooks.index_of("encrypt") ?? -1;

    assert.is_true(plymouth >= 0);
    assert.is_true(plymouth < encrypt)
}

test "set_hooks_line replaces the line and leaves everything else alone" {
    let rewritten = set_hooks_line(stock_mkinitcpio_conf(), "HOOKS=(base udev encrypt filesystems)")
        ?? "";

    assert.is_true(rewritten.includes("HOOKS=(base udev encrypt filesystems)\n"));
    assert.is_true(rewritten.includes("MODULES=()\n"));
    assert.is_true(rewritten.includes("COMPRESSION=\"zstd\"\n"));
    //# the commented example is not a HOOKS line and is left where it was
    assert.is_true(rewritten.includes("# HOOKS=(base udev autodetect modconf block filesystems fsck)\n"));
    //# and the one that was there is gone
    assert.is_true(!rewritten.includes("consolefont"))
}

test "a configuration with no HOOKS line is reported rather than added to" {
    assert.equal(set_hooks_line("MODULES=()\nCOMPRESSION=\"zstd\"\n", "HOOKS=(base)"), null)
}

test "the phase sets the hooks and then builds every image" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let files = root.common.recording_files();
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());
    let ui = silent_ui();

    assert.equal(
        configure_initramfs(shell, files, ui, initramfs_config(true),
                            root.common.mounted_target("/mnt")),
        "");

    assert.is_true((files.written.get("/mnt/etc/mkinitcpio.conf") ?? "").includes(
        "HOOKS=(base udev autodetect microcode kms keyboard keymap block plymouth encrypt filesystems)"));
    assert.equal(shell.commands, ["arch-chroot /mnt mkinitcpio -P"]);
    assert.equal(ui.steps, ["Building the initramfs..."])
}

test "without a return message the image is built without plymouth" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let files = root.common.recording_files();
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());

    assert.equal(
        configure_initramfs(shell, files, silent_ui(), initramfs_config(false),
                            root.common.mounted_target("/mnt")),
        "");
    assert.is_true(!(files.written.get("/mnt/etc/mkinitcpio.conf") ?? "").includes("plymouth"))
}

test "a build that fails is reported, and reported as what failed" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let _ = shell.exit_codes.set("arch-chroot /mnt mkinitcpio -P", 1);
    let files = root.common.recording_files();
    files.write("/mnt/etc/mkinitcpio.conf", stock_mkinitcpio_conf());

    assert.equal(
        configure_initramfs(shell, files, silent_ui(), initramfs_config(true),
                            root.common.mounted_target("/mnt")),
        "mkinitcpio -P failed with exit code 1.")
}

test "a target without the configuration is reported before anything is built" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };

    assert.equal(
        configure_initramfs(shell, root.common.recording_files(), silent_ui(),
                            initramfs_config(true), root.common.mounted_target("/mnt")),
        "/etc/mkinitcpio.conf is not in the target.");
    assert.equal(shell.commands, [])
}
