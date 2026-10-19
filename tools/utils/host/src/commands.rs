//! Running the commands a tool is handed: the only thing a host does besides
//! drawing.

use std::process::Stdio;

use tokio::io::AsyncWriteExt;
use tokio::process::Command;

/// How a command ended. A tool puts it into the result type its own SDK gives
/// it, which this crate does not know.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Ran {
    pub exit_code: i64,
    pub stdout: String,
    pub stderr: String,
}

/// Runs a command that reads from standard input. The input is written and the
/// pipe closed, so a command waiting for end-of-input proceeds.
pub async fn run_fed(program: String, args: Vec<String>, input: String) -> Ran {
    let failed = |code: i64| Ran {
        exit_code: code,
        stdout: String::new(),
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
            exit_code: out.status.code().unwrap_or(-1) as i64,
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        },
        Err(_) => failed(-1),
    }
}

/// Runs a command for its output. No parsing, no redrawing: this is the path
/// for commands that merely produce data, and it must stay proportional to
/// running the command itself.
pub async fn run_captured(program: String, args: Vec<String>) -> Ran {
    match Command::new(&program).args(&args).output().await {
        Ok(out) => Ran {
            exit_code: out.status.code().unwrap_or(-1) as i64,
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        },
        Err(_) => Ran {
            exit_code: 127,
            stdout: String::new(),
            stderr: String::new(),
        },
    }
}
