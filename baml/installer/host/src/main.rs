//! Terminal host for the OpinionatedArch installer.
//!
//! This binary owns exactly two things: the terminal, and running processes.
//! Which questions get asked, in what order, what counts as a valid answer,
//! which commands run and what their output means — all of that lives in BAML
//! and reaches this file only through the callbacks passed to `run_installer`.
//! See docs/decisions/015-installer-host-bridge.md.

use std::fs::File;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::execute;
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Flex, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Gauge, List, ListItem, ListState, Paragraph, Wrap};
use ratatui::{Frame, Terminal};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;

/// The TUI draws to the terminal device directly, not to stdout. Sharing
/// stdout with the program's own output is what lets a stray message land in
/// the middle of a frame; keeping them apart removes the possibility.
type Term = Terminal<CrosstermBackend<File>>;

const TITLE: &str = " OpinionatedArch ";
const STEPS_WIDTH: u16 = 26;

/// Verbose levels, as in the previous installer: 0 shows the current step
/// only, 1 adds our own messages, 2 adds the output of every command.
const VERBOSE_MAX: u8 = 2;

#[derive(Default)]
struct App {
    outline: Vec<String>,
    step: String,
    verbose: u8,
    error: Option<String>,
    on_summary: bool,
    installing: bool,
    phase: String,
    package: String,
    current: i64,
    total: i64,
    eta: Option<i64>,
    /// (minimum verbose level that shows it, text)
    log: Vec<(u8, String)>,
}

impl App {
    fn push_log(&mut self, level: u8, line: String) {
        self.log.push((level, line));
        if self.log.len() > 500 {
            self.log.remove(0);
        }
    }

    fn step_index(&self) -> Option<usize> {
        self.outline.iter().position(|s| *s == self.step)
    }
}

struct Host {
    term: Mutex<Term>,
    app: Mutex<App>,
    diagnostics: Diagnostics,
}

impl Host {
    /// Draws the standard chrome and lets the caller fill the content pane.
    fn draw<F: FnOnce(&mut Frame, &App, Rect)>(&self, fill: F) {
        let app = self.app.lock().unwrap();
        let mut term = self.term.lock().unwrap();
        let notes = self.diagnostics.lines();
        let _ = term.draw(|f| {
            let banner = if notes.is_empty() { 0 } else { 1 };
            let rows = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Min(5), Constraint::Length(banner), Constraint::Length(1)])
                .split(f.area());
            let panes = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Length(STEPS_WIDTH), Constraint::Min(20)])
                .split(rows[0]);

            steps_pane(f, &app, panes[0]);
            fill(f, &app, panes[1]);
            if let Some(latest) = notes.last() {
                let extra = if notes.len() > 1 { format!(" (+{} more)", notes.len() - 1) } else { String::new() };
                f.render_widget(
                    Paragraph::new(Line::from(Span::styled(
                        format!(" runtime: {latest}{extra}"),
                        Style::default().fg(Color::Yellow),
                    ))),
                    rows[1],
                );
            }
            status_bar(f, &app, rows[2]);
        });
    }

    fn take_error(&self) -> Option<String> {
        self.app.lock().unwrap().error.take()
    }
}

// ------------------------------------------------------------------- chrome

fn steps_pane(f: &mut Frame, app: &App, area: Rect) {
    let current = app.step_index();
    let items: Vec<ListItem> = app
        .outline
        .iter()
        .enumerate()
        .map(|(i, name)| {
            let (mark, style) = match current {
                Some(c) if i == c => ("▸", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
                Some(c) if i < c => ("✓", Style::default().fg(Color::Green)),
                _ => (" ", Style::default().fg(Color::DarkGray)),
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!(" {mark} "), style),
                Span::styled(name.clone(), style),
            ]))
        })
        .collect();
    f.render_widget(
        List::new(items).block(Block::default().borders(Borders::ALL).title(TITLE)),
        area,
    );
}

fn status_bar(f: &mut Frame, app: &App, area: Rect) {
    let key = Style::default().fg(Color::Black).bg(Color::Cyan);
    let dim = Style::default().fg(Color::DarkGray);
    let label = Style::default().fg(Color::Gray);

    let mut spans = Vec::new();
    let entry = |spans: &mut Vec<Span<'static>>, k: &str, text: String, enabled: bool| {
        spans.push(Span::styled(format!(" {k} "), if enabled { key } else { dim }));
        spans.push(Span::styled(format!("{text} "), if enabled { label } else { dim }));
    };

    entry(&mut spans, "F1", "Back".into(), !app.installing);
    entry(&mut spans, "F2", "Install".into(), app.on_summary);
    entry(&mut spans, "F3", "About".into(), !app.installing);
    entry(&mut spans, "F4", format!("Verbose: {}", app.verbose), true);
    entry(&mut spans, "F6", "Exit".into(), !app.installing);
    entry(&mut spans, "F7", "Shutdown".into(), !app.installing);

    f.render_widget(Paragraph::new(Line::from(spans)), area);
}

/// Content pane: bordered, titled with the step, with the prompt on top.
/// Returns the area left for the widget itself.
fn content_block(f: &mut Frame, area: Rect, title: &str, prompt: &str, error: Option<&str>) -> Rect {
    f.render_widget(
        Block::default().borders(Borders::ALL).title(format!(" {title} ")),
        area,
    );
    let inner = area.inner(ratatui::layout::Margin { horizontal: 2, vertical: 1 });

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(2), Constraint::Min(1), Constraint::Length(1)])
        .split(inner);

    f.render_widget(
        Paragraph::new(prompt.to_string())
            .style(Style::default().fg(Color::Gray))
            .wrap(Wrap { trim: true }),
        rows[0],
    );
    if let Some(message) = error {
        f.render_widget(
            Paragraph::new(Line::from(Span::styled(
                message.to_string(),
                Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
            ))),
            rows[2],
        );
    }
    rows[1]
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let [row] = Layout::vertical([Constraint::Length(height)]).flex(Flex::Center).areas(area);
    let [cell] = Layout::horizontal([Constraint::Length(width)]).flex(Flex::Center).areas(row);
    cell
}

// -------------------------------------------------------------------- modals

fn modal(host: &Host, title: &str, lines: Vec<String>, hints: &str) -> bool {
    loop {
        host.draw(|f, _, _| {
            let area = centered(f.area(), 60, (lines.len() as u16 + 4).min(f.area().height));
            f.render_widget(Clear, area);
            let text: Vec<Line> = lines.iter().map(|l| Line::from(l.clone())).collect();
            f.render_widget(
                Paragraph::new(text)
                    .wrap(Wrap { trim: true })
                    .block(Block::default().borders(Borders::ALL).title(format!(" {title} "))),
                area,
            );
            let footer = Rect { x: area.x + 2, y: area.y + area.height - 1, width: area.width - 4, height: 1 };
            f.render_widget(
                Paragraph::new(Span::styled(hints.to_string(), Style::default().fg(Color::DarkGray))),
                footer,
            );
        });

        let Some(key) = next_key() else { continue };
        match key.code {
            KeyCode::Enter | KeyCode::Char('y') | KeyCode::Char('Y') => return true,
            KeyCode::Esc | KeyCode::Char('n') | KeyCode::Char('N') => return false,
            _ => {}
        }
    }
}

/// Keys that work on every screen. Returns None when the key was consumed.
fn global_key(host: &Host, key: KeyEvent) -> Option<KeyEvent> {
    match key.code {
        KeyCode::F(3) => {
            modal(
                host,
                "About",
                vec![
                    "OpinionatedArch installer".into(),
                    String::new(),
                    "The flow, the validation and the meaning of every".into(),
                    "command's output live in BAML. This program owns".into(),
                    "the terminal and runs the processes.".into(),
                ],
                "Enter or Esc to close",
            );
            None
        }
        KeyCode::F(4) => {
            let mut app = host.app.lock().unwrap();
            app.verbose = (app.verbose + 1) % (VERBOSE_MAX + 1);
            None
        }
        KeyCode::F(6) => {
            if modal(host, "Exit", vec!["Leave the installer?".into()], "Enter yes   Esc no") {
                restore_terminal();
                std::process::exit(0);
            }
            None
        }
        KeyCode::F(7) => {
            if modal(host, "Shutdown", vec!["Power off this machine?".into()], "Enter yes   Esc no") {
                restore_terminal();
                let _ = std::process::Command::new("poweroff").status();
                std::process::exit(0);
            }
            None
        }
        _ => Some(key),
    }
}

fn next_key() -> Option<KeyEvent> {
    if !event::poll(Duration::from_millis(100)).unwrap_or(false) {
        return None;
    }
    match event::read() {
        Ok(Event::Key(key)) if key.kind == KeyEventKind::Press => Some(key),
        _ => None,
    }
}

/// A key from a widget loop, with the global shortcuts already handled.
fn widget_key(host: &Host) -> Option<KeyEvent> {
    global_key(host, next_key()?)
}

fn is_back(key: &KeyEvent) -> bool {
    matches!(key.code, KeyCode::Esc | KeyCode::F(1))
}

// ------------------------------------------------------------------- filter

/// Case-insensitive match on the segment after the last `/`, so typing
/// "madrid" finds "Europe/Madrid" and typing "es" finds the "es" keymap.
fn matches_filter(option: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }
    let tail = option.rsplit('/').next().unwrap_or(option);
    tail.to_lowercase().contains(&needle.to_lowercase())
}

fn filtered(options: &[String], needle: &str) -> Vec<usize> {
    options
        .iter()
        .enumerate()
        .filter(|(_, o)| matches_filter(o, needle))
        .map(|(i, _)| i)
        .collect()
}

// ------------------------------------------------------------------ widgets

fn ui_choose(host: &Host, title: String, prompt: String, options: Vec<String>, current: i64) -> Option<i64> {
    let mut error = host.take_error();
    let mut filter = String::new();
    let mut cursor = current.max(0) as usize;

    tokio::task::block_in_place(|| loop {
        let visible = filtered(&options, &filter);
        cursor = if visible.is_empty() { 0 } else { cursor.min(visible.len() - 1) };

        host.draw(|f, _, area| {
            let body = content_block(f, area, &title, &prompt, error.as_deref());
            let mut state = ListState::default();
            state.select((!visible.is_empty()).then_some(cursor));
            let items: Vec<ListItem> = visible.iter().map(|i| ListItem::new(options[*i].clone())).collect();
            let hint = if filter.is_empty() {
                "↑/↓ move · type to filter · Enter select".to_string()
            } else {
                format!("filter: {filter}")
            };
            f.render_stateful_widget(
                List::new(items)
                    .block(Block::default().borders(Borders::ALL).title(format!(" {hint} ")))
                    .highlight_style(Style::default().fg(Color::Black).bg(Color::Cyan))
                    .highlight_symbol(" ▸ "),
                body,
                &mut state,
            );
        });

        let Some(key) = widget_key(host) else { continue };
        if is_back(&key) {
            return None;
        }
        match key.code {
            KeyCode::Up => cursor = cursor.saturating_sub(1),
            KeyCode::Down => cursor = (cursor + 1).min(visible.len().saturating_sub(1)),
            KeyCode::Enter => {
                if let Some(index) = visible.get(cursor) {
                    return Some(*index as i64);
                }
            }
            KeyCode::Backspace => {
                filter.pop();
                cursor = 0;
                error = None;
            }
            KeyCode::Char(c) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                filter.push(c);
                cursor = 0;
                error = None;
            }
            _ => {}
        }
    })
}

fn ui_choose_many(
    host: &Host,
    title: String,
    prompt: String,
    options: Vec<String>,
    selected: Vec<String>,
    _min: i64,
    max: i64,
) -> Option<Vec<String>> {
    let error = host.take_error();
    let mut picked: Vec<bool> = options.iter().map(|o| selected.contains(o)).collect();
    let mut cursor = 0usize;

    tokio::task::block_in_place(|| loop {
        host.draw(|f, _, area| {
            let body = content_block(f, area, &title, &prompt, error.as_deref());
            let mut state = ListState::default();
            state.select(Some(cursor));
            let items: Vec<ListItem> = options
                .iter()
                .zip(picked.iter())
                .map(|(o, on)| ListItem::new(format!("[{}] {o}", if *on { "x" } else { " " })))
                .collect();
            f.render_stateful_widget(
                List::new(items)
                    .block(Block::default().borders(Borders::ALL).title(" Space toggles · Enter accepts "))
                    .highlight_style(Style::default().fg(Color::Black).bg(Color::Cyan))
                    .highlight_symbol(" ▸ "),
                body,
                &mut state,
            );
        });

        let Some(key) = widget_key(host) else { continue };
        if is_back(&key) {
            return None;
        }
        match key.code {
            KeyCode::Up => cursor = cursor.saturating_sub(1),
            KeyCode::Down => cursor = (cursor + 1).min(options.len().saturating_sub(1)),
            KeyCode::Char(' ') => {
                let count = picked.iter().filter(|p| **p).count() as i64;
                if picked[cursor] || count < max {
                    picked[cursor] = !picked[cursor];
                }
            }
            // BAML re-asks if the count is wrong, so just hand back the picks.
            KeyCode::Enter => {
                return Some(
                    options.iter().zip(picked.iter()).filter(|(_, on)| **on).map(|(o, _)| o.clone()).collect(),
                )
            }
            _ => {}
        }
    })
}

fn ui_text(host: &Host, title: String, prompt: String, initial: String, secret: bool) -> Option<String> {
    let mut error = host.take_error();
    let mut value = if secret { String::new() } else { initial };

    tokio::task::block_in_place(|| loop {
        host.draw(|f, _, area| {
            let body = content_block(f, area, &title, &prompt, error.as_deref());
            // A field, not a wall: one line, at the top of the pane.
            let field = Rect {
                x: body.x,
                y: body.y,
                width: body.width.min(64),
                height: 3,
            };
            let shown = if secret { "•".repeat(value.chars().count()) } else { value.clone() };
            f.render_widget(
                Paragraph::new(Line::from(vec![
                    Span::styled(shown, Style::default().fg(Color::Cyan)),
                    Span::styled("█", Style::default().fg(Color::Cyan)),
                ]))
                .block(Block::default().borders(Borders::ALL).title(" Enter accepts ")),
                field,
            );
        });

        let Some(key) = widget_key(host) else { continue };
        if is_back(&key) {
            return None;
        }
        match key.code {
            KeyCode::Enter => return Some(value.clone()),
            KeyCode::Backspace => {
                value.pop();
                error = None;
            }
            KeyCode::Char(c) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                value.push(c);
                error = None;
            }
            _ => {}
        }
    })
}

fn ui_review(host: &Host, title: String, lines: Vec<String>) -> bool {
    let error = host.take_error();
    host.app.lock().unwrap().on_summary = true;

    let answer = tokio::task::block_in_place(|| loop {
        host.draw(|f, _, area| {
            let body = content_block(
                f,
                area,
                &title,
                "Review what will be done. F2 starts the installation.",
                error.as_deref(),
            );
            let items: Vec<ListItem> = lines.iter().map(|l| ListItem::new(l.clone())).collect();
            f.render_widget(
                List::new(items).block(Block::default().borders(Borders::ALL).title(" Settings ")),
                body,
            );
        });

        let Some(key) = widget_key(host) else { continue };
        if is_back(&key) {
            return false;
        }
        if key.code == KeyCode::F(2) {
            return true;
        }
    });

    host.app.lock().unwrap().on_summary = false;
    answer
}

// ----------------------------------------------------------------- progress

fn progress_pane(f: &mut Frame, app: &App, area: Rect) {
    let body = content_block(f, area, "Installing", &app.phase, None);
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)])
        .split(body);

    let ratio = if app.total > 0 {
        (app.current as f64 / app.total as f64).clamp(0.0, 1.0)
    } else {
        0.0
    };
    let label = if app.total > 0 {
        let eta = app
            .eta
            .map(|ms| format!("  ~{}s left", (ms as f64 / 1000.0).ceil() as i64))
            .unwrap_or_default();
        format!("{}/{}  {}{}", app.current, app.total, app.package, eta)
    } else {
        app.step.clone()
    };
    f.render_widget(
        Gauge::default()
            .block(Block::default().borders(Borders::ALL))
            .gauge_style(Style::default().fg(Color::Cyan))
            .ratio(ratio)
            .label(label),
        rows[0],
    );

    // Verbose 0 shows no output at all; 1 our messages; 2 everything.
    if app.verbose == 0 || rows[1].height < 3 {
        return;
    }
    let visible: Vec<&String> =
        app.log.iter().filter(|(level, _)| *level <= app.verbose).map(|(_, text)| text).collect();
    let height = rows[1].height.saturating_sub(2) as usize;
    let start = visible.len().saturating_sub(height);
    let items: Vec<ListItem> = visible[start..]
        .iter()
        .map(|l| ListItem::new(Line::from(Span::styled((*l).clone(), Style::default().fg(Color::DarkGray)))))
        .collect();
    f.render_widget(
        List::new(items).block(Block::default().borders(Borders::ALL).title(" Output ")),
        rows[1],
    );
}

// --------------------------------------------------------------------- main

/// The value following `name` on the command line, if it is there.
fn arg_value(name: &str) -> Option<String> {
    std::env::args().skip_while(|a| a != name).nth(1)
}

#[tokio::main]
async fn main() {
    let asset_dir = arg_value("--assets").unwrap_or_else(|| "assets".to_string());

    // `--config <file>` answers every question from the file instead of asking.
    // Reading it is the host's job; deciding what it means is BAML's.
    let config_text = match arg_value("--config") {
        Some(path) => match std::fs::read_to_string(&path) {
            Ok(text) => Some(text),
            Err(e) => {
                eprintln!("cannot read {path}: {e}");
                std::process::exit(2);
            }
        },
        None => None,
    };

    // With a config file there is nothing to ask, so there is no reason to
    // take over the terminal: plain lines are what a log or a test can read.
    let summary = match config_text {
        Some(text) => run_unattended(asset_dir, text).await,
        None => run_interactive(asset_dir).await,
    };

    let failed = match &summary {
        Ok(s) if s.exit_code == 130 => {
            println!("Cancelled.");
            true
        }
        Ok(s) if s.exit_code == 0 => {
            println!("Bootstrapped {} successfully.", s.disk);
            false
        }
        Ok(s) if s.disk.is_empty() => {
            eprintln!("Nothing to do: no selectable disks found.");
            true
        }
        Ok(s) => {
            eprintln!("Install failed on {} with exit code {}.", s.disk, s.exit_code);
            true
        }
        Err(e) => {
            eprintln!("Installer error: {e}");
            true
        }
    };
    if failed {
        std::process::exit(1);
    }
}

/// Reads the config from a file and reports as plain lines. No terminal is
/// taken over and nothing is asked; if BAML does try to ask something, that is
/// a bug and the run stops instead of hanging.
async fn run_unattended(
    asset_dir: String,
    config_text: String,
) -> Result<baml_sdk::InstallSummary, baml_bridge::Error<std::convert::Infallible>> {
    let started = Instant::now();
    let file_ops = Arc::new(FileOps::default());
    let host = Arc::new(PlainHost { started });
    let (h_stream, h_step) = (host.clone(), host.clone());

    baml_sdk::run_installer_async(
        asset_dir,
        Some(config_text),
        move |program: String, args: Vec<String>| async move { run_captured(program, args).await },
        move |program: String, args: Vec<String>| {
            let host = h_stream.clone();
            async move { host.run_streamed(program, args).await }
        },
            move |program: String, args: Vec<String>, input: String| async move {
                run_fed(program, args, input).await
            },
            {
                let ops = file_ops.clone();
                move || ops.failure()
            },
            {
                let ops = file_ops.clone();
                move |path: String, content: String| ops.write(path, content)
            },
            {
                let ops = file_ops.clone();
                move |path: String| ops.read(path)
            },
            {
                let ops = file_ops.clone();
                move |path: String| ops.exists(path)
            },
            {
                let ops = file_ops.clone();
                move |path: String| ops.mkdir(path)
            },
            {
                let ops = file_ops.clone();
                move |path: String, points_to: String| ops.symlink(path, points_to)
            },
            {
                let ops = file_ops.clone();
                move |path: String, mode: String| ops.chmod(path, mode)
            },
        move |_names: Vec<String>| {},
        move |title: String| h_step.line(&title),
        move |message: String| eprintln!("error: {message}"),
        move |title: String, _p: String, _o: Vec<String>, _c: i64| unattended_question(&title),
        move |title: String, _p: String, _o: Vec<String>, _s: Vec<String>, _min: i64, _max: i64| {
            unattended_question(&title);
            None
        },
        move |title: String, _p: String, _i: String, _s: bool| {
            unattended_question(&title);
            None
        },
        move |_title: String, _lines: Vec<String>| true,
    )
    .await
}

fn unattended_question(title: &str) -> Option<i64> {
    eprintln!("error: the config file left '{title}' unanswered");
    None
}

/// Plain reporting for the unattended run: one line per event, timestamped
/// from the start so a log shows where the time went.
struct PlainHost {
    started: Instant,
}

impl PlainHost {
    fn line(&self, text: &str) {
        println!("[{:>6}ms] {text}", self.started.elapsed().as_millis());
    }

    async fn run_streamed(&self, program: String, args: Vec<String>) -> baml_sdk::common::CommandResult {
        self.line(&format!("running {program} {}", args.join(" ")));
        let mut child = match Command::new(&program)
            .args(&args)
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                eprintln!("cannot run {program}: {e}");
                return baml_sdk::common::CommandResult { exit_code: 127, stdout: String::new() };
            }
        };

        let mut captured = String::new();
        let mut lines = BufReader::new(child.stdout.take().expect("piped stdout")).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            captured.push_str(&line);
            captured.push('\n');
            // BAML decides what the line means; here it only decides what is
            // worth a line of log.
            if let Ok(event) = baml_sdk::parse_pacman_line_async(line.clone()).await {
                match event {
                    baml_sdk::PacmanEvent::Progress(p) => {
                        self.line(&format!("({}/{}) {} {}", p.current, p.total, p.action, p.package))
                    }
                    baml_sdk::PacmanEvent::PhaseMarker(m) => self.line(&format!(":: {}", m.name)),
                    _ => {}
                }
            }
        }
        let status = child.wait().await;
        baml_sdk::common::CommandResult {
            exit_code: status.ok().and_then(|s| s.code()).unwrap_or(-1) as i64,
            stdout: captured,
        }
    }
}

/// The terminal installer: takes over the screen and asks.
async fn run_interactive(
    asset_dir: String,
) -> Result<baml_sdk::InstallSummary, baml_bridge::Error<std::convert::Infallible>> {
    // Nothing the runtime says is thrown away: stdout and stderr are captured
    // and shown inside the TUI, which draws to the terminal device instead.
    let (diagnostics, real_streams) = capture_stdio();

    let term = match init_terminal() {
        Ok(term) => term,
        Err(e) => {
            if let Some(saved) = &real_streams {
                restore_stdio(saved);
            }
            eprintln!("cannot take over the terminal: {e}");
            std::process::exit(1);
        }
    };
    let host = Arc::new(Host {
        term: Mutex::new(term),
        app: Mutex::new(App::default()),
        diagnostics: diagnostics.clone(),
    });
    let started = Instant::now();
    let file_ops = Arc::new(FileOps::default());

    let summary = {
        let (h_run, h_outline, h_step, h_err) =
            (host.clone(), host.clone(), host.clone(), host.clone());
        let (h_choose, h_many, h_text, h_review) =
            (host.clone(), host.clone(), host.clone(), host.clone());

        baml_sdk::run_installer_async(
            asset_dir,
            None,
            move |program: String, args: Vec<String>| async move { run_captured(program, args).await },
            move |program: String, args: Vec<String>| {
                let host = h_run.clone();
                async move { run_streamed(host, program, args, started).await }
            },
            move |program: String, args: Vec<String>, input: String| async move {
                run_fed(program, args, input).await
            },
            {
                let ops = file_ops.clone();
                move || ops.failure()
            },
            {
                let ops = file_ops.clone();
                move |path: String, content: String| ops.write(path, content)
            },
            {
                let ops = file_ops.clone();
                move |path: String| ops.read(path)
            },
            {
                let ops = file_ops.clone();
                move |path: String| ops.exists(path)
            },
            {
                let ops = file_ops.clone();
                move |path: String| ops.mkdir(path)
            },
            {
                let ops = file_ops.clone();
                move |path: String, points_to: String| ops.symlink(path, points_to)
            },
            {
                let ops = file_ops.clone();
                move |path: String, mode: String| ops.chmod(path, mode)
            },
            move |names: Vec<String>| h_outline.app.lock().unwrap().outline = names,
            move |title: String| {
                let mut app = h_step.app.lock().unwrap();
                app.step = title;
                app.current = 0;
                app.total = 0;
                app.eta = None;
            },
            move |message: String| h_err.app.lock().unwrap().error = Some(message),
            move |title: String, prompt: String, options: Vec<String>, current: i64| {
                ui_choose(&h_choose, title, prompt, options, current)
            },
            move |title: String, prompt: String, options: Vec<String>, selected: Vec<String>, min: i64, max: i64| {
                ui_choose_many(&h_many, title, prompt, options, selected, min, max)
            },
            move |title: String, prompt: String, initial: String, secret: bool| {
                ui_text(&h_text, title, prompt, initial, secret)
            },
            move |title: String, lines: Vec<String>| ui_review(&h_review, title, lines),
        )
        .await
    };

    restore_terminal();
    if let Some(saved) = &real_streams {
        restore_stdio(saved);
    }

    // Everything the program and the runtime printed while the TUI held the
    // screen, now that printing it is safe again.
    for line in diagnostics.lines() {
        eprintln!("{line}");
    }
    summary
}

/// Filesystem operations for BAML, and the first failure among them.
///
/// Failures are remembered rather than returned one by one: BAML asks once per
/// phase, so a failed write can never pass unnoticed without every caller
/// having to check.
#[derive(Default)]
struct FileOps {
    first_failure: Mutex<Option<String>>,
}

impl FileOps {
    fn fail(&self, message: String) {
        let mut failure = self.first_failure.lock().unwrap();
        if failure.is_none() {
            *failure = Some(message);
        }
    }

    fn failure(&self) -> Option<String> {
        self.first_failure.lock().unwrap().clone()
    }

    fn write(&self, path: String, content: String) {
        if let Err(e) = std::fs::write(&path, content) {
            self.fail(format!("cannot write {path}: {e}"));
        }
    }

    fn read(&self, path: String) -> Option<String> {
        std::fs::read_to_string(path).ok()
    }

    fn exists(&self, path: String) -> bool {
        std::path::Path::new(&path).exists()
    }

    fn mkdir(&self, path: String) {
        if let Err(e) = std::fs::create_dir_all(&path) {
            self.fail(format!("cannot create {path}: {e}"));
        }
    }

    fn symlink(&self, path: String, points_to: String) {
        if let Err(e) = std::os::unix::fs::symlink(&points_to, &path) {
            self.fail(format!("cannot link {path} to {points_to}: {e}"));
        }
    }

    fn chmod(&self, path: String, mode: String) {
        match u32::from_str_radix(mode.trim_start_matches('0'), 8) {
            Ok(bits) => {
                use std::os::unix::fs::PermissionsExt;
                if let Err(e) =
                    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(bits))
                {
                    self.fail(format!("cannot set mode {mode} on {path}: {e}"));
                }
            }
            Err(e) => self.fail(format!("{mode} is not an octal mode: {e}")),
        }
    }
}

/// Runs a command that reads from standard input. The input is written and the
/// pipe closed, so a command waiting for end-of-input proceeds.
async fn run_fed(
    program: String,
    args: Vec<String>,
    input: String,
) -> baml_sdk::common::CommandResult {
    let mut child = match Command::new(&program)
        .args(&args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return baml_sdk::common::CommandResult { exit_code: 127, stdout: String::new() },
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes()).await;
        drop(stdin);
    }
    match child.wait_with_output().await {
        Ok(out) => baml_sdk::common::CommandResult {
            exit_code: out.status.code().unwrap_or(-1) as i64,
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        },
        Err(_) => baml_sdk::common::CommandResult { exit_code: -1, stdout: String::new() },
    }
}

/// Runs a command for its output. No parsing, no redrawing: this is the path
/// for commands that merely produce data, and it must stay proportional to
/// running the command itself.
async fn run_captured(program: String, args: Vec<String>) -> baml_sdk::common::CommandResult {
    match Command::new(&program).args(&args).stderr(Stdio::null()).output().await {
        Ok(out) => baml_sdk::common::CommandResult {
            exit_code: out.status.code().unwrap_or(-1) as i64,
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        },
        Err(_) => baml_sdk::common::CommandResult { exit_code: 127, stdout: String::new() },
    }
}

/// Runs a long operation, feeding every line back to BAML for interpretation
/// while it is still running, and returns the full result at the end. The
/// per-line cost here buys live progress, which is why it is only used for
/// commands whose progress the user is waiting on.
async fn run_streamed(
    host: Arc<Host>,
    program: String,
    args: Vec<String>,
    started: Instant,
) -> baml_sdk::common::CommandResult {
    host.app.lock().unwrap().installing = true;

    let mut child = match Command::new(&program)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            host.app.lock().unwrap().push_log(1, format!("cannot run {program}: {e}"));
            host.draw(progress_pane);
            return baml_sdk::common::CommandResult { exit_code: 127, stdout: String::new() };
        }
    };

    let mut captured = String::new();
    let mut lines = BufReader::new(child.stdout.take().expect("piped stdout")).lines();

    while let Ok(Some(line)) = lines.next_line().await {
        captured.push_str(&line);
        captured.push('\n');

        // Reentrant call: BAML decides what this line means while the process
        // is still producing output. Must be the async variant.
        let Ok(event) = baml_sdk::parse_pacman_line_async(line.clone()).await else { continue };

        let mut eta_input = None;
        {
            let mut app = host.app.lock().unwrap();
            match event {
                baml_sdk::PacmanEvent::Progress(p) => {
                    app.current = p.current;
                    app.total = p.total;
                    app.package = p.package;
                    eta_input = Some((p.current, p.total));
                    app.push_log(2, line.clone());
                }
                baml_sdk::PacmanEvent::PhaseMarker(m) => {
                    app.phase = m.name.clone();
                    app.push_log(1, format!(":: {}", m.name));
                }
                baml_sdk::PacmanEvent::Downloading(d) => {
                    app.phase = format!("downloading {}", d.file);
                    app.push_log(2, line.clone());
                }
                baml_sdk::PacmanEvent::Unknown(_) => app.push_log(2, line.clone()),
            }
        }

        if let Some((current, total)) = eta_input {
            let elapsed = started.elapsed().as_millis() as i64;
            if let Ok(eta) = baml_sdk::eta_ms_async(current, total, elapsed).await {
                host.app.lock().unwrap().eta = eta;
            }
        }

        host.draw(progress_pane);
    }

    let status = child.wait().await;
    host.app.lock().unwrap().installing = false;
    baml_sdk::common::CommandResult {
        exit_code: status.ok().and_then(|s| s.code()).unwrap_or(-1) as i64,
        stdout: captured,
    }
}

// -------------------------------------------------------------- stdio & tty

/// Everything the program writes to stdout or stderr — including messages
/// from the native BAML runtime, which has no other way to reach us — is
/// collected here. Nothing is discarded: it is shown in the TUI while running
/// and printed again once the terminal is handed back.
#[derive(Clone, Default)]
struct Diagnostics(Arc<Mutex<Vec<String>>>);

impl Diagnostics {
    fn lines(&self) -> Vec<String> {
        self.0.lock().unwrap().clone()
    }
}

/// The real stdout and stderr, kept so the captured output can be printed for
/// real at the end.
struct RealStreams {
    stdout: libc::c_int,
    stderr: libc::c_int,
}

/// Routes fd 1 and fd 2 into a pipe drained into `Diagnostics`. The TUI draws
/// to /dev/tty instead, so the two can no longer collide.
fn capture_stdio() -> (Diagnostics, Option<RealStreams>) {
    use std::io::{BufRead, BufReader as SyncBufReader};
    use std::os::fd::FromRawFd;

    let collected = Diagnostics::default();
    let mut fds = [0 as libc::c_int; 2];
    // SAFETY: `fds` is a valid two-element array; `pipe` only writes into it.
    if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
        return (collected, None);
    }
    let (read_fd, write_fd) = (fds[0], fds[1]);

    // SAFETY: fds 1 and 2 are open; `dup` returns a fresh descriptor or -1.
    let saved = unsafe { RealStreams { stdout: libc::dup(1), stderr: libc::dup(2) } };
    if saved.stdout < 0 || saved.stderr < 0 {
        return (collected, None);
    }
    // SAFETY: write_fd is valid and both targets are open descriptors.
    unsafe {
        libc::dup2(write_fd, 1);
        libc::dup2(write_fd, 2);
        libc::close(write_fd);
    }

    // SAFETY: read_fd is a fresh descriptor with no other owner.
    let reader = SyncBufReader::new(unsafe { File::from_raw_fd(read_fd) });
    let sink = collected.clone();
    std::thread::spawn(move || {
        for line in reader.lines().map_while(Result::ok) {
            if !line.trim().is_empty() {
                sink.0.lock().unwrap().push(line);
            }
        }
    });
    (collected, Some(saved))
}

/// Puts the real streams back on fds 1 and 2.
fn restore_stdio(saved: &RealStreams) {
    // SAFETY: both saved descriptors were produced by `dup` and are still open.
    unsafe {
        libc::dup2(saved.stdout, 1);
        libc::dup2(saved.stderr, 2);
    }
}

/// Takes over the terminal device, leaving stdout and stderr alone.
fn init_terminal() -> std::io::Result<Term> {
    let mut tty = File::options().read(true).write(true).open("/dev/tty")?;
    enable_raw_mode()?;
    execute!(tty, EnterAlternateScreen)?;
    Terminal::new(CrosstermBackend::new(tty))
}

fn restore_terminal() {
    if let Ok(mut tty) = File::options().read(true).write(true).open("/dev/tty") {
        let _ = execute!(tty, LeaveAlternateScreen);
    }
    let _ = disable_raw_mode();
}
