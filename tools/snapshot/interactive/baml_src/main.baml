// oparch-snapshot-interactive.
//
// Shows the snapshots of the machine through a terminal interface, narrows the
// list, takes a manual snapshot and removes one, through the snapshot library
// that the snapshot command-line tools are built on too. The command is
// documented in `docs/tools/snapshot/interactive/000-command.md`.
//
// A terminal interface is what BAML's standard library does not draw, so this
// tool has a host, as `docs/development/001-host-bridge.md` decides: the host
// draws and runs commands, and everything else is here.

/// ENTRYPOINT. Asked before the terminal is taken over. The tool runs as root,
/// because it snapshots and deletes subvolumes and writes under /snapshots, so
/// a run by any other user is refused before a screen is drawn. An error
/// message, or "" when this is root's run.
function root_refusal(
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
) -> string {
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    root.common.require_root(shell, "oparch-snapshot-interactive")
}

/// ENTRYPOINT. The screens, until the operator leaves them. The only place the
/// host's closures appear. Keep the closure types inline: the `rust` generator
/// drops any function whose callback hides behind a `type` alias.
function run_browser(
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_choose: (string, string, string[], bool) -> Choice throws never,
    on_text: (string, string, string) -> Typed throws never,
    on_confirm: (string, string[]) -> bool throws never,
    on_notice: (string, string[]) -> void throws never,
) -> void {
    let screens = HostScreens {
        on_action: on_action,
        on_error: on_error,
        on_choose: on_choose,
        on_text: on_text,
        on_confirm: on_confirm,
        on_notice: on_notice,
    };
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    browse(shell, root.common.system_files(), root.snapshot.snapshots_lock(), screens)
}
