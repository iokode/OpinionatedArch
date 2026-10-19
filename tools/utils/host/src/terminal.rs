//! The terminal, and the standard streams while a screen holds it.

use std::fs::File;
use std::sync::{Arc, Mutex};

use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

/// The TUI draws to the terminal device directly, not to stdout. Sharing
/// stdout with the program's own output is what lets a stray message land in
/// the middle of a frame; keeping them apart removes the possibility.
pub type Term = Terminal<CrosstermBackend<File>>;

/// Everything the program writes to stdout or stderr — including messages
/// from the native BAML runtime, which has no other way to reach us — is
/// collected here. Nothing is discarded: it is shown in the TUI while running
/// and printed again once the terminal is handed back.
#[derive(Clone, Default)]
pub struct Diagnostics(Arc<Mutex<Vec<String>>>);

impl Diagnostics {
    pub fn lines(&self) -> Vec<String> {
        self.0.lock().unwrap().clone()
    }

    /// A line the tool itself wants recorded, rather than one read off the
    /// pipe. It lands beside the runtime's own, because to whoever opens F8
    /// they are the same thing: what happened that nobody was asked about.
    pub fn push(&self, line: String) {
        self.0.lock().unwrap().push(line);
    }
}

/// The real stdout and stderr, kept so the captured output can be printed for
/// real at the end.
pub struct RealStreams {
    stdout: libc::c_int,
    stderr: libc::c_int,
}

/// Routes fd 1 and fd 2 into a pipe drained into `Diagnostics`. The TUI draws
/// to /dev/tty instead, so the two can no longer collide.
pub fn capture_stdio() -> (Diagnostics, Option<RealStreams>) {
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
pub fn restore_stdio(saved: &RealStreams) {
    // SAFETY: both saved descriptors were produced by `dup` and are still open.
    unsafe {
        libc::dup2(saved.stdout, 1);
        libc::dup2(saved.stderr, 2);
    }
}

/// Takes over the terminal device, leaving stdout and stderr alone.
pub fn init_terminal() -> std::io::Result<Term> {
    let mut tty = File::options().read(true).write(true).open("/dev/tty")?;
    enable_raw_mode()?;
    execute!(tty, EnterAlternateScreen)?;
    Terminal::new(CrosstermBackend::new(tty))
}

pub fn restore_terminal() {
    if let Ok(mut tty) = File::options().read(true).write(true).open("/dev/tty") {
        let _ = execute!(tty, LeaveAlternateScreen);
    }
    let _ = disable_raw_mode();
}
