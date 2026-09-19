//! What the BAML runtime and the program itself printed, read over the screen
//! and written to a file.

use crossterm::event::KeyCode;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::text::Span;
use ratatui::widgets::{Block, Borders, Clear, Paragraph, Wrap};

use crate::host::{Host, Tool};
use crate::keys::next_key;
use crate::picker::{joined, ui_pick, Want};
use crate::widgets::{modal, ui_text};

/// What the log is called when it is written out. The directory is chosen, so
/// only the name has to be typed, and it comes prefilled.
const LOG_FILE: &str = "oparch-runtime.log";

/// Writes lines where the operator chooses: a directory picked by walking to
/// it, starting where the tool says, and a name typed into a field. Reports
/// where it landed, or why it did not.
pub fn save_log<T: Tool>(host: &Host<T>, title: &str, suggested: &str, lines: &[String]) {
    let start = T::save_from(&host.app.lock().unwrap());
    let Some(directory) = ui_pick(host, title.into(), "Choose where to write it.".into(),
                                  start, Want::Directory)
    else {
        return;
    };
    let Some(name) = ui_text(host, title.into(), "File name".into(), suggested.into(), false)
    else {
        return;
    };
    let name = if name.trim().is_empty() { suggested.to_string() } else { name.trim().to_string() };

    let at = joined(&directory, &name);
    let written = lines.join("\n") + "\n";
    let said = match std::fs::write(&at, written) {
        Ok(()) => format!("Written to {at}"),
        Err(e) => format!("Cannot write {at}: {e}"),
    };
    modal(host, title, vec![said], "Enter or Esc to close");
}

/// The whole of what the BAML runtime and the program itself printed, over the
/// screen rather than beside it.
///
/// It is one line of noise where a question should be, and most of it is about
/// a shared library being found or fetched — worth keeping, not worth reading
/// unless something went wrong.
pub fn show_log<T: Tool>(host: &Host<T>) {
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
        //# is part of reading the log, not a step of the form
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
                save_log(host, "Save the runtime log", LOG_FILE, &lines);
                host.app.lock().unwrap().overlay = true;
            }
            _ => {}
        }
    }
}
