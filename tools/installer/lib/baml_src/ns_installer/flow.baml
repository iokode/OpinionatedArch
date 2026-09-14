// The installation. Everything here programs against Shell and Ui, so it runs
// identically whichever interface started it, and against test doubles.

/// Where the system being installed is mounted while the installer runs.
function install_root() -> string {
    "/mnt"
}

/// Runs one phase and reports the first thing that went wrong: the phase's own
/// error, or a file operation that failed inside it.
function run_phase(files: root.common.Files, problem: string) -> string {
    if (problem != "") {
        return problem;
    }
    files.failure() ?? ""
}

//# every phase, in order, stopping at the first failure
/// The phases, in the order they run, each in the three forms it is read in.
///
/// The list on the left names the thing without the verb, because the column is
/// narrow and the verb would be the same in every row; the log says
/// what is being done while it is being done, and the state it left once the
/// next phase has begun. A test holds every `ui.step` of a run to this list, so a
/// phase cannot be added without appearing in it.
///
/// The return message is here only when one was asked for, because a list that
/// shows a phase that will not run is a list that lies about how much is left.
function install_phases(config: InstallConfig) -> Phase[] {
    let phases = [
        Phase { to_do: "Disk", doing: "Preparing the disk...",
                done: "Disk prepared." },
        Phase { to_do: "Packages", doing: "Installing packages...",
                done: "Packages installed." },
        Phase { to_do: "Localization", doing: "Configuring localization...",
                done: "Localization configured." },
        Phase { to_do: "System identity", doing: "Configuring system identity...",
                done: "System identity configured." },
        Phase { to_do: "Users and groups", doing: "Creating users and groups...",
                done: "Users and groups created." },
        Phase { to_do: "Network stack", doing: "Enabling the network stack...",
                done: "Network stack enabled." },
        Phase { to_do: "Swap", doing: "Configuring swap...",
                done: "Swap configured." },
    ];
    if (config.return_message != null) {
        phases.push(Phase {
            to_do: "Return message",
            doing: "Rendering the pre-boot return message...",
            done: "Pre-boot return message rendered.",
        });
    }
    phases.push(Phase { to_do: "Initramfs", doing: "Building the initramfs...",
                        done: "Initramfs built." });
    phases.push(Phase { to_do: "Bootloader", doing: "Installing the bootloader...",
                        done: "Bootloader installed." });
    if (config.dotfiles != null) {
        phases.push(Phase {
            to_do: "Dotfiles",
            doing: "Applying the dotfiles...",
            done: "Dotfiles applied.",
        });
    }
    phases
}

/// What each phase says while it runs, which is what `ui.step` is given.
function install_phase_names(config: InstallConfig) -> string[] {
    let names: string[] = [];
    for (let phase in install_phases(config)) {
        names.push(phase.doing);
    }
    names
}

function run_phases(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                    config: InstallConfig, target: root.common.Target, asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
    //# whatever collected the configuration is done with, so the step list
    //# becomes the installation
    ui.outline(install_phases(config));

    let problem = run_phase(files, prepare_layout(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, bootstrap_base_system(shell, files, ui, config, target, asset_dir));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_localization(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_identity(files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_users(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_network(shell, ui, target));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_swap(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    //# before the initramfs is built: the plymouth hook packs the theme, and
    //# the images the renderer put in it, into the image it builds
    let problem = run_phase(files, configure_return_message(shell, files, ui, config, target, asset_dir));
    if (problem != "") { return problem; }

    let problem = run_phase(files, configure_initramfs(shell, files, ui, config, target));
    if (problem != "") { return problem; }

    //# the one whose failure means the machine does not start
    let problem = run_phase(files, configure_bootloader(shell, files, ui, config, target, asset_dir));
    if (problem != "") { return problem; }

    //# last: it expands over the users the fifth phase made, installs what its
    //# map declares with the package manager the second one brought, and lays
    //# a `grub/` directory of its own over the menu just written
    run_phase(files, configure_dotfiles(shell, files, ui, config, target, live_staging_dir()))
}

/// Performs the installation a configuration describes, and says how it ended.
/// What went wrong is reported through `ui` as well as ending the run.
function install(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                 config: InstallConfig, asset_dir: string) -> InstallSummary {
    let problem = run_phases(shell, files, ui, config,
                             root.common.chroot_target(install_root()), asset_dir)
        catch (e) { baml.errors.InvalidArgument => e.message };

    if (problem != "") {
        ui.error(problem);
        return InstallSummary { disk: config.disk, exit_code: 1 };
    }
    InstallSummary { disk: config.disk, exit_code: 0 }
}
