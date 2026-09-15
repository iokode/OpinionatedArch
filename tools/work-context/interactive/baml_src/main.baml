// oparch-work-context-interactive.
//
// Shows the work contexts of the machine, and creates or removes one through
// the work context library that `oparch-work-context-create` and
// `oparch-work-context-remove` are built on too. The command is documented in
// `docs/tools/work-context/interactive/000-command.md`.
//
// A terminal interface is what BAML's standard library does not draw, so this
// tool has a host, as `docs/development/001-host-bridge.md` decides: the host
// draws and runs commands, and everything else is here.

/// ENTRYPOINT. Asked before the terminal is taken over. The tool runs as root,
/// because creating and removing a work context changes accounts, subvolumes,
/// mounts and the mount table, so a run by any other user is refused before a
/// screen is drawn. An error message, or "" when this is root's run.
function root_refusal(
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
) -> string {
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    root.common.require_root(shell, "oparch-work-context-interactive")
}

/// ENTRYPOINT. The screens, and the operation they collect. The only place the
/// host's closures appear. Keep the closure types inline: the `rust` generator
/// drops any function whose callback hides behind a `type` alias.
function run_work_contexts(
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
    on_outline: (string[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_choose: (string, string, string[], int) -> int? throws never,
    on_text: (string, string, string) -> string? throws never,
    on_finish: (string, string[], bool) -> void throws never,
) -> Ended {
    let screens = HostScreens {
        on_outline: on_outline,
        on_step: on_step,
        on_action: on_action,
        on_error: on_error,
        on_choose: on_choose,
        on_text: on_text,
        on_finish: on_finish,
    };
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    //# only commands arrive from the host: files are touched here, and the
    //# snapshot storage lock is held here, as the snapshot library holds it
    manage_work_contexts(shell, root.common.system_files(), root.snapshot.snapshots_lock(), screens)
}
