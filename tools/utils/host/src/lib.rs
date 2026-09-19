//! What every OpinionatedArch tool with a terminal interface shares: taking the
//! terminal over, the frame a screen is drawn in, the widgets a form is asked
//! with, and running the commands a tool is handed.
//!
//! A tool's host is built on this and keeps only what is its own. Nothing here
//! knows a tool, or the SDK BAML generates for one: what a tool adds to the
//! state and to the keyboard reaches this crate through [`Tool`]. See
//! docs/development/001-host-bridge.md.

mod about;
mod commands;
mod host;
mod keys;
mod picker;
mod runtime_log;
mod terminal;
mod widgets;

pub use about::{about_view, splash};
pub use commands::{run_captured, run_fed, Ran};
pub use host::{answered, busy_pane, content_block, spin, App, Host, StatusKey, Step, Tool};
pub use keys::{is_back, next_key, widget_key, Asking};
pub use picker::{ui_pick, Want};
pub use runtime_log::{save_log, show_log};
pub use terminal::{
    capture_stdio, init_terminal, restore_stdio, restore_terminal, Diagnostics, RealStreams, Term,
};
pub use widgets::{modal, modal_choose, ui_choose, ui_choose_many, ui_text};
