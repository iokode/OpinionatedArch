//! Reading the keyboard, and who is reading it.

use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind};

use crate::host::{Host, Tool};

pub fn next_key() -> Option<KeyEvent> {
    if !event::poll(Duration::from_millis(100)).unwrap_or(false) {
        return None;
    }
    match event::read() {
        Ok(Event::Key(key)) if key.kind == KeyEventKind::Press => Some(key),
        _ => None,
    }
}

/// A key from a widget loop, with the tool's global shortcuts already handled.
pub fn widget_key<T: Tool>(host: &Host<T>) -> Option<KeyEvent> {
    T::global_key(host, next_key()?)
}

/// Says that a widget is reading the keyboard, for as long as the value lives.
/// It counts rather than flags, because they nest: a widget that opens a modal
/// has two of these alive at once, and the inner one going out of scope must
/// not hand the keyboard back while the outer one is still using it.
pub struct Asking<'a, T>(&'a Host<T>);

impl<'a, T> Asking<'a, T> {
    pub fn new(host: &'a Host<T>) -> Self {
        let mut app = host.app.lock().unwrap();
        app.asking += 1;
        // A question is the end of whatever was being waited for, whether or
        // not the screen thought to say so.
        app.busy = None;
        drop(app);
        Asking(host)
    }
}

impl<T> Drop for Asking<'_, T> {
    fn drop(&mut self) {
        let mut app = self.0.app.lock().unwrap();
        app.asking = app.asking.saturating_sub(1);
    }
}

pub fn is_back(key: &KeyEvent) -> bool {
    matches!(key.code, KeyCode::Esc | KeyCode::F(1))
}
