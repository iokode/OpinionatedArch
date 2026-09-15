//! Terminal host for the OpinionatedArch interactive installer.
//!
//! This binary owns exactly two things: the terminal, and running processes.
//! Which questions get asked, in what order, what counts as a valid answer,
//! which commands run and what their output means — all of that lives in BAML
//! and reaches this file only through the callbacks passed to `run_installer`.
//! See docs/development/001-host-bridge.md.
//!
//! What every host shares — taking the terminal over, the frame, the widgets
//! and running a command — is the crate in tools/utils/host/. What is here is
//! the installer's own: its log and the pane it is drawn in, the review screen,
//! media, and pacman's output read while it runs.

use std::cell::Cell;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossterm::event::{KeyCode, KeyEvent};
use oparch_host::{
    about_view, answered, capture_stdio, content_block, init_terminal, is_back, modal, modal_choose,
    next_key, restore_stdio, restore_terminal, run_captured, run_fed, save_log, show_log, spin,
    splash, ui_choose, ui_choose_many, ui_pick, ui_text, widget_key, Asking, Ran, StatusKey, Step,
    Tool, Want,
};
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Gauge, List, ListItem, Paragraph};
use ratatui::Frame;
use tokio::io::{AsyncReadExt, BufReader};
use tokio::process::Command;

type Host = oparch_host::Host<Installer>;
type App = oparch_host::App<Installer>;

/// Verbose levels, as in the previous installer: 0 shows the current step
/// only, 1 adds our own messages, 2 adds the output of every command.
const VERBOSE_MAX: u8 = 2;

/// What the installer adds to the state every screen is drawn from.
#[derive(Default)]
struct Installer {
    verbose: u8,
    on_summary: bool,
    installing: bool,
    /// Mount points F5 attached, detached again when the installation starts.
    mounted: Vec<String>,
    /// The run stopped and will not go on. The phase it stopped in is left
    /// reading as the phase it was doing: it did not finish, and a list that
    /// marks it off says it did.
    failed: bool,
    /// When the operator started it, which is F2 and not when the program did:
    /// what took the time is the installation, not the answering of questions.
    started_at: Option<Instant>,
    /// How far up the log has been scrolled, in lines. Zero is the bottom,
    /// which is where new lines appear.
    ///
    /// Drawing it is what says how far up it can go — the count of lines the
    /// verbose level shows, less the height of the box — so drawing it is what
    /// writes the number back. Without that, pressing up at the top raises a
    /// number nothing can act on, and coming back down means pressing down
    /// once for every time it was raised.
    scrolled: Cell<usize>,
    package: String,
    current: i64,
    total: i64,
    eta: Option<i64>,
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
    /// What a command wrote to standard error. Its own kind rather than more
    /// output, because it is what to read first when something went wrong — and
    /// its own level, because a package manager that fails writes thousands of
    /// lines and none of them belong in front of an operator who did not ask.
    Complaint,
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
            Said::Complaint => 2,
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
            //# yellow, because standard error is not how a program says it
            //# failed: `mkinitcpio` reports firmware it did not find there, and
            //# `grub-install` announces that it finished with no error at all.
            //# Worth finding among the output it sits in, and never mistakable
            //# for the one line that says the run stopped, which is the red one.
            Said::Complaint => Style::default().fg(Color::Yellow),
            Said::Failed => Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
            Said::Finished => Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
        }
    }
}

struct Logged {
    kind: Said,
    text: String,
}

impl Installer {
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
}

/// The phase that has just ended reads as what was done rather than as what
/// was being done. Only the line says so: the list on the left is a list of
/// what there is to do, and ticking it is what marks it off.
fn close_the_last_phase(app: &mut App) {
    let Some(line) = app.tool.log.iter_mut().rev().find(|line| line.kind == Said::Phase) else {
        return;
    };
    let Some(phase) = app.outline.iter().find(|p| p.doing == line.text) else { return };
    line.text = phase.done.clone();
}

/// Says that a command is about to run. It is said before rather than after,
/// because the one worth watching is the one still going.
fn announce(host: &Host, program: &str, args: &[String]) {
    {
        let mut app = host.app.lock().unwrap();
        if !app.tool.installing {
            return;
        }
        app.tool.push_log(Said::Action, command_line(program, args));
    }
    host.draw(progress_pane);
}

impl Tool for Installer {
    fn status_keys(app: &App, waiting: usize) -> Vec<StatusKey> {
        //# nothing on this bar answers while a full-screen view is up, so nothing
        //# on it is drawn as though it would
        let live = !app.overlay;
        //# the first screen of the form has nothing behind it, and neither does an
        //# installation: F1 leads somewhere only from the second entry onwards
        let can_go_back = !app.on_splash && app.phases_done() > 0;
        let tool = &app.tool;

        vec![
            StatusKey::new("F1", "Back", live && !tool.installing && can_go_back),
            StatusKey::new("F2", "Install", live && tool.on_summary),
            StatusKey::new("F3", "About", live && !tool.installing && !app.on_splash),
            StatusKey::new("F4", format!("Verbose: {}", tool.verbose), live),
            //# and again once it is over, because saving the log needs somewhere to
            //# save it to
            StatusKey::new("F5", "Mount media", live && (!tool.installing || app.finished)),
            //# once it is over, leaving is the thing the last line asks for
            StatusKey::new("F6", "Exit", live && (!tool.installing || app.finished)),
            StatusKey::new("F7", "Shutdown", live && !tool.installing),
            // The count is the whole of the notice: without it, a log nothing points
            // at is a log nobody opens.
            StatusKey::new("F8", format!("Runtime log: {waiting}"), live && waiting > 0),
        ]
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
                // what may be called, as `docs/development/001-host-bridge.md` records.
                tokio::runtime::Handle::current().block_on(mount_media(host));
                None
            }
            KeyCode::F(3) => {
                about_view(host);
                None
            }
            KeyCode::F(4) => {
                let mut app = host.app.lock().unwrap();
                app.tool.verbose = (app.tool.verbose + 1) % (VERBOSE_MAX + 1);
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

    /// The walk begins at the medium last attached, when there is one. A log is
    /// saved onto a stick, and the stick is what F5 was pressed for a moment
    /// earlier; starting at the top of the filesystem would make the operator
    /// walk down to what they have just mounted.
    fn save_from(app: &App) -> String {
        app.tool.mounted.last().cloned().unwrap_or_else(|| "/".into())
    }
}

/// How long it took, for someone reading it rather than timing it: minutes and
/// seconds, and hours when there were any.
fn how_long(taken: Duration) -> String {
    let seconds = taken.as_secs();
    let (hours, minutes, seconds) = (seconds / 3600, (seconds / 60) % 60, seconds % 60);
    if hours > 0 {
        format!("{hours}h {minutes}m {seconds}s")
    } else if minutes > 0 {
        format!("{minutes}m {seconds}s")
    } else {
        format!("{seconds}s")
    }
}

// -------------------------------------------------------------------- media

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
    let Ok(devices) = baml_sdk::parse_mountable_async(found.stdout).await else { return };

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
    if mounted.exit_code != 0 {
        let failure = baml_sdk::mount_failed_async(path, mounted.exit_code)
            .await
            .unwrap_or_else(|_| "Mounting failed.".into());
        modal(host, "Mount media", vec![failure], "Enter or Esc to close");
        return;
    }

    // Remembered so that it can be detached again before the disk is written
    // to, which is the one moment media must not still be attached.
    host.app.lock().unwrap().tool.mounted.push(at.clone());
    modal(host, "Mount media", vec![format!("Mounted at {at}")], "Enter or Esc to close");
}

/// Detaches everything F5 mounted. Called when the installation starts: what
/// was taken from a medium was copied when it was chosen, so nothing here is
/// still needed, and nothing browsed stays attached to a disk being erased.
async fn unmount_media(host: &Host) {
    let attached: Vec<String> = std::mem::take(&mut host.app.lock().unwrap().tool.mounted);
    for at in attached {
        let Ok(argv) = baml_sdk::unmount_argv_async(at).await else { continue };
        let _ = run_captured(argv.program, argv.args).await;
    }
}

// ------------------------------------------------------------------- splash

/// What the About box says, which is what the first screen says too. It is one
/// text and it lives beside the other assets, so that changing what this
/// program says about itself is editing a file rather than building a binary.
///
/// Every line is drawn as it is written, centred, so the file is what decides
/// where the text breaks.
fn about_text(asset_dir: &str) -> Vec<String> {
    let path = format!("{asset_dir}/about.txt");
    match std::fs::read_to_string(&path) {
        Ok(text) => text.lines().map(str::to_string).collect(),
        Err(e) => {
            eprintln!("cannot read {path}: {e}");
            std::process::exit(2);
        }
    }
}

// ---------------------------------------------------------- installation log

/// What the log of the installation is called when it is written out.
const INSTALL_LOG_FILE: &str = "oparch-install.log";

/// The installation log as a file: everything of it, whatever the screen was
/// showing, because a level is what one screen is filtered by and not what the
/// run consisted of. Colour cannot be written down, so the shape carries what
/// the colour did — a phase at the margin, what it did indented under it, and
/// what its commands printed indented under that.
fn log_as_text(log: &[Logged]) -> Vec<String> {
    log.iter()
        .map(|line| {
            let indent = match line.kind {
                Said::Phase | Said::Finished | Said::Failed => "",
                Said::Action => "  ",
                Said::Output | Said::Complaint => "    ",
            };
            format!("{indent}{}", line.text)
        })
        .collect()
}

/// Reads the keyboard while the installation runs, which is the whole of the
/// time no widget is doing it. Without this the log could not be scrolled and
/// the verbose level could not be changed, because between F2 and the end
/// nothing on this side is waiting for a key.
fn watch_keys_while_installing(host: Arc<Host>) {
    std::thread::spawn(move || loop {
        {
            let app = host.app.lock().unwrap();
            if !app.tool.installing {
                return;
            }
            if app.asking > 0 {
                drop(app);
                std::thread::sleep(Duration::from_millis(50));
                continue;
            }
        }

        let Some(key) = next_key() else { continue };
        {
            let mut app = host.app.lock().unwrap();
            match key.code {
                KeyCode::Up => app.tool.scroll_by(1),
                KeyCode::Down => app.tool.scroll_by(-1),
                KeyCode::PageUp => app.tool.scroll_by(10),
                KeyCode::PageDown => app.tool.scroll_by(-10),
                KeyCode::End => app.tool.scrolled.set(0),
                KeyCode::F(4) => app.tool.verbose = (app.tool.verbose + 1) % (VERBOSE_MAX + 1),
                _ => continue,
            }
        }
        host.draw(progress_pane);
    });
}

// ------------------------------------------------------------------- review

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
    host.app.lock().unwrap().tool.on_summary = true;

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
            {
                let mut app = host.app.lock().unwrap();
                app.tool.installing = true;
                app.tool.started_at = Some(Instant::now());
            }
            watch_keys_while_installing(host.clone());
            return true;
        }
    });

    host.app.lock().unwrap().tool.on_summary = false;
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

/// The three levels, each written in the colour of what it adds, so that the
/// legend is its own example. The one in force is marked rather than named: it
/// is on screen either way, and a line saying which is a line to read.
///
/// It belongs here rather than in the notes the questions carry: the levels and
/// the colours are the terminal's own vocabulary, and nothing on the other side
/// of the bridge knows them.
fn verbosity_box(app: &App) -> Vec<Line<'static>> {
    [
        (0u8, Said::Phase, "phases"),
        (1, Said::Action, "+ what each phase is doing"),
        (2, Said::Output, "+ what its commands printed"),
    ]
    .into_iter()
    .map(|(level, kind, text)| {
        let in_force = level == app.tool.verbose;
        let style = if in_force { kind.style().add_modifier(Modifier::BOLD) } else { kind.style() };
        Line::from(vec![
            Span::styled(
                format!(" {} {level}   ", if in_force { "▸" } else { " " }),
                Style::default().fg(Color::Gray),
            ),
            Span::styled(text, style),
        ])
    })
    .collect()
}

/// What there is left to do once there is nothing left to install. It is a box
/// of its own rather than the last lines of the log, because it is not part of
/// what happened and has no business being saved with it.
fn finished_box() -> Vec<Line<'static>> {
    // The same two columns and the same two colours as the review screen: a key
    // is read the way a setting is, and there is no reason for the eye to learn
    // a second arrangement for it.
    let key = Style::default().fg(Color::Gray);
    let what = Style::default().fg(Color::White);
    let note = Style::default().fg(Color::DarkGray);

    let keys = [
        ("Enter", "reboot into the installed system"),
        ("F6", "stay here, in the live environment"),
        ("s", "save the log to a file (all of it, whatever level is shown)"),
        ("F5", "mount a disk"),
    ];
    let width = keys.iter().map(|(pressed, _)| pressed.chars().count()).max().unwrap_or(0);
    let mut lines: Vec<Line> = keys
        .into_iter()
        .map(|(pressed, does)| {
            Line::from(vec![
                Span::styled(format!("  {pressed:<width$}   "), key),
                Span::styled(does, what),
            ])
        })
        .collect();

    // Where to save it is not what a key does, so it is not written beside one.
    // It is also the thing the operator is least likely to know: the system
    // they have just installed is still mounted, and saving onto it needs
    // nothing mounting at all.
    lines.push(Line::from(""));
    for line in [
        "  This filesystem is in RAM. To keep the log, write it to the system just installed,",
        "  which is mounted at /mnt, or press F5 to mount an external device.",
    ] {
        lines.push(Line::from(Span::styled(line, note)));
    }
    lines
}

/// What there is left to do once the installation has stopped. A box of its own
/// for the same reason the finished one is: it is not part of what happened,
/// and it has no business being saved with the log.
///
/// Rebooting is the one thing it does not offer. There is no installed system
/// to start, and offering it beside a failure is offering to boot a machine
/// that was never finished.
fn failed_box() -> Vec<Line<'static>> {
    let key = Style::default().fg(Color::Gray);
    let what = Style::default().fg(Color::White);
    let note = Style::default().fg(Color::DarkGray);

    let keys = [
        ("F4", "change how much of the log is shown"),
        ("s", "save the log to a file (all of it, whatever level is shown)"),
        ("F5", "mount a disk"),
        ("F6", "leave the installer and stay in the live environment"),
    ];
    let width = keys.iter().map(|(pressed, _)| pressed.chars().count()).max().unwrap_or(0);
    let mut lines: Vec<Line> = keys
        .into_iter()
        .map(|(pressed, does)| {
            Line::from(vec![
                Span::styled(format!("  {pressed:<width$}   "), key),
                Span::styled(does, what),
            ])
        })
        .collect();

    lines.push(Line::from(""));
    for line in [
        "  What stopped the installation is in red above, in full. At verbose 2 the log also",
        "  holds everything each command printed, which is where the rest of the story is.",
    ] {
        lines.push(Line::from(Span::styled(line, note)));
    }
    lines
}

fn progress_pane(f: &mut Frame, app: &App, area: Rect) {
    // Its own frame rather than the form's: there is no question here, so no
    // room is kept for a prompt or for the note that went with one.
    f.render_widget(Block::default().borders(Borders::ALL).title(" Installing "), area);
    let inner = area.inner(ratatui::layout::Margin { horizontal: 2, vertical: 1 });
    let levels = verbosity_box(app);
    // Red without the bold the failure lines carry: the box says where to go
    // next, and what went wrong is above it and should stay the louder of the two.
    let (ending, ending_title, ending_style) = if app.finished {
        (finished_box(), " Finished ", Style::default())
    } else if app.tool.failed {
        (failed_box(), " Error ", Style::default().fg(Color::Red))
    } else {
        (Vec::new(), "", Style::default())
    };
    let ending_rows = if ending.is_empty() { 0 } else { ending.len() as u16 + 2 };
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(0),
            Constraint::Length(ending_rows),
            Constraint::Length(levels.len() as u16 + 2),
        ])
        .split(inner);
    if ending_rows > 0 {
        f.render_widget(
            Paragraph::new(ending).block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(ending_title)
                    .border_style(ending_style),
            ),
            rows[2],
        );
    }
    f.render_widget(
        Paragraph::new(levels)
            .block(Block::default().borders(Borders::ALL).title(" Verbosity (F4) ")),
        rows[3],
    );

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
    let (view, scrolled) = log_window(&app.tool.log, app.tool.verbose, height, app.tool.scrolled.get());
    app.tool.scrolled.set(scrolled);

    // What one phase is counting through goes beside its own line, which is the
    // last blue one on screen. Only one phase has anything to count, so a
    // column of its own would be empty nine times out of ten. Scrolled back,
    // the blue line on screen belongs to a phase that is over, and counting
    // through it is not what is happening.
    let counting = if app.tool.total > 0 && scrolled == 0 {
        view.iter().rposition(|line| line.kind == Said::Phase)
    } else {
        None
    };
    let detail = format!("   {}/{}  {}", app.tool.current, app.tool.total, app.tool.package);

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
    // The keys belong to the thing they move, which is this box, exactly as
    // the form's widgets carry theirs. Where the window is sits on the other
    // end of the same border, so the two never have to share the room.
    let mut frame = Block::default()
        .borders(Borders::ALL)
        .title_top(" Log · ↑/↓ scroll · PgUp/PgDn page · End newest ");
    if scrolled > 0 {
        frame = frame.title_top(Line::from(format!(" {scrolled} below ")).right_aligned());
    }
    f.render_widget(List::new(items).block(frame), rows[1]);
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

    let summary = run_interactive(asset_dir).await;

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

/// A step of the list, from the phase BAML hands over.
fn step_of(phase: baml_sdk::installer::Phase) -> Step {
    Step { to_do: phase.to_do, doing: phase.doing, done: phase.done }
}

/// How a command ended, as the port's result BAML reads.
fn result_of(ran: Ran) -> baml_sdk::common::CommandResult {
    baml_sdk::common::CommandResult { exit_code: ran.exit_code, stdout: ran.stdout, stderr: ran.stderr }
}

/// The terminal installer: takes over the screen and asks.
async fn run_interactive(
    asset_dir: String,
) -> Result<baml_sdk::installer::InstallSummary, baml_bridge::Error<std::convert::Infallible>> {
    // Read before the terminal is taken over, so that a file this program
    // cannot read is said plainly instead of into a screen nobody will see.
    let about = about_text(&asset_dir);

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
    let host = Arc::new(Host::new(term, App::new(about, Installer::default()), diagnostics.clone()));
    splash(&host);

    let started = Instant::now();

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
            move |program: String, args: Vec<String>| {
                let host = h_capture.clone();
                async move {
                    announce(&host, &program, &args);
                    logged(&host, result_of(run_captured(program, args).await))
                }
            },
            move |program: String, args: Vec<String>| {
                let host = h_run.clone();
                async move { run_streamed(host, program, args, started).await }
            },
            move |program: String, args: Vec<String>, input: String| {
                let host = h_feed.clone();
                async move {
                    announce(&host, &program, &args);
                    logged(&host, result_of(run_fed(program, args, input).await))
                }
            },
            move |phases: Vec<baml_sdk::installer::Phase>| {
                h_outline.app.lock().unwrap().outline = phases.into_iter().map(step_of).collect()
            },
            move |title: String| {
                {
                    let mut app = h_step.app.lock().unwrap();
                    app.step = title.clone();
                    app.tool.current = 0;
                    app.tool.total = 0;
                    app.tool.eta = None;
                    //# whatever the screen before this one was waiting for is
                    //# over, said so or not: this is a different screen
                    app.busy = None;
                    //# the form has its own screens; a phase is a line in the log
                    if app.tool.installing {
                        close_the_last_phase(&mut app);
                        app.tool.push_log(Said::Phase, title);
                    }
                }
                //# drawn as it is said, so the disk is never wiped behind a
                //# screen that has not changed since F2
                if h_step.app.lock().unwrap().tool.installing {
                    h_step.draw(progress_pane);
                }
            },
            move |message: String| {
                // During an installation this is a line of the log. Before one,
                // there is no log on screen and it means something else: a
                // screen saying what it is about to wait for, which is what the
                // turning thing is labelled with until the next question.
                let mut app = h_action.app.lock().unwrap();
                if !app.tool.installing {
                    let was_idle = app.busy.is_none();
                    app.busy = Some(message);
                    drop(app);
                    if was_idle {
                        spin(h_action.clone());
                    }
                    return;
                }
                app.tool.push_log(Said::Action, message);
                drop(app);
                h_action.draw(progress_pane);
            },
            move |message: String| {
                let installing = {
                    let mut app = h_err.app.lock().unwrap();
                    app.error = Some(message.clone());
                    if app.tool.installing {
                        // The log is a list of lines, so a message carrying the
                        // whole of what a command complained about is entered a
                        // line at a time. All of it is shown whatever the
                        // verbose level: it is the one thing the operator came
                        // for, and it is what a failed run is about.
                        for line in message.lines() {
                            app.tool.push_log(Said::Failed, readable(line));
                        }
                        app.tool.push_log(Said::Failed, "Installation aborted.".into());
                        app.tool.failed = true;
                    }
                    app.tool.installing
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
                close_the_last_phase(&mut app);
                app.finished = true;
                app.tool.scrolled.set(0);
                //# the blank lines are part of the ending rather than log of
                //# their own, so they are shown whatever the verbose level is
                app.tool.push_log(Said::Finished, String::new());
                app.tool.push_log(Said::Finished, String::new());
                let took = app
                    .tool
                    .started_at
                    .map(|from| format!(" in {}", how_long(from.elapsed())))
                    .unwrap_or_default();
                //# the log ends with what happened. What to press about it is
                //# not what happened, and saving the log should not save it
                app.tool.push_log(Said::Finished, format!("Installation finished{took}."));
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
            //# held rather than shown behind a modal: what stopped it is already
            //# in the log, in full and in red, and a box over it would cover the
            //# very lines it is about. Holding the screen is also what makes the
            //# verbose level worth mentioning — it can still be changed here
            tokio::task::block_in_place(|| wait_after_failure(&host));
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
            // Saving it is why mounting has to work here: the medium it is
            // saved to is one nobody had a reason to mount before now.
            KeyCode::F(5) => tokio::runtime::Handle::current().block_on(mount_media(host)),
            KeyCode::Char('s') | KeyCode::Char('S') => {
                let written = log_as_text(&host.app.lock().unwrap().tool.log);
                save_log(host, "Save the installation log", INSTALL_LOG_FILE, &written);
            }
            //# the log is still there to be read, and still worth reading at a
            //# level other than the one it was watched at
            KeyCode::Up => host.app.lock().unwrap().tool.scroll_by(1),
            KeyCode::Down => host.app.lock().unwrap().tool.scroll_by(-1),
            KeyCode::PageUp => host.app.lock().unwrap().tool.scroll_by(10),
            KeyCode::PageDown => host.app.lock().unwrap().tool.scroll_by(-10),
            KeyCode::End => host.app.lock().unwrap().tool.scrolled.set(0),
            KeyCode::F(4) => {
                let mut app = host.app.lock().unwrap();
                app.tool.verbose = (app.tool.verbose + 1) % (VERBOSE_MAX + 1);
            }
            _ => {}
        }
    }
}

/// Holds the screen after a run that stopped, so the reason stays readable and
/// the log can still be turned up, scrolled and saved.
///
/// It offers everything the finished screen does but the one thing that screen
/// leads with: there is no installed system to reboot into.
fn wait_after_failure(host: &Host) {
    let _asking = Asking::new(host);
    loop {
        host.draw(progress_pane);
        let Some(key) = next_key() else { continue };
        match key.code {
            KeyCode::F(6) => return,
            KeyCode::F(5) => tokio::runtime::Handle::current().block_on(mount_media(host)),
            KeyCode::Char('s') | KeyCode::Char('S') => {
                let written = log_as_text(&host.app.lock().unwrap().tool.log);
                save_log(host, "Save the installation log", INSTALL_LOG_FILE, &written);
            }
            KeyCode::Up => host.app.lock().unwrap().tool.scroll_by(1),
            KeyCode::Down => host.app.lock().unwrap().tool.scroll_by(-1),
            KeyCode::PageUp => host.app.lock().unwrap().tool.scroll_by(10),
            KeyCode::PageDown => host.app.lock().unwrap().tool.scroll_by(-10),
            KeyCode::End => host.app.lock().unwrap().tool.scrolled.set(0),
            KeyCode::F(4) => {
                let mut app = host.app.lock().unwrap();
                app.tool.verbose = (app.tool.verbose + 1) % (VERBOSE_MAX + 1);
            }
            _ => {}
        }
    }
}

/// A line of command output as a terminal would leave it on screen.
///
/// What a command writes is not text: pacman colours its output and redraws its
/// progress in place, so a line arrives carrying escape sequences and carriage
/// returns. Put in a buffer they are not drawn, they are obeyed — the terminal
/// moves its cursor out of the box the line belongs to and paints over whatever
/// is there, which is the step list.
fn readable(line: &str) -> String {
    // After a carriage return, only what came after it was ever on screen.
    let visible = line.rsplit('\r').next().unwrap_or(line);
    let mut out = String::with_capacity(visible.len());
    let mut rest = visible.chars().peekable();

    while let Some(c) = rest.next() {
        if c != '\u{1b}' {
            if !c.is_control() {
                out.push(c);
            }
            continue;
        }
        match rest.peek() {
            //# a control sequence runs to its final byte
            Some('[') => {
                rest.next();
                for c in rest.by_ref() {
                    if ('@'..='~').contains(&c) {
                        break;
                    }
                }
            }
            //# an operating system command runs to a bell or to ESC \
            Some(']') => {
                rest.next();
                while let Some(c) = rest.next() {
                    if c == '\u{7}' {
                        break;
                    }
                    if c == '\u{1b}' {
                        rest.next();
                        break;
                    }
                }
            }
            _ => {
                rest.next();
            }
        }
    }
    out
}

/// A command as it was run, for the log. What was actually executed, rather
/// than a sentence about it: the sentence is the phase, one level up.
fn command_line(program: &str, args: &[String]) -> String {
    if args.is_empty() { program.to_string() } else { format!("{program} {}", args.join(" ")) }
}

/// What a command printed, into the log, so that verbose 2 means the same thing
/// for every command and not only for the one that streams.
fn logged(host: &Host, ran: baml_sdk::common::CommandResult) -> baml_sdk::common::CommandResult {
    {
        let mut app = host.app.lock().unwrap();
        if !app.tool.installing {
            return ran;
        }
        for line in ran.stdout.lines() {
            app.tool.push_log(Said::Output, readable(line));
        }
        for line in ran.stderr.lines() {
            app.tool.push_log(Said::Complaint, readable(line));
        }
    }
    host.draw(progress_pane);
    ran
}

/// Drains a child's standard error while its standard output is still being
/// read, and puts each complaint in the log as it arrives rather than after the
/// command is over. Reading one of two pipes and leaving the other to fill is
/// what makes a talkative command block forever, so this is spawned before the
/// stdout loop rather than collected after it. What is returned is still
/// everything, for the result the caller gets.
fn stream_stderr(child: &mut tokio::process::Child, host: Arc<Host>)
        -> tokio::task::JoinHandle<String> {
    let piped = child.stderr.take();
    tokio::spawn(async move {
        let mut collected = String::new();
        let Some(pipe) = piped else { return collected };
        let mut segments = Segments::new(pipe);
        while let Some(segment) = segments.next().await {
            collected.push_str(&segment);
            collected.push('\n');
            {
                let mut app = host.app.lock().unwrap();
                if app.tool.installing {
                    app.tool.push_log(Said::Complaint, readable(&segment));
                }
            }
            host.draw(progress_pane);
        }
        collected
    })
}

/// What a command writes, cut where a terminal would show a new line: at `\n`,
/// and also at `\r`.
///
/// A download draws its progress by returning the cursor to the start of the
/// line and painting over it, so a reader that waits for `\n` is handed
/// nothing at all until the transfer is over — and then one line holding every
/// redraw at once. Cutting at both gives one segment per redraw, which is what
/// makes a download something the operator can watch.
struct Segments<R> {
    reader: BufReader<R>,
    buffer: Vec<u8>,
}

impl<R: tokio::io::AsyncRead + Unpin> Segments<R> {
    fn new(reader: R) -> Self {
        Segments { reader: BufReader::new(reader), buffer: Vec::new() }
    }

    /// The next segment, or nothing when the pipe is closed. Empty segments are
    /// skipped: a `\r\n` ends one segment and would otherwise open another.
    async fn next(&mut self) -> Option<String> {
        loop {
            match self.reader.read_u8().await {
                Ok(byte) => {
                    if byte != b'\n' && byte != b'\r' {
                        self.buffer.push(byte);
                        continue;
                    }
                    let segment = String::from_utf8_lossy(&self.buffer).into_owned();
                    self.buffer.clear();
                    if !segment.trim().is_empty() {
                        return Some(segment);
                    }
                }
                Err(_) => {
                    if self.buffer.is_empty() {
                        return None;
                    }
                    let segment = String::from_utf8_lossy(&self.buffer).into_owned();
                    self.buffer.clear();
                    return Some(segment);
                }
            }
        }
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
    announce(&host, &program, &args);
    let mut child = match Command::new(&program)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            host.app.lock().unwrap().tool.push_log(Said::Action, format!("cannot run {program}: {e}"));
            host.draw(progress_pane);
            return baml_sdk::common::CommandResult {
                exit_code: 127,
                stdout: String::new(),
                stderr: String::new(),
            };
        }
    };

    let complaints = stream_stderr(&mut child, host.clone());
    let mut captured = String::new();
    let mut lines = Segments::new(child.stdout.take().expect("piped stdout"));

    while let Some(line) = lines.next().await {
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
                    app.tool.current = p.current;
                    app.tool.total = p.total;
                    app.tool.package = p.package;
                    eta_input = Some((p.current, p.total));
                    app.tool.push_log(Said::Output, readable(&line));
                }
                baml_sdk::PacmanEvent::PhaseMarker(m) => {
                    app.tool.push_log(Said::Output, readable(&format!(":: {}", m.name)));
                }
                baml_sdk::PacmanEvent::Downloading(_) => {
                    app.tool.push_log(Said::Output, readable(&line));
                }
                baml_sdk::PacmanEvent::Unknown(_) => app.tool.push_log(Said::Output, line.clone()),
            }
        }

        if let Some((current, total)) = eta_input {
            let elapsed = started.elapsed().as_millis() as i64;
            if let Ok(eta) = baml_sdk::eta_ms_async(current, total, elapsed).await {
                host.app.lock().unwrap().tool.eta = eta;
            }
        }

        host.draw(progress_pane);
    }

    let status = child.wait().await;
    //# already in the log, pushed as each one arrived; what comes back here is
    //# the whole of it, for the result the caller is given
    let complained = complaints.await.unwrap_or_default();

    baml_sdk::common::CommandResult {
        exit_code: status.ok().and_then(|s| s.code()).unwrap_or(-1) as i64,
        stdout: captured,
        stderr: complained,
    }
}

// -------------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;

    /// Why the run stopped is one line and is always shown. What the command
    /// wrote is not: a package manager that fails writes thousands of lines, and
    /// an operator watching at level 0 asked for none of them.
    #[test]
    fn a_failure_says_what_stopped_it_and_keeps_the_rest_for_level_two() {
        let complaint = [
            "error: target not found: ipxe",
            "error: failed to commit transaction",
        ];
        let mut log = vec![said(Said::Phase, "Installing packages...")];
        for line in complaint {
            log.push(said(Said::Complaint, line));
        }
        log.push(said(Said::Failed, "Installing the base system failed with exit code 1."));
        log.push(said(Said::Failed, "Installation aborted."));

        let (quiet, _) = log_window(&log, 0, 40, 0);
        let shown: Vec<&str> = quiet.iter().map(|line| line.text.as_str()).collect();
        assert!(shown.contains(&"Installing the base system failed with exit code 1."));
        assert!(shown.contains(&"Installation aborted."));
        for line in complaint {
            assert!(!shown.contains(&line), "{line} should wait for verbose 2");
        }

        let (loud, _) = log_window(&log, 2, 40, 0);
        let shown: Vec<&str> = loud.iter().map(|line| line.text.as_str()).collect();
        for line in complaint {
            assert!(shown.contains(&line), "{line} is missing at verbose 2");
        }
    }

    /// A download is drawn by returning the cursor and painting over the line,
    /// so what makes it watchable is cutting where the terminal shows a new
    /// line: at the carriage return as much as at the line feed. Cut only at
    /// the line feed, the four redraws below would reach the log as one line,
    /// and not until the transfer was over.
    #[tokio::test]
    async fn every_redraw_of_a_progress_bar_is_a_segment_of_its_own() {
        let written = "downloading linux...\r 25%\r 50%\r100%\r\ndone\n";
        let mut segments = Segments::new(written.as_bytes());

        let mut seen = Vec::new();
        while let Some(segment) = segments.next().await {
            seen.push(segment);
        }

        assert_eq!(seen, vec!["downloading linux...", " 25%", " 50%", "100%", "done"]);
    }

    /// What a pipe holds when it closes is a segment too, even with nothing
    /// ending it: a command killed mid-line still said what it said.
    #[tokio::test]
    async fn what_arrives_without_an_ending_is_still_a_segment() {
        let mut segments = Segments::new("half a line".as_bytes());

        assert_eq!(segments.next().await, Some("half a line".to_string()));
        assert_eq!(segments.next().await, None);
    }

    /// Standard error is where plenty of commands put what is not their output:
    /// `mkinitcpio` reports firmware it did not find there, and `grub-install`
    /// announces that it finished with no error at all. Red is kept for the one
    /// line that says the run stopped, so a run that worked ends without any.
    #[test]
    fn what_a_command_wrote_to_standard_error_is_not_painted_as_a_failure() {
        assert_eq!(Said::Complaint.style().fg, Some(Color::Yellow));
        assert_eq!(Said::Failed.style().fg, Some(Color::Red));
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
    fn what_a_command_writes_is_read_as_text_and_never_obeyed() {
        // pacman colours its output.
        assert_eq!(readable("\u{1b}[1;32m==>\u{1b}[0m Building image"), "==> Building image");

        // And redraws its progress in place: only the last pass was on screen.
        assert_eq!(readable("downloading  10%\rdownloading  90%"), "downloading  90%");

        // A sequence that moves the cursor is what painted over the step list.
        assert_eq!(readable("\u{1b}[2Kleft edge"), "left edge");
        assert_eq!(readable("a\u{1b}]0;a title\u{7}b"), "ab");

        // Everything else is left exactly as it came.
        assert_eq!(
            readable("UUID=2330b40a / btrfs rw,relatime,subvol=/@log 0 0"),
            "UUID=2330b40a / btrfs rw,relatime,subvol=/@log 0 0"
        );
        assert_eq!(readable("tabs\tand\u{8}backspaces"), "tabsandbackspaces");
    }

    #[test]
    fn how_long_it_took_reads_as_a_duration_rather_than_a_count() {
        assert_eq!(how_long(Duration::from_secs(9)), "9s");
        assert_eq!(how_long(Duration::from_secs(252)), "4m 12s");
        assert_eq!(how_long(Duration::from_secs(3600)), "1h 0m 0s");
        assert_eq!(how_long(Duration::from_secs(4271)), "1h 11m 11s");
    }

    #[test]
    fn the_saved_log_carries_in_its_shape_what_the_colours_carried() {
        let log = vec![
            said(Said::Phase, "Installing packages..."),
            said(Said::Action, "Installing 12 packages with pacstrap..."),
            said(Said::Output, "installing linux-firmware"),
            said(Said::Phase, "Packages installed."),
        ];

        assert_eq!(
            log_as_text(&log),
            vec![
                "Installing packages...",
                "  Installing 12 packages with pacstrap...",
                "    installing linux-firmware",
                "Packages installed.",
            ]
        );
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
}
