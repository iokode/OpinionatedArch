//! Terminal host for oparch-snapshot-interactive.
//!
//! Which screens are shown, what they offer, what counts as an answer, and
//! every operation on the snapshots are BAML's, and reach this file only
//! through the callbacks passed to `root_refusal` and `run_browser`. What every
//! host does is the crate in tools/utils/host/; what is here is this tool's
//! own: its keys, and a frame with no step list. See
//! docs/development/001-host-bridge.md.

use std::sync::Arc;

use crossterm::event::{KeyCode, KeyEvent};
use oparch_host::{
    capture_stdio, init_terminal, modal, restore_stdio, restore_terminal, run_captured, run_fed,
    show_log, spin, ui_choose, ui_text, Diagnostics, Ran, RealStreams, StatusKey, Tool,
};

type Host = oparch_host::Host<Browser>;
type App = oparch_host::App<Browser>;

/// What this tool adds to the state every screen is drawn from.
#[derive(Default)]
struct Browser {
    /// Whether the screen showing has one behind it to go back to.
    can_go_back: bool,
    /// The operator confirmed leaving, and the screen showing is to say so.
    leaving: bool,
}

impl Tool for Browser {
    fn status_keys(app: &App, waiting: usize) -> Vec<StatusKey> {
        //# nothing on this bar answers while a full-screen view is up
        let live = !app.overlay;

        vec![
            StatusKey::new("F1", "Back", live && app.tool.can_go_back),
            StatusKey::new("F6", "Exit", live),
            // The count is the whole of the notice: without it, a log nothing points
            // at is a log nobody opens.
            StatusKey::new("F8", format!("Runtime log: {waiting}"), live && waiting > 0),
        ]
    }

    /// Keys that work on every list and field. Returns None when the key was
    /// consumed.
    fn global_key(host: &Host, key: KeyEvent) -> Option<KeyEvent> {
        match key.code {
            KeyCode::F(8) => {
                show_log(host);
                //# the log hands the step list back as it closes, and this tool
                //# has none: its screens are not steps of a form
                host.app.lock().unwrap().full_screen = true;
                None
            }
            KeyCode::F(6) => {
                if !modal(host, "Exit", vec!["Leave oparch-snapshot-interactive?".into()], "Enter yes   Esc no") {
                    return None;
                }
                // Leaving is BAML's to carry out, so the screen showing is
                // closed as going back closes it, and says it was leaving.
                host.app.lock().unwrap().tool.leaving = true;
                Some(KeyEvent::from(KeyCode::Esc))
            }
            _ => Some(key),
        }
    }

    fn save_from(_: &App) -> String {
        "/".into()
    }
}

/// Whether the operator confirmed leaving while the screen that just closed was
/// showing.
fn left(host: &Host) -> bool {
    host.app.lock().unwrap().tool.leaving
}

/// How a command ended, as the port's result BAML reads.
fn result_of(ran: Ran) -> baml_sdk::common::CommandResult {
    baml_sdk::common::CommandResult { exit_code: ran.exit_code, stdout: ran.stdout, stderr: ran.stderr }
}

/// Gives the standard streams back and prints what was captured while they
/// were not the terminal's.
fn hand_back(diagnostics: &Diagnostics, real_streams: &Option<RealStreams>) {
    if let Some(saved) = real_streams {
        restore_stdio(saved);
    }
    for line in diagnostics.lines() {
        eprintln!("{line}");
    }
}

#[tokio::main]
async fn main() {
    // Nothing the runtime says is thrown away: stdout and stderr are captured
    // and shown inside the TUI, which draws to the terminal device instead.
    let (diagnostics, real_streams) = capture_stdio();

    // Before the terminal is taken over, so that a refusal is said plainly.
    let refused = baml_sdk::root_refusal_async(
        |program: String, args: Vec<String>| async move { result_of(run_captured(program, args).await) },
        |program: String, args: Vec<String>| async move { result_of(run_captured(program, args).await) },
        |program: String, args: Vec<String>, input: String| async move {
            result_of(run_fed(program, args, input).await)
        },
    )
    .await;
    let refusal = match refused {
        Ok(refusal) => refusal,
        Err(e) => format!("{e}"),
    };
    if !refusal.is_empty() {
        hand_back(&diagnostics, &real_streams);
        eprintln!("error: {refusal}");
        std::process::exit(1);
    }

    let term = match init_terminal() {
        Ok(term) => term,
        Err(e) => {
            hand_back(&diagnostics, &real_streams);
            eprintln!("cannot take over the terminal: {e}");
            std::process::exit(1);
        }
    };
    let mut app = App::new(Vec::new(), Browser::default());
    app.full_screen = true;
    let host = Arc::new(Host::new(term, app, diagnostics.clone()));

    let ran = {
        let (h_action, h_error, h_choose) = (host.clone(), host.clone(), host.clone());
        let (h_text, h_confirm, h_notice) = (host.clone(), host.clone(), host.clone());

        baml_sdk::run_browser_async(
            |program: String, args: Vec<String>| async move { result_of(run_captured(program, args).await) },
            |program: String, args: Vec<String>| async move { result_of(run_captured(program, args).await) },
            |program: String, args: Vec<String>, input: String| async move {
                result_of(run_fed(program, args, input).await)
            },
            move |message: String| {
                // What the turning thing is labelled with until the next question.
                let mut app = h_action.app.lock().unwrap();
                let was_idle = app.busy.is_none();
                app.busy = Some(message);
                drop(app);
                if was_idle {
                    spin(h_action.clone());
                }
            },
            move |message: String| h_error.app.lock().unwrap().error = Some(message),
            move |title: String, prompt: String, options: Vec<String>, can_go_back: bool| {
                h_choose.app.lock().unwrap().tool.can_go_back = can_go_back;
                let chosen = ui_choose(&h_choose, title, prompt, options, 0);
                baml_sdk::Choice { index: chosen, leave: chosen.is_none() && left(&h_choose) }
            },
            move |title: String, prompt: String, initial: String| {
                h_text.app.lock().unwrap().tool.can_go_back = true;
                let typed = ui_text(&h_text, title, prompt, initial, false);
                let leave = typed.is_none() && left(&h_text);
                baml_sdk::Typed { value: typed, leave }
            },
            move |title: String, lines: Vec<String>| modal(&h_confirm, &title, lines, "Enter yes   Esc no"),
            move |title: String, lines: Vec<String>| {
                modal(&h_notice, &title, lines, "Enter or Esc to close");
            },
        )
        .await
    };

    restore_terminal();
    hand_back(&diagnostics, &real_streams);

    if let Err(e) = ran {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}
