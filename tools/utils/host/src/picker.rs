//! Walking the filesystem so that something on this machine is chosen rather
//! than typed.

use crossterm::event::{KeyCode, KeyModifiers};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState};

use crate::host::{content_block, Host, Tool};
use crate::keys::{is_back, widget_key, Asking};
use crate::widgets::filtered;

/// What a picker is being opened for. A package is a directory or a `.tar`; a
/// file is one file; a directory is where something is about to be written, so
/// files are not offered at all.
#[derive(Clone, Copy, PartialEq)]
pub enum Want {
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

    /// What typing filters against. It is the bare name, not the label, so
    /// the `/` after a directory's name and the brackets around this
    /// directory's row are not matched.
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

pub(crate) fn joined(at: &str, name: &str) -> String {
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
pub fn ui_pick<T: Tool>(host: &Host<T>, title: String, prompt: String, start: String,
                        want: Want) -> Option<String> {
    let _asking = Asking::new(host);
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

        // A directory is matched by its name, as a file is.
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
    fn walking_up_stops_at_the_top() {
        assert_eq!(parent_of("/media/sdb1"), Some("/media".into()));
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
