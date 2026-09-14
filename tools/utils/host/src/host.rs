//! The state every screen is drawn from, and the frame it is drawn in: the
//! steps on the left, the status bar at the bottom, and the pane between them.

use std::sync::{Arc, Mutex};

use crossterm::event::KeyEvent;
use ratatui::layout::{Constraint, Direction, Flex, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::terminal::{Diagnostics, Term};

pub(crate) const TITLE: &str = " OpinionatedArch ";
/// The step list says what it is. The product's name is on the first screen and
/// on F3, where it means something; over a column of steps it means nothing.
const STEPS_TITLE: &str = " Steps ";
const STEPS_WIDTH: u16 = 26;

/// An entry of the step list, in the three forms it is read in: what there is
/// to do, what is being done, and what was done.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Step {
    pub to_do: String,
    pub doing: String,
    pub done: String,
}

/// A key on the status bar, what it does, and whether it answers now.
pub struct StatusKey {
    pub key: String,
    pub label: String,
    pub enabled: bool,
}

impl StatusKey {
    pub fn new(key: &str, label: impl Into<String>, enabled: bool) -> Self {
        StatusKey { key: key.into(), label: label.into(), enabled }
    }
}

/// What a tool adds to the frame. Its own state is the `tool` of [`App`], and
/// these are what the frame asks of it.
pub trait Tool: Send + Sized + 'static {
    /// The keys the status bar offers, in order, and which of them answer now.
    fn status_keys(app: &App<Self>, waiting: usize) -> Vec<StatusKey>;

    /// A key read by a widget, before the widget sees it. Returns None when the
    /// key was consumed.
    fn global_key(host: &Host<Self>, key: KeyEvent) -> Option<KeyEvent>;

    /// Where the walk to a directory to write a file into begins.
    fn save_from(app: &App<Self>) -> String;
}

pub struct App<T> {
    pub outline: Vec<Step>,
    pub step: String,
    pub error: Option<String>,
    /// How many widgets are on screen reading the keyboard for themselves.
    /// While there is one, any other reader keeps its hands off: two readers
    /// on one terminal split the keys between them at random.
    pub asking: usize,
    /// Every step is behind us. Nothing announces this — the run simply ends —
    /// so the host is what marks the list off.
    pub finished: bool,
    /// A full-screen view is up, and the status-bar keys do nothing until it
    /// closes. They are drawn dim so that they do not invite a press.
    pub overlay: bool,
    /// The step list is hidden, because what is on screen is not a step of the
    /// form. Seeing it come back reads as having returned to the tool.
    pub full_screen: bool,
    /// The first screen is up. There is nothing behind it to go back to, and
    /// nothing to tell about that it is not already saying.
    pub on_splash: bool,
    /// What the question being asked says about itself. Cleared as soon as it
    /// is answered, so a note never outlives the question it belongs to.
    pub tip: Vec<String>,
    /// What this program says about itself, read once. It is held here rather
    /// than read where it is drawn, because it is drawn on every keypress and
    /// it does not change while the program runs.
    pub about: Vec<String>,
    /// What a screen is doing while it is not asking anything, when it is
    /// doing something. A screen says so, and the next question takes it down
    /// again.
    ///
    /// Nothing here draws itself: a screen that waits on a radio and a screen
    /// that has hung look the same from the outside, and this is what tells
    /// them apart.
    pub busy: Option<String>,
    /// Which frame of the turning thing is up.
    pub busy_frame: usize,
    /// What is the tool's own.
    pub tool: T,
}

impl<T> App<T> {
    pub fn new(about: Vec<String>, tool: T) -> Self {
        App {
            outline: Vec::new(),
            step: String::new(),
            error: None,
            asking: 0,
            finished: false,
            overlay: false,
            full_screen: false,
            on_splash: false,
            tip: Vec::new(),
            about,
            busy: None,
            busy_frame: 0,
            tool,
        }
    }

    /// How far the run has gone, as steps finished out of steps to take. A
    /// step the list does not hold is the end of the run, which is every step
    /// done.
    pub fn phases_done(&self) -> usize {
        if self.finished {
            return self.outline.len();
        }
        self.outline.iter().position(|p| p.doing == self.step).unwrap_or(self.outline.len())
    }
}

pub struct Host<T> {
    pub term: Mutex<Term>,
    pub app: Mutex<App<T>>,
    pub diagnostics: Diagnostics,
}

impl<T: Tool> Host<T> {
    pub fn new(term: Term, app: App<T>, diagnostics: Diagnostics) -> Self {
        Host { term: Mutex::new(term), app: Mutex::new(app), diagnostics }
    }

    /// Draws the standard chrome and lets the caller fill the content pane.
    pub fn draw<F: FnOnce(&mut Frame, &App<T>, Rect)>(&self, fill: F) {
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
            status_bar(f, T::status_keys(&app, waiting), rows[1]);
        });
    }

    pub fn take_error(&self) -> Option<String> {
        self.app.lock().unwrap().error.take()
    }
}

// ------------------------------------------------------------------- chrome

fn steps_pane<T>(f: &mut Frame, app: &App<T>, area: Rect) {
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

fn status_bar(f: &mut Frame, keys: Vec<StatusKey>, area: Rect) {
    let key = Style::default().fg(Color::Black).bg(Color::Cyan);
    let dim = Style::default().fg(Color::DarkGray);
    let label = Style::default().fg(Color::Gray);

    let mut spans = Vec::new();
    for entry in keys {
        spans.push(Span::styled(format!(" {} ", entry.key), if entry.enabled { key } else { dim }));
        spans.push(Span::styled(format!("{} ", entry.label), if entry.enabled { label } else { dim }));
    }

    f.render_widget(Paragraph::new(Line::from(spans)), area);
}

/// Content pane: bordered, titled with the step, with the prompt on top.
/// Returns the area left for the widget itself.
pub fn content_block<T>(f: &mut Frame, app: &App<T>, area: Rect, title: &str, prompt: &str,
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

pub(crate) fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let [row] = Layout::vertical([Constraint::Length(height)]).flex(Flex::Center).areas(area);
    let [cell] = Layout::horizontal([Constraint::Length(width)]).flex(Flex::Center).areas(row);
    cell
}

/// How tall a box has to be for its text to fit. Counting lines is not enough:
/// they are wrapped, so a line longer than the box is two rows, and counting it
/// as one is what cuts the last line off.
pub(crate) fn wrapped_height(lines: &[String], inner: u16) -> u16 {
    let inner = inner.max(1) as usize;
    let rows: usize = lines
        .iter()
        .map(|l| (l.chars().count() + inner - 1) / inner)
        .map(|rows| rows.max(1))
        .sum();
    rows as u16
}

/// A question has been answered, so what it said about itself goes with it.
pub fn answered<T: Tool, A>(host: &Host<T>, answer: A) -> A {
    host.app.lock().unwrap().tip.clear();
    answer
}

/// What a screen shows while it is working and not asking. The steps stay
/// where they are; only the pane a question would be in changes.
pub fn busy_pane<T>(f: &mut Frame, app: &App<T>, area: Rect) {
    let Some(label) = app.busy.clone() else { return };
    // ASCII, because this is drawn on whatever console the machine booted
    // with, and a character that is not in its font is a blank that never
    // moves — which is the one thing this exists not to look like.
    const FRAMES: [char; 4] = ['-', '\\', '|', '/'];
    let turning = FRAMES[app.busy_frame % FRAMES.len()];

    f.render_widget(Clear, area);
    f.render_widget(
        Paragraph::new(vec![
            Line::from(""),
            Line::from(format!("{turning} {label}…")).centered(),
        ])
        .block(Block::default().borders(Borders::ALL).title(" Working ")),
        area,
    );
}

/// Turns it, until whatever was being waited for is over. One thread for as
/// long as there is something to say, started by the screen that says it and
/// ended by the next question.
pub fn spin<T: Tool>(host: Arc<Host<T>>) {
    std::thread::spawn(move || loop {
        {
            let mut app = host.app.lock().unwrap();
            if app.busy.is_none() {
                return;
            }
            app.busy_frame = app.busy_frame.wrapping_add(1);
        }
        host.draw(busy_pane);
        std::thread::sleep(std::time::Duration::from_millis(120));
    });
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
