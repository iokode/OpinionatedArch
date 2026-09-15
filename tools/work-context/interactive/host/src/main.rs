//! Terminal host for oparch-work-context-interactive.
//!
//! Which screens are asked, what counts as an answer, and creating or removing
//! a work context are BAML's, and reach this file only through the callbacks
//! passed to `root_refusal` and `run_work_contexts`. What every host does is the
//! crate in tools/utils/host/; what is here is this tool's own: its keys, and
//! the screen a run ends on. See docs/development/001-host-bridge.md.

use std::sync::Arc;

use crossterm::event::{KeyCode, KeyEvent};
use oparch_host::{
    answered, capture_stdio, init_terminal, modal, next_key, restore_stdio, restore_terminal,
    run_captured, run_fed, show_log, spin, ui_choose, ui_text, Asking, Diagnostics, Ran,
    RealStreams, StatusKey, Step, Tool,
};
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph, Wrap};
use ratatui::Frame;

type Host = oparch_host::Host<WorkContexts>;
type App = oparch_host::App<WorkContexts>;

/// What this tool adds to the state every screen is drawn from: what the run
/// ended saying, once it has.
#[derive(Default)]
struct WorkContexts {
    title: String,
    ended: Vec<String>,
    failed: bool,
}

impl Tool for WorkContexts {
    fn status_keys(app: &App, waiting: usize) -> Vec<StatusKey> {
        // Nothing on this bar answers while a full-screen view is up.
        let live = !app.overlay;
        // A screen with one behind it, and not the operation, which asks nothing.
        let at = app.phases_done();
        let can_go_back = at > 0 && at + 1 < app.outline.len();

        vec![
            StatusKey::new("F1", "Back", live && can_go_back),
            StatusKey::new("F6", "Exit", live),
            // The count is the whole of the notice: without it, a log nothing points
            // at is a log nobody opens.
            StatusKey::new("F8", format!("Runtime log: {waiting}"), live && waiting > 0),
        ]
    }

    /// Keys that work on every screen that asks. Returns None when the key was
    /// consumed.
    fn global_key(host: &Host, key: KeyEvent) -> Option<KeyEvent> {
        match key.code {
            KeyCode::F(8) => {
                show_log(host);
                None
            }
            KeyCode::F(6) => {
                if modal(host, "Exit", vec!["Leave without creating or removing a work context?".into()],
                         "Enter yes   Esc no") {
                    restore_terminal();
                    std::process::exit(1);
                }
                None
            }
            _ => Some(key),
        }
    }

    fn save_from(_: &App) -> String {
        "/".into()
    }
}

/// The screen a run ends on: what it said, in green when the operation was
/// carried out and in red when it was not, and how to leave.
fn ended_pane(f: &mut Frame, app: &App, area: Rect) {
    let said = if app.tool.failed {
        Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
    };
    let mut lines: Vec<Line> =
        app.tool.ended.iter().map(|line| Line::from(Span::styled(line.clone(), said))).collect();
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled("Enter or F6 to leave", Style::default().fg(Color::DarkGray))));

    f.render_widget(
        Paragraph::new(lines)
            .wrap(Wrap { trim: false })
            .block(Block::default().borders(Borders::ALL).title(format!(" {} ", app.tool.title))),
        area,
    );
}

/// Holds the screen the run ends on until the operator leaves it.
fn wait_on_the_end(host: &Host, title: String, lines: Vec<String>, failed: bool) {
    {
        let mut app = host.app.lock().unwrap();
        app.busy = None;
        app.finished = true;
        app.tool.title = title;
        app.tool.ended = lines;
        app.tool.failed = failed;
    }
    let _asking = Asking::new(host);
    tokio::task::block_in_place(|| loop {
        host.draw(ended_pane);
        let Some(key) = next_key() else { continue };
        match key.code {
            KeyCode::Enter | KeyCode::F(6) => return,
            KeyCode::F(8) => show_log(host),
            _ => {}
        }
    })
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
    let host =
        Arc::new(Host::new(term, App::new(Vec::new(), WorkContexts::default()), diagnostics.clone()));

    let ended = {
        let (h_outline, h_step, h_action) = (host.clone(), host.clone(), host.clone());
        let (h_error, h_choose, h_text, h_finish) = (host.clone(), host.clone(), host.clone(), host.clone());

        baml_sdk::run_work_contexts_async(
            |program: String, args: Vec<String>| async move { result_of(run_captured(program, args).await) },
            |program: String, args: Vec<String>| async move { result_of(run_captured(program, args).await) },
            |program: String, args: Vec<String>, input: String| async move {
                result_of(run_fed(program, args, input).await)
            },
            move |names: Vec<String>| {
                h_outline.app.lock().unwrap().outline = names
                    .into_iter()
                    .map(|name| Step { to_do: name.clone(), doing: name.clone(), done: name })
                    .collect()
            },
            move |title: String| {
                let mut app = h_step.app.lock().unwrap();
                app.step = title;
                app.busy = None;
            },
            move |message: String| {
                // What the turning thing is labelled with until the run ends.
                let mut app = h_action.app.lock().unwrap();
                let was_idle = app.busy.is_none();
                app.busy = Some(message);
                drop(app);
                if was_idle {
                    spin(h_action.clone());
                }
            },
            move |message: String| h_error.app.lock().unwrap().error = Some(message),
            move |title: String, prompt: String, options: Vec<String>, current: i64| {
                answered(&h_choose, ui_choose(&h_choose, title, prompt, options, current))
            },
            move |title: String, prompt: String, initial: String| {
                answered(&h_text, ui_text(&h_text, title, prompt, initial, false))
            },
            move |title: String, lines: Vec<String>, failed: bool| {
                wait_on_the_end(&h_finish, title, lines, failed)
            },
        )
        .await
    };

    restore_terminal();
    hand_back(&diagnostics, &real_streams);

    match ended {
        Ok(ended) if ended.exit_code == 0 => println!("{}", ended.message),
        Ok(ended) => {
            eprintln!("error: {}", ended.message);
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    }
}
