//! The first screen, and F3: the wordmark, what the program says about itself,
//! and one key to go on.

use crossterm::event::KeyCode;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Paragraph};

use crate::host::{Host, Tool, TITLE};
use crate::keys::{next_key, widget_key};

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

/// The first screen: the wordmark, what this is, and one key to go on.
///
/// The wordmark is dropped on a console too short to hold it, rather than the
/// text being cut: what the screen is for is the words, and the picture is what
/// can be spared.
fn splash_lines(about: &[String], height: u16, footer: &str) -> Vec<Line<'static>> {
    let cyan = Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD);
    let mut lines: Vec<Line> = Vec::new();

    let with_wordmark = height >= WORDMARK.len() as u16 + about.len() as u16 + 7;
    if with_wordmark {
        for row in WORDMARK {
            lines.push(Line::from(Span::styled(row, cyan)).centered());
        }
        lines.push(Line::from(""));
    } else {
        lines.push(Line::from(Span::styled("OpinionatedArch", cyan)).centered());
        lines.push(Line::from(""));
    }

    for text in about {
        lines.push(Line::from(text.clone()).centered());
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
fn draw_about<T: Tool>(host: &Host<T>, footer: &str) {
    host.draw(|f, app, area| {
        f.render_widget(Clear, area);
        let rows = area.height.saturating_sub(2);
        f.render_widget(
            Paragraph::new(splash_lines(&app.about, rows, footer))
                .block(Block::default().borders(Borders::ALL).title(TITLE)),
            area,
        );
    });
}

/// What F3 shows: the first screen again, and a way back to where it was
/// pressed. Esc rather than F1, because while this is up the bar answers
/// nothing and F1 is drawn dim along with the rest.
pub fn about_view<T: Tool>(host: &Host<T>) {
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
/// the one way out and is now the only one: backing out of a screen never ends
/// the program by accident.
pub fn splash<T: Tool>(host: &Host<T>) {
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
