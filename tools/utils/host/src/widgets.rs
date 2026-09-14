//! The widget vocabulary a form is asked with: a selector, a multi-select, a
//! text field, and a box drawn over whatever screen is up.

use crossterm::event::{KeyCode, KeyModifiers};
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap};

use crate::host::{centered, content_block, wrapped_height, Host, Tool};
use crate::keys::{is_back, next_key, widget_key, Asking};

// -------------------------------------------------------------------- modals

const MODAL_WIDTH: u16 = 60;

pub fn modal<T: Tool>(host: &Host<T>, title: &str, lines: Vec<String>, hints: &str) -> bool {
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
pub fn modal_choose<T: Tool>(host: &Host<T>, title: &str, options: &[String]) -> Option<usize> {
    let _asking = Asking::new(host);
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

pub(crate) fn filtered(options: &[String], needle: &str) -> Vec<usize> {
    options
        .iter()
        .enumerate()
        .filter(|(_, o)| matches_filter(o, needle))
        .map(|(i, _)| i)
        .collect()
}

// ------------------------------------------------------------------ widgets

pub fn ui_choose<T: Tool>(host: &Host<T>, title: String, prompt: String, options: Vec<String>,
                          current: i64) -> Option<i64> {
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

pub fn ui_choose_many<T: Tool>(
    host: &Host<T>,
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

/// A text field. A secret one shows a bullet for every character typed and
/// never what was typed, and starts empty whatever it is given.
pub fn ui_text<T: Tool>(host: &Host<T>, title: String, prompt: String, initial: String,
                        secret: bool) -> Option<String> {
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
