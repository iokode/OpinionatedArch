//! Terminal host for the OpinionatedArch installer.
//!
//! This binary owns exactly two things: the terminal, and running processes.
//! Which questions get asked, in what order, what counts as a valid answer,
//! which commands run and what their output means — all of that lives in BAML
//! and reaches this file only through the callbacks passed to `run_installer`.
//! See docs/decisions/015-installer-host-bridge.md.

use std::cell::Cell;
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
/// The step list says what it is. The product's name is on the first screen and
/// on F3, where it means something; over a column of steps it means nothing.
const STEPS_TITLE: &str = " Steps ";
const STEPS_WIDTH: u16 = 26;

/// Verbose levels, as in the previous installer: 0 shows the current step
/// only, 1 adds our own messages, 2 adds the output of every command.
const VERBOSE_MAX: u8 = 2;

#[derive(Default)]
struct App {
    outline: Vec<baml_sdk::Phase>,
    step: String,
    verbose: u8,
    error: Option<String>,
    on_summary: bool,
    installing: bool,
    /// Mount points F5 attached, detached again when the installation starts.
    mounted: Vec<String>,
    /// A widget is on screen and reading the keyboard for itself. While it is,
    /// the installation's own reader keeps its hands off: two readers on one
    /// terminal split the keys between them at random.
    asking: bool,
    /// Every phase is behind us. Nothing announces this any more — the run
    /// simply ends — so the host is what marks the list off and fills the bar.
    finished: bool,
    /// How far up the log has been scrolled, in lines. Zero is the bottom,
    /// which is where new lines appear.
    ///
    /// Drawing it is what says how far up it can go — the count of lines the
    /// verbose level shows, less the height of the box — so drawing it is what
    /// writes the number back. Without that, pressing up at the top raises a
    /// number nothing can act on, and coming back down means pressing down
    /// once for every time it was raised.
    scrolled: Cell<usize>,
    /// A full-screen view is up, and the status-bar keys do nothing until it
    /// closes. They are drawn dim so that they do not invite a press.
    overlay: bool,
    /// The step list is hidden, because what is on screen is not a step of the
    /// form. Seeing it come back reads as having returned to the installer.
    full_screen: bool,
    /// The first screen is up. There is nothing behind it to go back to, and
    /// nothing to tell about that it is not already saying.
    on_splash: bool,
    package: String,
    current: i64,
    total: i64,
    eta: Option<i64>,
    /// What the question being asked says about itself. Cleared as soon as it
    /// is answered, so a note never outlives the question it belongs to.
    tip: Vec<String>,
    /// Everything the installation has said, in order.
    log: Vec<Logged>,
}

/// A line of the installation log, and what kind of thing it is. The kind is
/// what gives it its colour, and what decides whether the current verbose level
/// shows it at all.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Said {
    /// The phase under way. Always shown: it is the least the operator can be
    /// told, and at verbose 0 it is the whole of what they are told.
    Phase,
    /// What the phase is doing, in words.
    Action,
    /// What a command printed while doing it.
    Output,
    /// Why the installation stopped. Always shown: it is the one line the
    /// operator came for.
    Failed,
    /// That it is over, and what to press. Always shown, for the same reason.
    Finished,
}

impl Said {
    /// The lowest verbose level that shows this kind.
    fn level(self) -> u8 {
        match self {
            Said::Phase => 0,
            Said::Action => 1,
            Said::Output => 2,
            Said::Failed => 0,
            Said::Finished => 0,
        }
    }

    fn style(self) -> Style {
        match self {
            //# the same cyan the step list marks the current phase with: the
            //# line in the log and the entry in the list are the same thing
            Said::Phase => Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
            Said::Action => Style::default().fg(Color::White),
            Said::Output => Style::default().fg(Color::DarkGray),
            Said::Failed => Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
            Said::Finished => Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
        }
    }
}

struct Logged {
    kind: Said,
    text: String,
}

impl App {
    fn scroll_by(&self, lines: i64) {
        let at = self.scrolled.get() as i64;
        self.scrolled.set(at.saturating_add(lines).max(0) as usize);
    }

    /// Nothing is ever dropped. An installation is minutes long and its log is
    /// measured in megabytes, and a log that forgets its beginning is a log
    /// that cannot be scrolled back to the phase that went wrong.
    fn push_log(&mut self, kind: Said, text: String) {
        self.log.push(Logged { kind, text });
    }

    /// How far the installation has gone, as phases finished out of phases to
    /// run. A step the list does not hold is the end of the run, which is every
    /// phase done.
    fn phases_done(&self) -> usize {
        if self.finished {
            return self.outline.len();
        }
        self.outline.iter().position(|p| p.doing == self.step).unwrap_or(self.outline.len())
    }

    /// The phase that has just ended reads as what was done rather than as what
    /// was being done. Only the line says so: the list on the left is a list of
    /// what there is to do, and ticking it is what marks it off.
    fn close_the_last_phase(&mut self) {
        let Some(line) = self.log.iter_mut().rev().find(|line| line.kind == Said::Phase) else {
            return;
        };
        let Some(phase) = self.outline.iter().find(|p| p.doing == line.text) else { return };
        line.text = phase.done.clone();
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
        // What the runtime says is kept, not shown: it is one line of noise in
        // front of a question, and F8 is where it can be read in full.
        let waiting = self.diagnostics.lines().len();
        let _ = term.draw(|f| {
            let rows = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Min(5), Constraint::Length(1)])
                .split(f.area());
            if app.full_screen {
                fill(f, &app, rows[0]);
            } else {
                let panes = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([Constraint::Length(STEPS_WIDTH), Constraint::Min(20)])
                    .split(rows[0]);

                steps_pane(f, &app, panes[0]);
                fill(f, &app, panes[1]);
            }
            status_bar(f, &app, waiting, rows[1]);
        });
    }

    fn take_error(&self) -> Option<String> {
        self.app.lock().unwrap().error.take()
    }
}

// ------------------------------------------------------------------- chrome

fn steps_pane(f: &mut Frame, app: &App, area: Rect) {
    let at = app.phases_done();
    let items: Vec<ListItem> = app
        .outline
        .iter()
        .enumerate()
        .map(|(i, name)| {
            let (mark, style) = if i < at {
                ("✓", Style::default().fg(Color::Green))
            } else if i == at {
                ("▸", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
            } else {
                (" ", Style::default().fg(Color::DarkGray))
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!(" {mark} "), style),
                Span::styled(name.to_do.clone(), style),
            ]))
        })
        .collect();
    f.render_widget(
        List::new(items).block(Block::default().borders(Borders::ALL).title(STEPS_TITLE)),
        area,
    );
}

fn status_bar(f: &mut Frame, app: &App, waiting: usize, area: Rect) {
    let key = Style::default().fg(Color::Black).bg(Color::Cyan);
    let dim = Style::default().fg(Color::DarkGray);
    let label = Style::default().fg(Color::Gray);

    let mut spans = Vec::new();
    //# nothing on this bar answers while a full-screen view is up, so nothing
    //# on it is drawn as though it would
    let live = !app.overlay;
    //# the first screen of the form has nothing behind it, and neither does an
    //# installation: F1 leads somewhere only from the second entry onwards
    let can_go_back = !app.on_splash && app.phases_done() > 0;
    let entry = |spans: &mut Vec<Span<'static>>, k: &str, text: String, enabled: bool| {
        spans.push(Span::styled(format!(" {k} "), if enabled { key } else { dim }));
        spans.push(Span::styled(format!("{text} "), if enabled { label } else { dim }));
    };

    entry(&mut spans, "F1", "Back".into(), live && !app.installing && can_go_back);
    entry(&mut spans, "F2", "Install".into(), live && app.on_summary);
    entry(&mut spans, "F3", "About".into(), live && !app.installing && !app.on_splash);
    entry(&mut spans, "F4", format!("Verbose: {}", app.verbose), live);
    entry(&mut spans, "F5", "Mount media".into(), live && !app.installing);
    //# once it is over, leaving is the thing the last line asks for
    entry(&mut spans, "F6", "Exit".into(), live && (!app.installing || app.finished));
    entry(&mut spans, "F7", "Shutdown".into(), live && !app.installing);
    // The count is the whole of the notice: without it, a log nothing points
    // at is a log nobody opens.
    entry(&mut spans, "F8", format!("Runtime log: {waiting}"), live && waiting > 0);

    f.render_widget(Paragraph::new(Line::from(spans)), area);
}

/// Content pane: bordered, titled with the step, with the prompt on top.
/// Returns the area left for the widget itself.
fn content_block(f: &mut Frame, app: &App, area: Rect, title: &str, prompt: &str,
                 error: Option<&str>) -> Rect {
    f.render_widget(
        Block::default().borders(Borders::ALL).title(format!(" {title} ")),
        area,
    );
    let inner = area.inner(ratatui::layout::Margin { horizontal: 2, vertical: 1 });

    // The note sits under the widget rather than over it: what is being
    // answered stays where the eye already is, and the explanation waits below.
    //
    // Each entry is a paragraph, wrapped to the box, so the height is what the
    // wrapping makes of it and not how many entries there are. Breaking the
    // text where it was written instead would leave a ragged edge far short of
    // the border, which is what reads as broken.
    let note = if app.tip.is_empty() {
        0
    } else {
        wrapped_height(&app.tip, inner.width.saturating_sub(2)) + 2
    };
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),
            Constraint::Min(1),
            Constraint::Length(note),
            Constraint::Length(1),
        ])
        .split(inner);

    if note > 0 {
        let lines: Vec<Line> = app
            .tip
            .iter()
            .map(|l| Line::from(Span::styled(l.clone(), Style::default().fg(Color::Gray))))
            .collect();
        f.render_widget(
            Paragraph::new(lines).wrap(Wrap { trim: true }).block(
                Block::default().borders(Borders::ALL).title(" What this means "),
            ),
            rows[2],
        );
    }

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
            rows[3],
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

/// How tall a modal has to be for its text to fit. Counting lines is not
/// enough: they are wrapped, so a line longer than the box is two rows, and
/// counting it as one is what cuts the last line off.
fn wrapped_height(lines: &[String], inner: u16) -> u16 {
    let inner = inner.max(1) as usize;
    let rows: usize = lines
        .iter()
        .map(|l| (l.chars().count() + inner - 1) / inner)
        .map(|rows| rows.max(1))
        .sum();
    rows as u16
}

const MODAL_WIDTH: u16 = 60;

fn modal(host: &Host, title: &str, lines: Vec<String>, hints: &str) -> bool {
    let _asking = Asking::new(host);
    loop {
        host.draw(|f, _, _| {
            let height = wrapped_height(&lines, MODAL_WIDTH - 2) + 4;
            let area = centered(f.area(), MODAL_WIDTH, height.min(f.area().height));
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

/// A list drawn over whatever screen is up, for something that is not part of
/// the form. Returns the chosen row, or None.
fn modal_choose(host: &Host, title: &str, options: &[String]) -> Option<usize> {
    let mut cursor = 0usize;
    loop {
        host.draw(|f, _, _| {
            let height = (options.len() as u16 + 4).min(f.area().height);
            let area = centered(f.area(), 72, height);
            f.render_widget(Clear, area);
            let mut state = ListState::default();
            state.select(Some(cursor));
            let items: Vec<ListItem> = options.iter().map(|o| ListItem::new(o.clone())).collect();
            f.render_stateful_widget(
                List::new(items)
                    .block(Block::default().borders(Borders::ALL).title(format!(" {title} ")))
                    .highlight_style(Style::default().fg(Color::Black).bg(Color::Cyan))
                    .highlight_symbol(" ▸ "),
                area,
                &mut state,
            );
        });

        let Some(key) = next_key() else { continue };
        match key.code {
            KeyCode::Up => cursor = cursor.saturating_sub(1),
            KeyCode::Down => cursor = (cursor + 1).min(options.len().saturating_sub(1)),
            KeyCode::Enter => return Some(cursor),
            KeyCode::Esc | KeyCode::F(1) | KeyCode::F(5) => return None,
            _ => {}
        }
    }
}

/// Mounts removable media, so that the pickers can reach a package that is on a
/// stick nobody has mounted yet.
///
/// Nothing here decides anything: which command lists the devices, what its
/// output means, where a device is mounted and what a failure is called all come
/// from BAML, reentrantly, exactly as pacman's output is parsed while it runs.
/// This function runs the commands and draws the result.
async fn mount_media(host: &Host) {
    let Ok(listing) = baml_sdk::mountable_listing_argv_async().await else { return };
    let found = run_captured(listing.program, listing.args).await;
    let Ok(devices) = baml_sdk::parse_mountable_async(found.result.stdout).await else { return };

    if devices.is_empty() {
        let nothing = baml_sdk::nothing_to_mount_async()
            .await
            .unwrap_or_else(|_| "Nothing to mount.".into());
        modal(host, "Mount media", vec![nothing], "Enter or Esc to close");
        return;
    }

    let Ok(labels) = baml_sdk::mountable_labels_async(devices.clone()).await else { return };
    let Some(picked) = modal_choose(host, "Mount media", &labels) else { return };
    let path = devices[picked].path.clone();

    let Ok(at) = baml_sdk::mount_point_for_async(path.clone()).await else { return };
    if let Err(e) = std::fs::create_dir_all(&at) {
        modal(host, "Mount media", vec![format!("cannot create {at}: {e}")], "Enter or Esc to close");
        return;
    }

    let Ok(argv) = baml_sdk::mount_argv_async(path.clone(), at.clone()).await else { return };
    let mounted = run_captured(argv.program, argv.args).await;
    if mounted.result.exit_code != 0 {
        let failure = baml_sdk::mount_failed_async(path, mounted.result.exit_code)
            .await
            .unwrap_or_else(|_| "Mounting failed.".into());
        modal(host, "Mount media", vec![failure], "Enter or Esc to close");
        return;
    }

    // Remembered so that it can be detached again before the disk is written
    // to, which is the one moment media must not still be attached.
    host.app.lock().unwrap().mounted.push(at.clone());
    modal(host, "Mount media", vec![format!("Mounted at {at}")], "Enter or Esc to close");
}

/// Detaches everything F5 mounted. Called when the installation starts: what
/// was taken from a medium was copied when it was chosen, so nothing here is
/// still needed, and nothing browsed stays attached to a disk being erased.
async fn unmount_media(host: &Host) {
    let attached: Vec<String> = std::mem::take(&mut host.app.lock().unwrap().mounted);
    for at in attached {
        let Ok(argv) = baml_sdk::unmount_argv_async(at).await else { continue };
        let _ = run_captured(argv.program, argv.args).await;
    }
}

// ------------------------------------------------------------------- splash

/// The wordmark, in block letters: 75 columns, which a console 80 wide
/// takes with room to spare. Two lines, because the name does not fit on
/// one, and every row is the same width so that centring them lines them up.
const WORDMARK: [&str; 11] = [
    " ███   ████   █████  █   █  █████   ███   █   █   ███   █████  █████  ████",
    "█   █  █   █    █    ██  █    █    █   █  ██  █  █   █    █    █      █   █",
    "█   █  ████     █    █ █ █    █    █   █  █ █ █  █████    █    ████   █   █",
    "█   █  █        █    █  ██    █    █   █  █  ██  █   █    █    █      █   █",
    " ███   █      █████  █   █  █████   ███   █   █  █   █    █    █████  ████",
    "",
    " ███   ████    ████  █   █",
    "█   █  █   █  █      █   █",
    "█████  ████   █      █████",
    "█   █  █  █   █      █   █",
    "█   █  █   █   ████  █   █",
];

/// What the About box says, which is what the first screen says too: it is the
/// same text, and this is where it is read rather than where it is looked up.
fn about_lines() -> Vec<String> {
    vec![
        "OpinionatedArch is an Arch-based distribution for one".into(),
        "person juggling multiple work contexts.".into(),
        String::new(),
        "Created by Ivan Montilla (@montyclt)".into(),
        "Part of the IOKode Project — iokode.blog".into(),
        String::new(),
        "Website: oparch.iokode.net".into(),
        "Licensed under the BSD 2-Clause License".into(),
    ]
}

/// The first screen: the wordmark, what this is, and one key to go on.
///
/// The wordmark is dropped on a console too short to hold it, rather than the
/// text being cut: what the screen is for is the words, and the picture is what
/// can be spared.
fn splash_lines(height: u16, footer: &str) -> Vec<Line<'static>> {
    let cyan = Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD);
    let mut lines: Vec<Line> = Vec::new();

    let with_wordmark = height >= WORDMARK.len() as u16 + about_lines().len() as u16 + 7;
    if with_wordmark {
        for row in WORDMARK {
            lines.push(Line::from(Span::styled(row, cyan)).centered());
        }
        lines.push(Line::from(""));
    } else {
        lines.push(Line::from(Span::styled("OpinionatedArch", cyan)).centered());
        lines.push(Line::from(""));
    }

    for text in about_lines() {
        lines.push(Line::from(text).centered());
    }
    lines.push(Line::from(""));
    lines.push(
        Line::from(Span::styled(
            footer.to_string(),
            Style::default().fg(Color::Black).bg(Color::Cyan),
        ))
        .centered(),
    );
    lines
}

/// Draws that screen. The first screen and F3 are the same view, so they are
/// the same drawing: only the line at the bottom differs, because only what to
/// press next differs.
fn draw_about(host: &Host, footer: &str) {
    host.draw(|f, _, area| {
        f.render_widget(Clear, area);
        let rows = area.height.saturating_sub(2);
        f.render_widget(
            Paragraph::new(splash_lines(rows, footer))
                .block(Block::default().borders(Borders::ALL).title(TITLE)),
            area,
        );
    });
}

/// What F3 shows: the first screen again, and a way back to where it was
/// pressed. Esc rather than F1, because while this is up the bar answers
/// nothing and F1 is drawn dim along with the rest.
fn about_view(host: &Host) {
    {
        let mut app = host.app.lock().unwrap();
        app.full_screen = true;
        app.overlay = true;
    }

    loop {
        draw_about(host, "Press Esc to go back");
        let Some(key) = next_key() else { continue };
        if matches!(key.code, KeyCode::Esc | KeyCode::F(1) | KeyCode::F(3) | KeyCode::Enter) {
            let mut app = host.app.lock().unwrap();
            app.full_screen = false;
            app.overlay = false;
            return;
        }
    }
}

/// Holds the screen until the operator says to start. Leaving is F6, which is
/// the one way out of the installer and is now the only one: backing out of a
/// screen never ends the program by accident.
fn splash(host: &Host) {
    {
        let mut app = host.app.lock().unwrap();
        app.full_screen = true;
        app.on_splash = true;
    }

    tokio::task::block_in_place(|| loop {
        draw_about(host, "Press Enter to begin");

        let Some(key) = widget_key(host) else { continue };
        if key.code == KeyCode::Enter {
            let mut app = host.app.lock().unwrap();
            app.full_screen = false;
            app.on_splash = false;
            return;
        }
    })
}

// --------------------------------------------------------------- runtime log

/// What the log is called when it is written out. The directory is chosen, so
/// only the name has to be typed, and it comes prefilled.
const LOG_FILE: &str = "oparch-runtime.log";

/// Writes the log where the operator chooses: a directory picked by walking to
/// it, and a name typed into a field. Reports where it landed, or why it did
/// not.
fn save_log(host: &Host, lines: &[String]) {
    let Some(directory) =
        ui_pick(host, "Save the runtime log".into(), "Choose where to write it.".into(),
                "/".into(), Want::Directory)
    else {
        return;
    };
    let Some(name) =
        ui_text(host, "Save the runtime log".into(), "File name".into(), LOG_FILE.into(), false)
    else {
        return;
    };
    let name = if name.trim().is_empty() { LOG_FILE.to_string() } else { name.trim().to_string() };

    let at = joined(&directory, &name);
    let written = lines.join("\n") + "\n";
    let said = match std::fs::write(&at, written) {
        Ok(()) => format!("Written to {at}"),
        Err(e) => format!("Cannot write {at}: {e}"),
    };
    modal(host, "Save the runtime log", vec![said], "Enter or Esc to close");
}

/// The whole of what the BAML runtime and the program itself printed, over the
/// screen rather than beside it.
///
/// It is one line of noise where a question should be, and most of it is about
/// a shared library being found or fetched — worth keeping, not worth reading
/// unless something went wrong.
fn show_log(host: &Host) {
    let lines = host.diagnostics.lines();
    if lines.is_empty() {
        return;
    }
    let body = lines.join("\n");
    let mut top: u16 = 0;
    {
        let mut app = host.app.lock().unwrap();
        app.overlay = true;
        //# stays set while the log is saved too: the picker that chooses where
        //# is part of reading the log, not a step of the installation
        app.full_screen = true;
    }

    loop {
        host.draw(|f, _, area| {
            f.render_widget(Clear, area);
            let title = format!(
                " Runtime log — {} line(s), from {} ",
                lines.len(),
                top as usize + 1
            );
            f.render_widget(
                Paragraph::new(body.clone())
                    .wrap(Wrap { trim: false })
                    .scroll((top, 0))
                    .block(Block::default().borders(Borders::ALL).title(title)),
                area,
            );
            let footer = Rect {
                x: area.x + 2,
                y: area.y + area.height.saturating_sub(1),
                width: area.width.saturating_sub(4),
                height: 1,
            };
            f.render_widget(
                Paragraph::new(Span::styled(
                    "↑/↓ scroll · PgUp/PgDn page · s save to a file · Esc close",
                    Style::default().fg(Color::DarkGray),
                )),
                footer,
            );
        });

        let Some(key) = next_key() else { continue };
        let page = 10u16;
        match key.code {
            KeyCode::Esc | KeyCode::F(8) => {
                let mut app = host.app.lock().unwrap();
                app.overlay = false;
                app.full_screen = false;
                return;
            }
            KeyCode::Up => top = top.saturating_sub(1),
            KeyCode::Down => top = top.saturating_add(1).min(lines.len() as u16),
            KeyCode::PageUp => top = top.saturating_sub(page),
            KeyCode::PageDown => top = top.saturating_add(page).min(lines.len() as u16),
            KeyCode::Home => top = 0,
            KeyCode::End => top = lines.len() as u16,
            //# the picker answers the status-bar keys again, so they wake up
            //# for as long as it is the thing on screen
            KeyCode::Char('s') | KeyCode::Char('S') => {
                host.app.lock().unwrap().overlay = false;
                save_log(host, &lines);
                host.app.lock().unwrap().overlay = true;
            }
            _ => {}
        }
    }
}

/// A question has been answered, so what it said about itself goes with it.
fn answered<T>(host: &Host, answer: T) -> T {
    host.app.lock().unwrap().tip.clear();
    answer
}

/// Keys that work on every screen. Returns None when the key was consumed.
fn global_key(host: &Host, key: KeyEvent) -> Option<KeyEvent> {
    match key.code {
        KeyCode::F(8) => {
            show_log(host);
            None
        }
        KeyCode::F(5) => {
            // Reentrant: BAML is above us on the stack, so the async API is
            // what may be called, as `015-installer-host-bridge.md` records.
            tokio::runtime::Handle::current().block_on(mount_media(host));
            None
        }
        KeyCode::F(3) => {
            about_view(host);
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

/// Reads the keyboard while the installation runs, which is the whole of the
/// time no widget is doing it. Without this the log could not be scrolled and
/// the verbose level could not be changed, because between F2 and the end
/// nothing on this side is waiting for a key.
fn watch_keys_while_installing(host: Arc<Host>) {
    std::thread::spawn(move || loop {
        {
            let app = host.app.lock().unwrap();
            if !app.installing {
                return;
            }
            if app.asking {
                drop(app);
                std::thread::sleep(Duration::from_millis(50));
                continue;
            }
        }

        let Some(key) = next_key() else { continue };
        {
            let mut app = host.app.lock().unwrap();
            match key.code {
                KeyCode::Up => app.scroll_by(1),
                KeyCode::Down => app.scroll_by(-1),
                KeyCode::PageUp => app.scroll_by(10),
                KeyCode::PageDown => app.scroll_by(-10),
                KeyCode::End => app.scrolled.set(0),
                KeyCode::F(4) => app.verbose = (app.verbose + 1) % (VERBOSE_MAX + 1),
                _ => continue,
            }
        }
        host.draw(progress_pane);
    });
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

/// Says that a widget is reading the keyboard, for as long as the value lives.
struct Asking<'a>(&'a Host);

impl<'a> Asking<'a> {
    fn new(host: &'a Host) -> Self {
        host.app.lock().unwrap().asking = true;
        Asking(host)
    }
}

impl Drop for Asking<'_> {
    fn drop(&mut self) {
        self.0.app.lock().unwrap().asking = false;
    }
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
    let _asking = Asking::new(host);
    let mut error = host.take_error();
    let mut filter = String::new();
    let mut cursor = current.max(0) as usize;

    tokio::task::block_in_place(|| loop {
        let visible = filtered(&options, &filter);
        cursor = if visible.is_empty() { 0 } else { cursor.min(visible.len() - 1) };

        host.draw(|f, app, area| {
            let body = content_block(f, app, area, &title, &prompt, error.as_deref());
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
        host.draw(|f, app, area| {
            let body = content_block(f, app, area, &title, &prompt, error.as_deref());
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
    let _asking = Asking::new(host);
    let mut error = host.take_error();
    let mut value = if secret { String::new() } else { initial };

    tokio::task::block_in_place(|| loop {
        host.draw(|f, app, area| {
            let body = content_block(f, app, area, &title, &prompt, error.as_deref());
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

// ------------------------------------------------------------------- picker

/// What a picker is being opened for. A package is a directory or a `.tar`; a
/// file is one file; a directory is where something is about to be written, so
/// files are not offered at all.
#[derive(Clone, Copy, PartialEq)]
enum Want {
    Package,
    File,
    Directory,
}

impl Want {
    /// Whether the directory being looked at may itself be the answer.
    fn takes_a_directory(self) -> bool {
        self != Want::File
    }

    fn takes(self, name: &str) -> bool {
        match self {
            Want::Package => name.ends_with(".tar"),
            Want::File => true,
            Want::Directory => false,
        }
    }
}

/// A row of the picker: what it shows, and what choosing it does.
enum Entry {
    /// Take the directory being looked at. Only offered when it may be taken.
    Here,
    /// Walk to the directory above. A row rather than only a key, because a
    /// key nothing shows is a key nobody finds.
    Up,
    /// Walk to a directory.
    Into(String),
    /// Take a file.
    Take(String),
}

impl Entry {
    fn label(&self) -> String {
        match self {
            Entry::Here => "[ use this directory ]".into(),
            Entry::Up => "../".into(),
            Entry::Into(name) => format!("{name}/"),
            Entry::Take(name) => name.clone(),
        }
    }

    /// What typing filters against. It is the bare name, not the label: the
    /// filter matches the segment after the last `/`, and a label that ends in
    /// one would have nothing left to match.
    fn key(&self) -> String {
        match self {
            Entry::Here => "use this directory".into(),
            Entry::Up => "..".into(),
            Entry::Into(name) => name.clone(),
            Entry::Take(name) => name.clone(),
        }
    }
}

/// The parent of `at`, or None when there is none to go up to.
fn parent_of(at: &str) -> Option<String> {
    std::path::Path::new(at)
        .parent()
        .map(|p| p.to_string_lossy().into_owned())
        .filter(|p| p != at)
}

fn joined(at: &str, name: &str) -> String {
    if at.ends_with('/') {
        format!("{at}{name}")
    } else {
        format!("{at}/{name}")
    }
}

/// What the picker offers in `at`: the directory itself when a package is
/// wanted, then every subdirectory, then the files that may be taken.
///
/// Directories come first because walking is what the operator is doing until
/// the last keystroke. Hidden entries are shown: a package is as likely to live
/// in `.config` as anywhere else, and a picker that hides half a disk sends the
/// operator back to a shell.
fn entries_in(at: &str, want: Want) -> Vec<Entry> {
    let mut rows = Vec::new();
    if want.takes_a_directory() {
        rows.push(Entry::Here);
    }
    if parent_of(at).is_some() {
        rows.push(Entry::Up);
    }

    let Ok(reading) = std::fs::read_dir(at) else { return rows };
    let (mut dirs, mut files) = (Vec::new(), Vec::new());
    for found in reading.flatten() {
        let name = found.file_name().to_string_lossy().into_owned();
        // A symlink is followed: what matters is what it leads to.
        let Ok(kind) = std::fs::metadata(found.path()) else { continue };
        if kind.is_dir() {
            dirs.push(name);
        } else if want.takes(&name) {
            files.push(name);
        }
    }
    dirs.sort_by_key(|n| n.to_lowercase());
    files.sort_by_key(|n| n.to_lowercase());

    rows.extend(dirs.into_iter().map(Entry::Into));
    rows.extend(files.into_iter().map(Entry::Take));
    rows
}

/// Walks the filesystem and answers with a path.
///
/// `packages` offers directories and `.tar` archives, and lets the directory
/// being looked at be the answer; otherwise one file is what is being asked
/// for, and a directory is only somewhere to walk through.
fn ui_pick(host: &Host, title: String, prompt: String, start: String, want: Want) -> Option<String> {
    let mut error = host.take_error();
    let mut at = if std::path::Path::new(&start).is_dir() { start } else { "/".to_string() };
    let mut filter = String::new();
    let mut cursor = 0usize;

    tokio::task::block_in_place(|| loop {
        let rows = entries_in(&at, want);
        let labels: Vec<String> = rows.iter().map(|e| e.label()).collect();
        let keys: Vec<String> = rows.iter().map(|e| e.key()).collect();
        let visible = filtered(&keys, &filter);
        cursor = if visible.is_empty() { 0 } else { cursor.min(visible.len() - 1) };
        let up = parent_of(&at);

        let keys_hint = match want {
            Want::Package => "↑/↓ move · → open · ← up · Enter opens a directory or takes a .tar",
            Want::File => "↑/↓ move · → open · ← up · Enter takes the file",
            Want::Directory => "↑/↓ move · → open · ← up · Enter opens a directory",
        };
        host.draw(|f, app, area| {
            let body = content_block(f, app, area, &title,
                                     &format!("{prompt}\n{keys_hint}"), error.as_deref());
            let mut state = ListState::default();
            state.select((!visible.is_empty()).then_some(cursor));
            let items: Vec<ListItem> = visible
                .iter()
                .map(|i| {
                    let style = match rows[*i] {
                        Entry::Here => Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
                        Entry::Up | Entry::Into(_) => Style::default().fg(Color::Cyan),
                        Entry::Take(_) => Style::default(),
                    };
                    ListItem::new(Line::from(Span::styled(labels[*i].clone(), style)))
                })
                .collect();
            let hint = if filter.is_empty() {
                format!(" {at} ")
            } else {
                format!(" {at}   filter: {filter} ")
            };
            f.render_stateful_widget(
                List::new(items)
                    .block(Block::default().borders(Borders::ALL).title(hint))
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
            // Left walks up, which is what a picker is expected to do; the
            // parent is not a row, so it cannot be filtered away.
            KeyCode::Left => {
                if let Some(above) = up {
                    at = above;
                    filter.clear();
                    cursor = 0;
                    error = None;
                }
            }
            KeyCode::Right | KeyCode::Enter => {
                let Some(index) = visible.get(cursor) else { continue };
                match &rows[*index] {
                    Entry::Here => return Some(at.clone()),
                    Entry::Up => {
                        if let Some(above) = up {
                            at = above;
                            filter.clear();
                            cursor = 0;
                            error = None;
                        }
                    }
                    Entry::Into(name) => {
                        at = joined(&at, name);
                        filter.clear();
                        cursor = 0;
                        error = None;
                    }
                    // Right is for walking, so it does not take a file.
                    Entry::Take(name) => {
                        if key.code == KeyCode::Enter {
                            return Some(joined(&at, name));
                        }
                    }
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

/// How a row's label reads: nested rows sit under the one they belong to, and
/// the colon is part of the label so that the values line up after it.
fn summary_label(row: &baml_sdk::SummaryRow) -> String {
    let indent = if row.nested { "  " } else { "" };
    format!("{indent}{}:", row.label)
}

/// The review screen: two columns, two colours. Every value starts at the same
/// column, whatever the label before it, because a column of values is read
/// down and a ragged one cannot be.
fn summary_columns(rows: &[baml_sdk::SummaryRow]) -> Vec<(String, String)> {
    let width = rows.iter().map(|r| summary_label(r).chars().count()).max().unwrap_or(0);
    rows.iter()
        .map(|row| {
            let label = summary_label(row);
            (format!("{label:<width$}  "), row.value.clone())
        })
        .collect()
}

fn summary_table(rows: &[baml_sdk::SummaryRow]) -> Vec<ListItem<'static>> {
    summary_columns(rows)
        .into_iter()
        .map(|(label, value)| {
            ListItem::new(Line::from(vec![
                Span::styled(label, Style::default().fg(Color::Gray)),
                Span::styled(value, Style::default().fg(Color::White)),
            ]))
        })
        .collect()
}

fn ui_review(host: &Arc<Host>, title: String, rows: Vec<baml_sdk::SummaryRow>) -> bool {
    let error = host.take_error();
    host.app.lock().unwrap().on_summary = true;

    let answer = tokio::task::block_in_place(|| loop {
        host.draw(|f, app, area| {
            let body = content_block(
                f,
                app,
                area,
                &title,
                "Review what will be done. F2 starts the installation.",
                error.as_deref(),
            );
            f.render_widget(
                List::new(summary_table(&rows))
                    .block(Block::default().borders(Borders::ALL).title(" Settings ")),
                body,
            );
        });

        let Some(key) = widget_key(host) else { continue };
        if is_back(&key) {
            return false;
        }
        if key.code == KeyCode::F(2) {
            //# media are detached before anything is written, not at exit
            tokio::runtime::Handle::current().block_on(unmount_media(host));
            host.app.lock().unwrap().installing = true;
            watch_keys_while_installing(host.clone());
            return true;
        }
    });

    host.app.lock().unwrap().on_summary = false;
    answer
}

// ----------------------------------------------------------------- progress

/// The slice of the log on screen, and how far from the bottom it really is.
///
/// It is walked from the newest line backwards, so what it costs is the height
/// of the box and how far the operator scrolled, and not how long the log has
/// grown. Drawn once per line of output, anything else would be quadratic in
/// the length of an installation.
fn log_window<'a>(
    log: &'a [Logged],
    verbose: u8,
    height: usize,
    scrolled: usize,
) -> (Vec<&'a Logged>, usize) {
    let mut walked: Vec<&Logged> = log
        .iter()
        .rev()
        .filter(|line| line.kind.level() <= verbose)
        .take(height + scrolled)
        .collect();
    walked.reverse();

    // Scrolled past the oldest line there is: the window stops at the top.
    let scrolled = scrolled.min(walked.len().saturating_sub(height));
    let end = walked.len() - scrolled;
    (walked[end.saturating_sub(height)..end].to_vec(), scrolled)
}

fn progress_pane(f: &mut Frame, app: &App, area: Rect) {
    // Its own frame rather than the form's: there is no question here, so no
    // room is kept for a prompt or for the note that went with one.
    f.render_widget(Block::default().borders(Borders::ALL).title(" Installing "), area);
    let inner = area.inner(ratatui::layout::Margin { horizontal: 2, vertical: 1 });
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)])
        .split(inner);

    // Always drawn, and never carrying text: how far along the run is, in
    // phases finished, whatever the log below it is doing.
    let total = app.outline.len().max(1);
    f.render_widget(
        Gauge::default()
            .block(Block::default().borders(Borders::ALL))
            .gauge_style(Style::default().fg(Color::Cyan))
            .ratio((app.phases_done() as f64 / total as f64).clamp(0.0, 1.0))
            .label(""),
        rows[0],
    );

    if rows[1].height < 3 {
        return;
    }
    let height = rows[1].height.saturating_sub(2) as usize;
    let (view, scrolled) = log_window(&app.log, app.verbose, height, app.scrolled.get());
    app.scrolled.set(scrolled);

    // What one phase is counting through goes beside its own line, which is the
    // last blue one on screen. Only one phase has anything to count, so a
    // column of its own would be empty nine times out of ten. Scrolled back,
    // the blue line on screen belongs to a phase that is over, and counting
    // through it is not what is happening.
    let counting = if app.total > 0 && scrolled == 0 {
        view.iter().rposition(|line| line.kind == Said::Phase)
    } else {
        None
    };
    let detail = format!("   {}/{}  {}", app.current, app.total, app.package);

    let items: Vec<ListItem> = view
        .iter()
        .enumerate()
        .map(|(at, line)| {
            let text = if counting == Some(at) {
                format!("{}{detail}", line.text)
            } else {
                line.text.clone()
            };
            ListItem::new(Line::from(Span::styled(text, line.kind.style())))
        })
        .collect();
    let title = if scrolled == 0 {
        " Log ".to_string()
    } else {
        format!(" Log — {scrolled} lines below ")
    };
    f.render_widget(
        List::new(items).block(Block::default().borders(Borders::ALL).title(title)),
        rows[1],
    );
}

// --------------------------------------------------------------------- main

/// Where the assets are. They are deployed beside the binary, so that is where
/// they are read from, and where the installer happens to be started from does
/// not enter into it. Anywhere else is `--assets`, said out loud.
fn default_asset_dir() -> String {
    let exe = std::env::current_exe().expect("the running binary has a path");
    let beside = exe.parent().expect("the binary is in a directory").join("assets");
    beside.to_string_lossy().into_owned()
}

/// The value following `name` on the command line, if it is there.
fn arg_value(name: &str) -> Option<String> {
    std::env::args().skip_while(|a| a != name).nth(1)
}

#[tokio::main]
async fn main() {
    let asset_dir = arg_value("--assets").unwrap_or_else(default_asset_dir);

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
    let (h_stream, h_step, h_action) = (host.clone(), host.clone(), host.clone());

    baml_sdk::run_installer_async(
        asset_dir,
        Some(config_text),
        move |program: String, args: Vec<String>| async move {
            run_captured(program, args).await.result
        },
        move |program: String, args: Vec<String>| {
            let host = h_stream.clone();
            async move { host.run_streamed(program, args).await }
        },
            move |program: String, args: Vec<String>, input: String| async move {
                run_fed(program, args, input).await.result
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
        move |_phases: Vec<baml_sdk::Phase>| {},
        move |title: String| h_step.line(&title),
        move |message: String| h_action.line(&message),
        move |message: String| eprintln!("error: {message}"),
        move |message: String| eprintln!("warning: {message}"),
        move |_names: Vec<String>| {},
        move |title: String, _p: String, _o: Vec<String>, _c: i64| unattended_question(&title),
        move |title: String, _p: String, _o: Vec<String>, _s: Vec<String>, _min: i64, _max: i64| {
            unattended_question(&title);
            None
        },
        move |title: String, _p: String, _i: String, _s: bool| {
            unattended_question(&title);
            None
        },
        move |title: String, _p: String, _s: String| {
            unattended_question(&title);
            None
        },
        move |title: String, _p: String, _s: String| {
            unattended_question(&title);
            None
        },
        move |_title: String, _rows: Vec<baml_sdk::SummaryRow>| true,
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
    splash(&host);

    let started = Instant::now();
    let file_ops = Arc::new(FileOps::default());

    let summary = {
        let (h_run, h_outline, h_step, h_err) =
            (host.clone(), host.clone(), host.clone(), host.clone());
        let (h_action, h_capture, h_feed) = (host.clone(), host.clone(), host.clone());
        let (h_choose, h_many, h_text, h_review) =
            (host.clone(), host.clone(), host.clone(), host.clone());
        let (h_pick_package, h_pick_file) = (host.clone(), host.clone());
        let (h_tip, h_warn) = (host.clone(), host.clone());

        baml_sdk::run_installer_async(
            asset_dir,
            None,
            move |program: String, args: Vec<String>| {
                let host = h_capture.clone();
                async move { logged(&host, run_captured(program, args).await) }
            },
            move |program: String, args: Vec<String>| {
                let host = h_run.clone();
                async move { run_streamed(host, program, args, started).await }
            },
            move |program: String, args: Vec<String>, input: String| {
                let host = h_feed.clone();
                async move { logged(&host, run_fed(program, args, input).await) }
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
            move |phases: Vec<baml_sdk::Phase>| h_outline.app.lock().unwrap().outline = phases,
            move |title: String| {
                {
                    let mut app = h_step.app.lock().unwrap();
                    app.step = title.clone();
                    app.current = 0;
                    app.total = 0;
                    app.eta = None;
                    //# the form has its own screens; a phase is a line in the log
                    if app.installing {
                        app.close_the_last_phase();
                        app.push_log(Said::Phase, title);
                    }
                }
                //# drawn as it is said, so the disk is never wiped behind a
                //# screen that has not changed since F2
                if h_step.app.lock().unwrap().installing {
                    h_step.draw(progress_pane);
                }
            },
            move |message: String| {
                h_action.app.lock().unwrap().push_log(Said::Action, message);
                h_action.draw(progress_pane);
            },
            move |message: String| {
                let installing = {
                    let mut app = h_err.app.lock().unwrap();
                    app.error = Some(message.clone());
                    if app.installing {
                        app.push_log(Said::Failed, message);
                    }
                    app.installing
                };
                //# on a screen that asks, the next question shows it; on one
                //# that does not, nothing would, so it is drawn here
                if installing {
                    h_err.draw(progress_pane);
                }
            },
            move |message: String| h_warn.diagnostics.push(message),
            move |names: Vec<String>| h_tip.app.lock().unwrap().tip = names,
            move |title: String, prompt: String, options: Vec<String>, current: i64| {
                answered(&h_choose, ui_choose(&h_choose, title, prompt, options, current))
            },
            move |title: String, prompt: String, options: Vec<String>, selected: Vec<String>, min: i64, max: i64| {
                answered(&h_many, ui_choose_many(&h_many, title, prompt, options, selected, min, max))
            },
            move |title: String, prompt: String, initial: String, secret: bool| {
                answered(&h_text, ui_text(&h_text, title, prompt, initial, secret))
            },
            move |title: String, prompt: String, start: String| {
                answered(&h_pick_package,
                         ui_pick(&h_pick_package, title, prompt, start, Want::Package))
            },
            move |title: String, prompt: String, start: String| {
                answered(&h_pick_file, ui_pick(&h_pick_file, title, prompt, start, Want::File))
            },
            move |title: String, rows: Vec<baml_sdk::SummaryRow>| {
                ui_review(&h_review, title, rows)
            },
        )
        .await
    };

    // It is over, and the screen is held until the operator says what to do
    // with the machine. Two blank lines before it, because it is not another
    // line of the log: it is the end of it.
    if let Ok(done) = &summary {
        if done.exit_code == 0 {
            {
                let mut app = host.app.lock().unwrap();
                app.close_the_last_phase();
                app.finished = true;
                app.scrolled.set(0);
                //# the blank lines are part of the ending rather than log of
                //# their own, so they are shown whatever the verbose level is
                app.push_log(Said::Finished, String::new());
                app.push_log(Said::Finished, String::new());
                app.push_log(
                    Said::Finished,
                    "Installation finished. Enter reboots; F6 leaves you in the live shell."
                        .into(),
                );
            }
            tokio::task::block_in_place(|| wait_for_the_end(&host));
        }
    }

    // Why it stopped is the one thing worth holding the screen for: past this
    // point the terminal is handed back and the frame with the reason on it is
    // gone. It is written down as well, so it survives the screen either way.
    if let Ok(done) = &summary {
        if done.exit_code != 0 && done.exit_code != 130 {
            let said = host.app.lock().unwrap().error.clone().unwrap_or_default();
            diagnostics.push(format!("installation failed: {said}"));
            tokio::task::block_in_place(|| {
                modal(&host, "Installation failed", vec![said], "Enter or Esc to close")
            });
        }
    }

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

/// Holds the last screen until the operator says what happens next. There is
/// nothing left to install, so the only two answers are to start the machine
/// they have just built, or to stay in the live environment.
fn wait_for_the_end(host: &Host) {
    let _asking = Asking::new(host);
    loop {
        host.draw(progress_pane);
        let Some(key) = next_key() else { continue };
        match key.code {
            KeyCode::Enter => {
                restore_terminal();
                let _ = std::process::Command::new("reboot").status();
                std::process::exit(0);
            }
            KeyCode::F(6) => return,
            //# the log is still there to be read, and still worth reading at a
            //# level other than the one it was watched at
            KeyCode::Up => host.app.lock().unwrap().scroll_by(1),
            KeyCode::Down => host.app.lock().unwrap().scroll_by(-1),
            KeyCode::PageUp => host.app.lock().unwrap().scroll_by(10),
            KeyCode::PageDown => host.app.lock().unwrap().scroll_by(-10),
            KeyCode::End => host.app.lock().unwrap().scrolled.set(0),
            KeyCode::F(4) => {
                let mut app = host.app.lock().unwrap();
                app.verbose = (app.verbose + 1) % (VERBOSE_MAX + 1);
            }
            _ => {}
        }
    }
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

/// What a command produced. BAML is given the exit code and standard output,
/// which is what it reads; standard error is the host's, for the log.
struct Ran {
    result: baml_sdk::common::CommandResult,
    stderr: String,
}

/// What a command printed, into the log, so that verbose 2 means the same thing
/// for every command and not only for the one that streams.
fn logged(host: &Host, ran: Ran) -> baml_sdk::common::CommandResult {
    {
        let mut app = host.app.lock().unwrap();
        if !app.installing {
            return ran.result;
        }
        for line in ran.result.stdout.lines().chain(ran.stderr.lines()) {
            app.push_log(Said::Output, line.to_string());
        }
    }
    host.draw(progress_pane);
    ran.result
}

/// Runs a command that reads from standard input. The input is written and the
/// pipe closed, so a command waiting for end-of-input proceeds.
async fn run_fed(program: String, args: Vec<String>, input: String) -> Ran {
    let failed = |code: i64| Ran {
        result: baml_sdk::common::CommandResult { exit_code: code, stdout: String::new() },
        stderr: String::new(),
    };
    let mut child = match Command::new(&program)
        .args(&args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return failed(127),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes()).await;
        drop(stdin);
    }
    match child.wait_with_output().await {
        Ok(out) => Ran {
            result: baml_sdk::common::CommandResult {
                exit_code: out.status.code().unwrap_or(-1) as i64,
                stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            },
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        },
        Err(_) => failed(-1),
    }
}

/// Runs a command for its output. No parsing, no redrawing: this is the path
/// for commands that merely produce data, and it must stay proportional to
/// running the command itself.
async fn run_captured(program: String, args: Vec<String>) -> Ran {
    match Command::new(&program).args(&args).output().await {
        Ok(out) => Ran {
            result: baml_sdk::common::CommandResult {
                exit_code: out.status.code().unwrap_or(-1) as i64,
                stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            },
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        },
        Err(_) => Ran {
            result: baml_sdk::common::CommandResult { exit_code: 127, stdout: String::new() },
            stderr: String::new(),
        },
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
    let mut child = match Command::new(&program)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            host.app.lock().unwrap().push_log(Said::Action, format!("cannot run {program}: {e}"));
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
                    app.push_log(Said::Output, line.clone());
                }
                baml_sdk::PacmanEvent::PhaseMarker(m) => {
                    app.push_log(Said::Output, format!(":: {}", m.name));
                }
                baml_sdk::PacmanEvent::Downloading(_) => {
                    app.push_log(Said::Output, line.clone());
                }
                baml_sdk::PacmanEvent::Unknown(_) => app.push_log(Said::Output, line.clone()),
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

    /// A line the installer itself wants recorded, rather than one read off the
    /// pipe. It lands beside the runtime's own, because to whoever opens F8
    /// they are the same thing: what happened that nobody was asked about.
    fn push(&self, line: String) {
        self.0.lock().unwrap().push(line);
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

// -------------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;

    /// A directory holding a subdirectory, an archive and a plain file. Each
    /// test gets its own, because they run at the same time and one tearing
    /// down the tree another is reading is a failure that comes and goes.
    fn sample_tree(named: &str) -> std::path::PathBuf {
        let root =
            std::env::temp_dir().join(format!("oparch-picker-{}-{named}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("andorra")).unwrap();
        std::fs::create_dir_all(root.join(".hidden")).unwrap();
        std::fs::write(root.join("dark.tar"), "").unwrap();
        std::fs::write(root.join("notes.txt"), "").unwrap();
        root
    }

    #[test]
    fn a_package_picker_offers_this_directory_then_directories_then_archives() {
        let root = sample_tree("packages");
        let labels: Vec<String> =
            entries_in(&root.to_string_lossy(), Want::Package).iter().map(|e| e.label()).collect();

        assert_eq!(
            labels,
            vec!["[ use this directory ]", "../", ".hidden/", "andorra/", "dark.tar"],
            "a plain file is not a package, and a hidden directory is still a directory"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_file_picker_offers_every_file_and_takes_no_directory() {
        let root = sample_tree("files");
        let rows = entries_in(&root.to_string_lossy(), Want::File);
        let labels: Vec<String> = rows.iter().map(|e| e.label()).collect();

        assert_eq!(labels, vec!["../", ".hidden/", "andorra/", "dark.tar", "notes.txt"]);
        assert!(
            !rows.iter().any(|e| matches!(e, Entry::Here)),
            "there is no directory to take when one file is what is being asked for"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn typing_filters_directories_too() {
        let root = sample_tree("filter");
        let keys: Vec<String> = entries_in(&root.to_string_lossy(), Want::Package).iter().map(|e| e.key()).collect();

        // The label ends in `/`, so filtering has to happen on the name.
        assert_eq!(filtered(&keys, "andor"), vec![3]);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_directory_picker_offers_no_file_at_all() {
        let root = sample_tree("saving");
        let rows = entries_in(&root.to_string_lossy(), Want::Directory);
        let labels: Vec<String> = rows.iter().map(|e| e.label()).collect();

        // Writing a file is choosing where, not choosing what to overwrite.
        assert_eq!(labels, vec!["[ use this directory ]", "../", ".hidden/", "andorra/"]);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_modal_is_tall_enough_for_text_that_wraps() {
        let short = vec!["one".to_string(), "two".to_string()];
        assert_eq!(wrapped_height(&short, 58), 2);

        // 70 characters in a 58-wide box is two rows, not one.
        let long = vec!["x".repeat(70)];
        assert_eq!(wrapped_height(&long, 58), 2);

        // An empty line is still a line.
        assert_eq!(wrapped_height(&[String::new()], 58), 1);
    }

    fn setting(label: &str, value: &str, nested: bool) -> baml_sdk::SummaryRow {
        baml_sdk::SummaryRow { label: label.into(), value: value.into(), nested }
    }

    #[test]
    fn every_value_on_the_review_screen_starts_at_the_same_column() {
        let rows = vec![
            setting("target disk", "/dev/sda", false),
            setting("disk swapfile size (GB)", "0", false),
            setting("owner_name", "Ivan", true),
        ];

        let columns = summary_columns(&rows);
        let widths: Vec<usize> = columns.iter().map(|(l, _)| l.chars().count()).collect();
        assert_eq!(widths, vec![26, 26, 26], "the longest label sets the column");

        // A nested row is indented into that same column, not past it.
        assert_eq!(columns[2].0.trim_end(), "  owner_name:");
        assert_eq!(columns[0].1, "/dev/sda", "the value is its own column, unpadded");
    }

    fn said(kind: Said, text: &str) -> Logged {
        Logged { kind, text: text.into() }
    }

    #[test]
    fn the_log_shows_its_tail_and_scrolls_back_through_all_of_it() {
        let mut log = vec![said(Said::Phase, "Preparing the disk...")];
        for i in 0..5000 {
            log.push(said(Said::Output, &format!("line {i}")));
        }

        // At the bottom: the last three lines, and nothing claims to be scrolled.
        let (view, scrolled) = log_window(&log, 2, 3, 0);
        assert_eq!(view.iter().map(|l| l.text.as_str()).collect::<Vec<_>>(),
                   vec!["line 4997", "line 4998", "line 4999"]);
        assert_eq!(scrolled, 0);

        // Scrolled back, the window moves with it.
        let (view, scrolled) = log_window(&log, 2, 3, 10);
        assert_eq!(view[2].text, "line 4989");
        assert_eq!(scrolled, 10);

        // Past the top it stops at the top, and says how far it really got: the
        // first line is the phase, which is 5001 lines from the bottom.
        let (view, scrolled) = log_window(&log, 2, 3, 99_999);
        assert_eq!(view[0].kind, Said::Phase);
        assert_eq!(scrolled, 5001 - 3);
    }

    #[test]
    fn scrolling_past_the_top_does_not_have_to_be_undone() {
        let mut log = vec![said(Said::Phase, "Preparing the disk...")];
        for i in 0..20 {
            log.push(said(Said::Output, &format!("line {i}")));
        }

        // Held at the top, however far past it the operator pressed.
        let (_, far) = log_window(&log, 2, 5, 99_999);
        let (_, once_more) = log_window(&log, 2, 5, far + 1);
        assert_eq!(once_more, far, "there is nowhere further up to be");

        // So one press down moves one line, rather than undoing the excess.
        let (view, back) = log_window(&log, 2, 5, far - 1);
        assert_eq!(back, far - 1);
        assert_eq!(view.len(), 5);
    }

    #[test]
    fn what_the_verbose_level_hides_is_not_scrolled_through_either() {
        let mut log = vec![said(Said::Phase, "Preparing the disk...")];
        for i in 0..100 {
            log.push(said(Said::Output, &format!("line {i}")));
        }
        log.push(said(Said::Phase, "Installing packages..."));

        // Showing phases only, the hundred lines between them are not there.
        let (view, scrolled) = log_window(&log, 0, 3, 0);
        assert_eq!(view.len(), 2);
        assert_eq!(scrolled, 0);
    }

    #[test]
    fn walking_up_stops_at_the_top() {
        assert_eq!(parent_of("/run/oparch/media"), Some("/run/oparch".into()));
        assert_eq!(parent_of("/"), None);
    }

    #[test]
    fn the_top_of_the_filesystem_offers_no_way_up() {
        assert!(
            !entries_in("/", Want::Package).iter().any(|e| matches!(e, Entry::Up)),
            "a row that goes nowhere is a row that lies"
        );
    }

    #[test]
    fn joining_a_name_never_doubles_the_separator() {
        assert_eq!(joined("/", "media"), "/media");
        assert_eq!(joined("/run", "media"), "/run/media");
    }
}
