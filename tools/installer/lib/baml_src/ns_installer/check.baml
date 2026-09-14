// Whether a configuration describes an installation this machine can perform,
// asked of the live system before anything is written.
//
// A configuration answered screen by screen is held to this as each answer is
// given. One that arrives whole is held to it here, while the disk is still
// intact.

function one_of(value: string, options: string[]) -> bool {
    options.includes(value)
}

/// Everything a configuration cannot decide on its own: that the disk is really
/// a block device, that the timezone exists, that the templates are installed.
/// Returns "" when the config describes something this machine can install.
function check_config(shell: root.common.Shell, files: root.common.Files, secrets: Secrets,
                      config: InstallConfig, asset_dir: string) -> string {
    //# everything the configuration points at is brought here first, before a
    //# single check has been made: this is the last moment at which a medium is
    //# certainly still attached and the target disk certainly still intact
    let brought = bring_every_source(shell, files, config, live_staging_dir());
    if (brought != "") {
        return brought;
    }

    if (config.disk == "") {
        return "disk cannot be empty.";
    }
    if (shell.capture("test", ["-b", config.disk]).exit_code != 0) {
        return `disk must be an existing block device: ${config.disk}`;
    }
    if (!one_of(config.install_mode, ["wipe-all", "keep-homes"])) {
        return "install_mode must be wipe-all or keep-homes.";
    }
    //# the format admits it, the installer does not implement it, and this is
    //# the last place a file-driven run can be stopped before the disk is touched
    if (config.install_mode == "keep-homes") {
        return "keep-homes is not implemented yet.";
    }
    //# a file may ask for an installation this medium cannot perform. Refusing
    //# it here is refusing it while the disk is still intact, which is the one
    //# thing the interactive screen gets for free by not offering the answer
    if (config.offline && !medium_carries_packages(files)) {
        return "offline needs a medium carrying a repository of its own, and this one carries none.";
    }
    if (!one_of(config.ucode_package, ["intel-ucode", "amd-ucode", "none"])) {
        return "ucode_package must be intel-ucode, amd-ucode, or none.";
    }
    if (!one_of(config.gpu_driver, ["nvidia-open", "none"])) {
        return "gpu_driver must be nvidia-open or none.";
    }
    if (config.shared_secret == "") {
        return "shared_secret cannot be empty.";
    }
    if (config.console_keymap == "") {
        return "console_keymap cannot be empty.";
    }

    //# the same list the picker offers, so both entry points accept the same set
    if (!list_timezones(shell).includes(config.timezone)) {
        return `Invalid timezone: ${config.timezone}`;
    }
    if (!validate_hostname(config.hostname)) {
        return "Invalid hostname.";
    }

    //# the map decides what the package has to hold, and only the tool reads
    //# maps; it is asked here, after the hostname and the users it plans for
    //# have been found sound, and before the disk is touched
    if (config.dotfiles != null) {
        let wanted = required_dotfiles_secrets(shell, config, live_staging_dir());
        if (wanted.error != "") {
            return wanted.error;
        }
        //# a store is only opened and judged when the map asks for one, and what
        //# judges it is the same plan, this time held to the files being there.
        //# A file that names no store and needs one is answered by the tool
        //# naming what is missing, rather than by a sentence written here.
        if (wanted.files.length() > 0) {
            if let store: SecretStoreInput = config.secret_store {
                let failure = open_secret_store(shell, files, secrets, store.passphrase,
                                                live_staging_dir());
                if (failure != "") {
                    return failure;
                }
            }
            let refused = check_staged_secrets(shell, config, live_staging_dir());
            if (refused != "") {
                return refused;
            }
        }
    }

    //# the package decides which languages exist and which fields are needed,
    //# and the theme how many languages it has an arrangement for; both are
    //# read here so that a message that cannot be drawn is refused before the
    //# disk is touched
    if let message: ReturnMessageInput = config.return_message {
        //# already brought here, so both are read from where they landed
        let loaded = root.return_message.load_package(
            files, package_directory(asset_dir, message.template));
        if (loaded.error != "") {
            return loaded.error;
        }
        let problem = root.return_message.check_values(loaded.package, message.values,
                                                       "return_message.");
        if (problem != "") {
            return problem;
        }

        let theme = root.return_message.load_theme(
            shell, files, theme_directory(asset_dir, message.theme));
        if (theme.error != "") {
            return theme.error;
        }
        return root.return_message.check_language_count(theme.theme, message.values);
    }
    ""
}

// ----------------------------------------------------------------- fixtures

/// A filesystem holding the project's package and its theme, for tests that
/// validate a configuration against them.
function packaged_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/assets/return-message/manifest.yaml", root.return_message.sample_manifest());
    files.write("/assets/return-message/es.txt", "Hola {{owner_name}}[[, {{phone}}]]");
    files.write("/assets/return-message/ca.txt", "Hola {{owner_name}}");
    files.write("/assets/return-message-theme/manifest.yaml", root.return_message.sample_theme());
    files.write("/assets/pacman-hooks/90-oparch-netboot.hook", "[Trigger]\nTarget = ipxe\n");
    files.write("/assets/pacman-hooks/90-oparch-grub.hook", "[Trigger]\nTarget = grub\n");
    files.write("/assets/pacman-hooks/90-oparch-microcode-amd.hook",
                "[Trigger]\nTarget = boot/amd-ucode.img\n");
    files.write("/assets/pacman-hooks/90-oparch-microcode-intel.hook",
                "[Trigger]\nTarget = boot/intel-ucode.img\n");
    //# what the `pacman` package leaves in the target, which is there by the
    //# time the bootstrap writes this project's repository into it
    files.write("/mnt/etc/pacman.conf", packaged_pacman_conf());
    files
}

/// The same, on a medium that carries a repository of its own: this project's
/// image, where an installation with no network at all is possible. What says
/// so is the pacman configuration written beside that repository when the
/// image was built.
function medium_files() -> root.common.RecordingFiles {
    let files = packaged_files();
    files.write(medium_pacman_conf(), "[options]\n");
    files
}

/// The same, with a third language in the package. What the package offers and
/// what the theme lays out are different limits, and telling them apart needs a
/// package offering a number the theme has no arrangement for.
function three_language_files() -> root.common.RecordingFiles {
    let files = packaged_files();
    files.write("/assets/return-message/manifest.yaml",
                root.return_message.sample_manifest() + "  - code: \"en\"\n    name: \"English\"\n");
    files.write("/assets/return-message/en.txt", "Hello {{owner_name}}");
    files
}
