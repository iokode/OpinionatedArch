// oparch-installer-interactive.
//
// Asks every installation input through a terminal interface, one screen at a
// time, and then installs through the library `oparch-installer` is built on.
// The command is documented in
// `docs/tools/oparch-installer-interactive/000-command.md`.
//
// A terminal interface is what BAML's standard library does not draw, so this
// tool has a host, as `docs/development/001-host-bridge.md` decides: the host
// draws and runs commands, and everything else is here.

/// The form, and then the installation it describes.
///
/// `screens` and `ui` are one object: the form asks through the first, and the
/// installation reports through the second, which is the port the library
/// defines. They are two parameters because they are two ports.
function install_interactively(shell: root.common.Shell, files: root.common.Files,
                               secrets: root.installer.Secrets, screens: Screens,
                               ui: root.installer.Ui, asset_dir: string) -> root.installer.InstallSummary {
    if let config: root.installer.InstallConfig = collect_config(shell, files, secrets, screens, asset_dir) {
        return root.installer.install(shell, files, ui, config, asset_dir);
    }
    //# nothing behind the first screen means nothing to back out to, so the
    //# form does not end this way; leaving is F6, which the host handles
    root.installer.InstallSummary { disk: "", exit_code: 130 }
}

/// ENTRYPOINT. The only function the host calls for the installation, and the
/// only place its closures appear. Keep the closure types inline: the `rust`
/// generator drops any function whose callback hides behind a `type` alias.
function run_installer(
    asset_dir: string,
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
    on_outline: (root.installer.Phase[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_warn: (string) -> void throws never,
    on_tip: (string[]) -> void throws never,
    on_choose: (string, string, string[], int) -> int? throws never,
    on_choose_many: (string, string, string[], string[], int, int) -> string[]? throws never,
    on_text: (string, string, string, bool) -> string? throws never,
    on_pick_package: (string, string, string) -> string? throws never,
    on_pick_file: (string, string, string) -> string? throws never,
    on_review: (string, SummaryRow[]) -> bool throws never,
) -> root.installer.InstallSummary {
    //# Only commands arrive from the host. Touching files needs neither a
    //# terminal nor output read while it is produced, which is all a host is
    //# for, as `docs/development/001-host-bridge.md` decides — so `baml.fs`
    //# does it here. `system_files()` is built once for the whole run: the
    //# first failure among the operations is asked for once per phase, and it
    //# has to survive until it is asked.
    let screens = HostScreens {
        on_outline: on_outline,
        on_step: on_step,
        on_action: on_action,
        on_error: on_error,
        on_warn: on_warn,
        on_tip: on_tip,
        on_choose: on_choose,
        on_choose_many: on_choose_many,
        on_text: on_text,
        on_pick_package: on_pick_package,
        on_pick_file: on_pick_file,
        on_review: on_review,
    };
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    install_interactively(
        shell,
        root.installer.AnnouncingFiles { inner: root.common.system_files(), ui: screens },
        root.installer.AgeSecrets { shell: shell },
        screens,
        screens,
        asset_dir,
    )
}

test "the form is asked, and the installation it describes follows it" {
    let ui = scripted([
        "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none",
        "0", "0", "ivan", "s", "s", "UTC", "oparch", "no", "no", "start",
    ]);

    let summary = install_interactively(fake_live_shell(), root.common.recording_files(),
                                        root.installer.recording_secrets(), ui, ui, "/assets");

    assert.equal(ui.steps.slice(0, step_names().length()), step_names());
    //# and past the form, the step list is the installation's
    assert.equal(ui.steps.at(step_names().length()) ?? "", "Preparing the disk...");
    assert.equal(summary.disk, "/dev/sda")
}
