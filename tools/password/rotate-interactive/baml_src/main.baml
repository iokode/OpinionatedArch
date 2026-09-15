// oparch-password-rotate-interactive.
//
// Asks the existing shared secret, the new one and its confirmation through a
// terminal interface, and rotates it through the password library that
// `oparch-password-rotate` is built on too. The command is documented in
// `docs/tools/password/rotate-interactive/000-command.md`.
//
// A terminal interface is what BAML's standard library does not draw, so this
// tool has a host, as `docs/development/001-host-bridge.md` decides: the host
// draws and runs commands, and everything else is here.

/// ENTRYPOINT. Asked before the terminal is taken over. The tool runs as root,
/// because what the rotation changes is the header of the encrypted container
/// and the passwords of the accounts, so a run by any other user is refused
/// before a screen is drawn. An error message, or "" when this is root's run.
function root_refusal(
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
) -> string {
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    root.common.require_root(shell, "oparch-password-rotate-interactive")
}

/// ENTRYPOINT. The screens, and the rotation they collect. The only place the
/// host's closures appear. Keep the closure types inline: the `rust` generator
/// drops any function whose callback hides behind a `type` alias.
function run_rotation(
    on_capture: (string, string[]) -> root.common.CommandResult throws never,
    on_stream: (string, string[]) -> root.common.CommandResult throws never,
    on_feed: (string, string[], string) -> root.common.CommandResult throws never,
    on_outline: (string[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_secret: (string, string) -> string? throws never,
    on_finish: (string, string[], bool) -> void throws never,
) -> Ended {
    let screens = HostScreens {
        on_outline: on_outline,
        on_step: on_step,
        on_action: on_action,
        on_error: on_error,
        on_secret: on_secret,
        on_finish: on_finish,
    };
    let shell = root.common.HostShell {
        on_capture: on_capture, on_stream: on_stream, on_feed: on_feed,
    };
    rotate_interactively(shell, screens)
}
