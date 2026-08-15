// The dotfiles: the shared configuration this machine is installed with, and
// the tool that applies it.
//
// It runs last, and `docs/plans/000-dotfiles-integration.md` says why it can
// only run there: the tool expands over the accounts in the `dotfiles` group
// and their homes, installs the packages a map declares, and copies a `grub/`
// directory from the dotfiles into `/boot` on top of the menu the bootloader
// phase has just written.
//
// What the package is, and whether it holds what its map declares, was settled
// while the form was still being answered. Nothing here asks again: by now the
// package is in the staging directory and has already been judged.

/// Where the shared configuration lives on the installed system.
function dotfiles_directory() -> string {
    "/dotfiles"
}

/// Where the secret store lives on the installed system. The path is the map
/// format's, not this installer's; it is written here because the installation
/// is what first puts anything there.
function secret_store_directory() -> string {
    "/etc/oparch/dotfiles-sync/secrets"
}

/// Where the tool is put in the target so that it can be entered and run.
/// `docs/development/004-acting-on-another-system.md` decides that a tool is
/// entered rather than aimed, and being entered means being installed in what
/// is entered. When the tools ship as packages this goes away.
function dotfiles_sync_in_target() -> string {
    "/usr/local/bin/oparch-dotfiles-sync"
}

/// Git refuses to work in a repository owned by anyone but the user running it,
/// and `/dotfiles` is owned by root by design, so the installed system is told
/// that this one is expected. Written rather than set with `git config`, which
/// would need git in the target before anything has installed it.
function git_system_config_path() -> string {
    "/etc/gitconfig"
}

function git_system_config() -> string {
    "[safe]\n\tdirectory = " + dotfiles_directory() + "\n"
}

/// Leaves `/dotfiles` as `docs/decisions/020-dotfiles.md` requires.
///
/// Two halves, because they answer different questions. The modes are for what
/// the copy just brought, which arrives with whatever modes it was copied from;
/// the default ACL is for everything created afterwards, which nobody will be
/// there to fix.
function open_dotfiles_to_its_group(shell: root.common.Shell,
                                    target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    let directories = root.common.must(
        root.common.run_in(shell, target, "find",
                           [dotfiles_directory(), "-type", "d", "-exec", "chmod", "2775", "{}", "+"]),
        "opening the dotfiles directories to their group");
    if (directories != "") {
        return directories;
    }

    let regular = root.common.must(
        root.common.run_in(shell, target, "find",
                           [dotfiles_directory(), "-type", "f", "-exec", "chmod", "664", "{}", "+"]),
        "opening the dotfiles files to their group");
    if (regular != "") {
        return regular;
    }

    root.common.must(
        root.common.run_in(shell, target, "setfacl", ["-d", "-m", "g::rwx", dotfiles_directory()]),
        "granting the dotfiles group what it creates")
}

/// Puts the secret store where the tool reads it from, with the owner and the
/// modes the map format requires of it.
function install_secret_store(shell: root.common.Shell, files: root.common.Files,
                              target: root.common.Target, staging: string) -> string
        throws baml.errors.InvalidArgument {
    let store = root.common.target_path(target, secret_store_directory());
    files.mkdir(store);

    let copied = root.common.must(
        shell.capture("cp", ["-r", `${staged_secrets_directory(staging)}/.`, store]),
        "copying the secret store");
    if (copied != "") {
        return copied;
    }

    //# the store is root's alone: every directory in it, and every value in it
    let directories = root.common.must(
        root.common.run_in(shell, target, "find",
                           [secret_store_directory(), "-type", "d", "-exec", "chmod", "700", "{}", "+"]),
        "restricting the secret store");
    if (directories != "") {
        return directories;
    }

    root.common.must(
        root.common.run_in(shell, target, "find",
                           [secret_store_directory(), "-type", "f", "-exec", "chmod", "600", "{}", "+"]),
        "restricting the secrets")
}

/// Copies the tool into the target, from wherever the live medium keeps it.
function install_dotfiles_sync(shell: root.common.Shell,
                               target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    let found = shell.capture("which", [dotfiles_sync()]);
    if (!found.ok() || found.stdout.trim() == "") {
        return `${dotfiles_sync()} is not on this live medium.`;
    }
    root.common.must(
        shell.capture("cp", [found.stdout.trim(),
                             root.common.target_path(target, dotfiles_sync_in_target())]),
        "installing the dotfiles tool")
}

//# the shared configuration, and the tool that applies it
function configure_dotfiles(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                            config: InstallConfig, target: root.common.Target,
                            staging: string) -> string
        throws baml.errors.InvalidArgument {
    if (config.dotfiles == null) {
        return "";
    }
    ui.step("Applying the dotfiles...");

    //# the contents, not the directory: `/dotfiles` is a mount point the disk
    //# phase made and the users phase gave its group, and it stays the one it made
    let copied = root.common.must(
        shell.capture("cp", ["-r", `${staged_dotfiles_directory(staging)}/.`,
                             root.common.target_path(target, dotfiles_directory())]),
        "copying the dotfiles");
    if (copied != "") {
        return copied;
    }

    let opened = open_dotfiles_to_its_group(shell, target);
    if (opened != "") {
        return opened;
    }
    files.write(root.common.target_path(target, git_system_config_path()), git_system_config());

    if (config.secret_store != null) {
        let store = install_secret_store(shell, files, target, staging);
        if (store != "") {
            return store;
        }
    }

    let installed = install_dotfiles_sync(shell, target);
    if (installed != "") {
        return installed;
    }

    if let failed: string = files.failure() {
        return failed;
    }

    //# entered, not aimed: inside the chroot the hostname, the group, the homes
    //# and /dotfiles all mean what they say, so the tool is run with no arguments
    root.common.must(root.common.run_in(shell, target, dotfiles_sync(), []),
                     "applying the dotfiles")
}

// -------------------------------------------------------------------- tests

function dotfiles_config() -> InstallConfig {
    let config = empty_config();
    config.hostname = "oparch";
    config.work_contexts = ["ivan"];
    config.dotfiles = source_at("git", "https://example.invalid/dotfiles.git");
    config
}

function dotfiles_shell() -> root.common.RecordingShell {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let _ = shell.replies.set("which oparch-dotfiles-sync", "/usr/local/bin/oparch-dotfiles-sync\n");
    shell
}

test "an installation with no dotfiles package does nothing at all" {
    let shell = dotfiles_shell();
    let ui = silent_ui();

    assert.equal(
        configure_dotfiles(shell, root.common.recording_files(), ui, empty_config(),
                           root.common.chroot_target("/mnt"), "/tmp/oparch"),
        "");

    assert.equal(shell.commands, []);
    assert.equal(ui.steps, [])
}

test "the package is copied in, opened to its group, and the tool is entered" {
    let shell = dotfiles_shell();
    let files = root.common.recording_files();

    assert.equal(
        configure_dotfiles(shell, files, silent_ui(), dotfiles_config(),
                           root.common.chroot_target("/mnt"), "/tmp/oparch"),
        "");

    assert.equal(shell.commands, [
        "cp -r /tmp/oparch/dotfiles/. /mnt/dotfiles",
        "arch-chroot /mnt find /dotfiles -type d -exec chmod 2775 {} +",
        "arch-chroot /mnt find /dotfiles -type f -exec chmod 664 {} +",
        "arch-chroot /mnt setfacl -d -m g::rwx /dotfiles",
        "which oparch-dotfiles-sync",
        "cp /usr/local/bin/oparch-dotfiles-sync /mnt/usr/local/bin/oparch-dotfiles-sync",
        "arch-chroot /mnt oparch-dotfiles-sync",
    ]);
    //# git is told the repository it does not own is one it may work in
    assert.equal(files.written.get("/mnt/etc/gitconfig"), "[safe]\n\tdirectory = /dotfiles\n")
}

test "a secret store is installed before the tool runs, and restricted" {
    let shell = dotfiles_shell();
    let config = dotfiles_config();
    config.secret_store = SecretStoreInput {
        archive: source_at("url", "https://example.invalid/store.dfsec"),
        passphrase: "sixteen words from the short list",
    };

    assert.equal(
        configure_dotfiles(shell, root.common.recording_files(), silent_ui(), config,
                           root.common.chroot_target("/mnt"), "/tmp/oparch"),
        "");

    assert.is_true(shell.commands.includes(
        "cp -r /tmp/oparch/secrets/. /mnt/etc/oparch/dotfiles-sync/secrets"));
    assert.is_true(shell.commands.includes(
        "arch-chroot /mnt find /etc/oparch/dotfiles-sync/secrets -type d -exec chmod 700 {} +"));
    assert.is_true(shell.commands.includes(
        "arch-chroot /mnt find /etc/oparch/dotfiles-sync/secrets -type f -exec chmod 600 {} +"));
    //# and all of it is in place before anything reads it: the tool is last
    assert.equal(shell.commands.at(shell.commands.length() - 1) ?? "",
                 "arch-chroot /mnt oparch-dotfiles-sync")
}

test "a copy that fails stops before the tool is entered" {
    let shell = dotfiles_shell();
    let _ = shell.exit_codes.set("cp -r /tmp/oparch/dotfiles/. /mnt/dotfiles", 1);

    assert.equal(
        configure_dotfiles(shell, root.common.recording_files(), silent_ui(), dotfiles_config(),
                           root.common.chroot_target("/mnt"), "/tmp/oparch"),
        "copying the dotfiles failed with exit code 1.");

    assert.is_true(!shell.commands.includes("arch-chroot /mnt oparch-dotfiles-sync"))
}

test "a tool that is not on the medium is reported rather than entered" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };

    assert.equal(
        configure_dotfiles(shell, root.common.recording_files(), silent_ui(), dotfiles_config(),
                           root.common.chroot_target("/mnt"), "/tmp/oparch"),
        "oparch-dotfiles-sync is not on this live medium.");

    assert.is_true(!shell.commands.includes("arch-chroot /mnt oparch-dotfiles-sync"))
}

test "what the tool says when it refuses to apply is what the phase reports" {
    let shell = dotfiles_shell();
    let _ = shell.exit_codes.set("arch-chroot /mnt oparch-dotfiles-sync", 1);

    assert.equal(
        configure_dotfiles(shell, root.common.recording_files(), silent_ui(), dotfiles_config(),
                           root.common.chroot_target("/mnt"), "/tmp/oparch"),
        "applying the dotfiles failed with exit code 1.")
}
