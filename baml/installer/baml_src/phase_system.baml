// Localization, identity, users and network.
//
// These four phases are independent of each other: they read the config, write
// files into the target and enable what the installed system needs. None of
// them depends on the others having run.

/// Runs a command in the target's own context. The installer writes files into
/// the mounted target directly, but a command like `locale-gen` or `useradd`
/// has to see the target as its root.
function in_target(shell: root.common.Shell, target: root.common.Target,
                   program: string, args: string[]) -> root.common.CommandResult {
    if (target.root == "/") {
        shell.capture(program, args)
    } else {
        shell.capture("arch-chroot", [target.root, program].concat(args))
    }
}

/// The same, for a command that reads a secret from standard input.
function feed_in_target(shell: root.common.Shell, target: root.common.Target,
                        program: string, args: string[], input: string) -> root.common.CommandResult {
    if (target.root == "/") {
        shell.feed(program, args, input)
    } else {
        shell.feed("arch-chroot", [target.root, program].concat(args), input)
    }
}

// --------------------------------------------------------------- 3. locale

//# locale, console keymap, timezone and hardware clock
function configure_localization(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                                config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Configuring localization");

    let locale_gen = root.common.target_path(target, "/etc/locale.gen");
    if (!root.common.replace_in_file(files, locale_gen, "#en_US.UTF-8 UTF-8", "en_US.UTF-8 UTF-8")) {
        return "/etc/locale.gen is missing from the target.";
    }
    let generated = in_target(shell, target, "locale-gen", []);
    if (generated.exit_code != 0) {
        return `locale-gen failed with exit code ${generated.exit_code}.`;
    }

    files.write(root.common.target_path(target, "/etc/locale.conf"), "LANG=en_US.UTF-8" + "\n");
    files.write(root.common.target_path(target, "/etc/vconsole.conf"),
                `KEYMAP=${config.console_keymap}` + "\n");
    files.symlink(root.common.target_path(target, "/etc/localtime"),
                  `/usr/share/zoneinfo/${config.timezone}`);

    root.common.must(in_target(shell, target, "hwclock", ["--systohc", "--utc"]), "hwclock")
}

// ------------------------------------------------------------- 4. identity

//# the name this machine answers to
function configure_identity(files: root.common.Files, ui: Ui,
                            config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Configuring system identity");
    files.write(root.common.target_path(target, "/etc/hostname"), config.hostname + "\n");
    ""
}

// ---------------------------------------------------------------- 5. users

//# groups, accounts, passwords and sudo
function configure_users(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                         config: InstallConfig, target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    ui.step("Creating users and groups");

    for (let group in ["dotfiles", "login-users"]) {
        let added = root.common.must(in_target(shell, target, "groupadd", [group]),
                                     `creating the ${group} group`);
        if (added != "") { return added; }
    }
    //# shared, group-writable and setgid so every login user can write there
    let shared = root.common.must(in_target(shell, target, "install",
        ["-d", "-m", "2775", "-o", "root", "-g", "dotfiles", "/dotfiles"]), "creating /dotfiles");
    if (shared != "") { return shared; }

    for (let user in config.login_users) {
        let created = in_target(shell, target, "useradd",
            ["-M", "-d", `/home/${user}`, "-G", "wheel,dotfiles,login-users",
             "-s", "/bin/bash", user]);
        if (created.exit_code != 0) {
            return `Creating the user ${user} failed with exit code ${created.exit_code}.`;
        }
        let owned = root.common.must(
            in_target(shell, target, "chown", ["-R", `${user}:${user}`, `/home/${user}`]),
            `taking ownership of the home of ${user}`);
        if (owned != "") { return owned; }

        //# the passphrase reaches chpasswd on standard input, never as an
        //# argument. Left unchecked, a failure here leaves an account with no
        //# password on a system whose root is about to be locked.
        let password = root.common.must(
            feed_in_target(shell, target, "chpasswd", [],
                           `${user}:${config.shared_secret}` + "\n"),
            `setting the password of ${user}`);
        if (password != "") { return password; }
    }

    //# root has no password: administration goes through sudo
    let locked = root.common.must(in_target(shell, target, "passwd", ["-l", "root"]),
                                  "locking the root account");
    if (locked != "") { return locked; }

    //# passwordless, per `decisions/001-user-model-and-account-types.md`: the
    //# operator has already unlocked the disk and logged in
    let sudoers = root.common.target_path(target, "/etc/sudoers.d/10-wheel");
    files.write(sudoers, "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" + "\n");
    files.chmod(sudoers, "0440");
    ""
}

// -------------------------------------------------------------- 6. network

//# the services that must already be enabled on first boot
function configure_network(shell: root.common.Shell, ui: Ui,
                           target: root.common.Target) -> string {
    ui.step("Enabling the network stack");
    for (let service in ["NetworkManager.service", "systemd-resolved.service"]) {
        let enabled = in_target(shell, target, "systemctl", ["enable", service]);
        if (enabled.exit_code != 0) {
            return `Enabling ${service} failed with exit code ${enabled.exit_code}.`;
        }
    }
    ""
}

// -------------------------------------------------------------------- tests

function system_config() -> InstallConfig {
    let config = empty_config();
    config.console_keymap = "es";
    config.timezone = "Europe/Madrid";
    config.hostname = "oparch";
    config.shared_secret = "correct horse battery staple";
    config.login_users = ["ivan"];
    config
}

function plain_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], replies: {}, exit_codes: {},
    }
}

function target_with_locale_gen() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/mnt/etc/locale.gen", "#en_US.UTF-8 UTF-8\n#es_ES.UTF-8 UTF-8\n");
    files
}

test "localization uncomments the locale, generates it and sets keymap and time" {
    let shell = plain_shell();
    let files = target_with_locale_gen();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(
        configure_localization(shell, files, ui, system_config(), root.common.mounted_target("/mnt")),
        "");

    assert.equal(files.written.get("/mnt/etc/locale.gen"), "en_US.UTF-8 UTF-8\n#es_ES.UTF-8 UTF-8\n");
    assert.equal(files.written.get("/mnt/etc/locale.conf"), "LANG=en_US.UTF-8\n");
    assert.equal(files.written.get("/mnt/etc/vconsole.conf"), "KEYMAP=es\n");
    assert.equal(files.symlinks.get("/mnt/etc/localtime"), "/usr/share/zoneinfo/Europe/Madrid");
    assert.equal(shell.commands, [
        "arch-chroot /mnt locale-gen",
        "arch-chroot /mnt hwclock --systohc --utc",
    ])
}

test "localization stops when the target has no locale.gen" {
    let shell = plain_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(
        configure_localization(shell, root.common.recording_files(), ui, system_config(),
                               root.common.mounted_target("/mnt")),
        "/etc/locale.gen is missing from the target.");
    assert.equal(shell.commands, [])
}

test "identity writes the hostname" {
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(
        configure_identity(files, ui, system_config(), root.common.mounted_target("/mnt")), "");
    assert.equal(files.written.get("/mnt/etc/hostname"), "oparch\n")
}

test "users creates the groups, the shared dotfiles directory and each account" {
    let shell = plain_shell();
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };
    let config = system_config();
    config.login_users = ["ivan", "work"];

    assert.equal(
        configure_users(shell, files, ui, config, root.common.mounted_target("/mnt")), "");

    assert.equal(shell.commands, [
        "arch-chroot /mnt groupadd dotfiles",
        "arch-chroot /mnt groupadd login-users",
        "arch-chroot /mnt install -d -m 2775 -o root -g dotfiles /dotfiles",
        "arch-chroot /mnt useradd -M -d /home/ivan -G wheel,dotfiles,login-users -s /bin/bash ivan",
        "arch-chroot /mnt chown -R ivan:ivan /home/ivan",
        "arch-chroot /mnt chpasswd",
        "arch-chroot /mnt useradd -M -d /home/work -G wheel,dotfiles,login-users -s /bin/bash work",
        "arch-chroot /mnt chown -R work:work /home/work",
        "arch-chroot /mnt chpasswd",
        "arch-chroot /mnt passwd -l root",
    ])
}

test "users never puts the passphrase on a command line" {
    let shell = plain_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };
    let config = system_config();

    let _ = configure_users(shell, root.common.recording_files(), ui, config,
                            root.common.mounted_target("/mnt"));

    assert.is_true(!shell.commands.join(" ").includes(config.shared_secret));
    assert.equal(shell.fed, ["arch-chroot /mnt chpasswd"])
}

test "users locks root and restricts the sudoers file" {
    let shell = plain_shell();
    let files = root.common.recording_files();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let _ = configure_users(shell, files, ui, system_config(), root.common.mounted_target("/mnt"));

    assert.is_true(shell.commands.includes("arch-chroot /mnt passwd -l root"));
    assert.equal(files.written.get("/mnt/etc/sudoers.d/10-wheel"),
                 "%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n");
    assert.equal(files.modes.get("/mnt/etc/sudoers.d/10-wheel"), "0440")
}

test "users stops when an account cannot be created" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(
        "arch-chroot /mnt useradd -M -d /home/ivan -G wheel,dotfiles,login-users -s /bin/bash ivan", 9);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(
        configure_users(shell, root.common.recording_files(), ui, system_config(),
                        root.common.mounted_target("/mnt")),
        "Creating the user ivan failed with exit code 9.");
    assert.is_true(!shell.commands.includes("arch-chroot /mnt passwd -l root"))
}

test "network enables both services before first boot" {
    let shell = plain_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(configure_network(shell, ui, root.common.mounted_target("/mnt")), "");
    assert.equal(shell.commands, [
        "arch-chroot /mnt systemctl enable NetworkManager.service",
        "arch-chroot /mnt systemctl enable systemd-resolved.service",
    ])
}

test "network reports which service could not be enabled" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("arch-chroot /mnt systemctl enable systemd-resolved.service", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(configure_network(shell, ui, root.common.mounted_target("/mnt")),
                 "Enabling systemd-resolved.service failed with exit code 1.")
}

test "a local target runs commands directly, with no chroot" {
    let shell = plain_shell();
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    let _ = configure_network(shell, ui, root.common.local_target());

    assert.equal(shell.commands, [
        "systemctl enable NetworkManager.service",
        "systemctl enable systemd-resolved.service",
    ])
}

test "users stops when a password cannot be set, before root is locked" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set("arch-chroot /mnt chpasswd", 1);
    let ui = ScriptedUi { answers: [], asked: [], steps: [], errors: [], outline: [], limits: [] };

    assert.equal(
        configure_users(shell, root.common.recording_files(), ui, system_config(),
                        root.common.mounted_target("/mnt")),
        "setting the password of ivan failed with exit code 1.");
    //# leaving root unlocked is the only way back into a system with no user password
    assert.is_true(!shell.commands.includes("arch-chroot /mnt passwd -l root"))
}
