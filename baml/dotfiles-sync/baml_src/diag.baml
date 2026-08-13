// Diagnostics collection. The tool validates the complete plan before it
// changes anything, so errors accumulate instead of aborting on the first one.

/// The file and line a declaration came from.
class SourceLoc {
    file: string,
    line: int,

    function label(self) -> string {
        `${self.file}:${self.line}`
    }
}

class Diagnostics {
    errors: string[],

    /// Records an error attributed to a source location.
    function at(self, loc: SourceLoc, message: string) -> null {
        let _ = self.errors.push(`${loc.label()}: ${message}`);
        null
    }

    /// Records an error with no source location.
    function report(self, message: string) -> null {
        let _ = self.errors.push(message);
        null
    }

    function has_errors(self) -> bool {
        self.errors.length() > 0
    }
}

function new_diagnostics() -> Diagnostics {
    Diagnostics { errors: [] }
}

/// Moves what the filesystem port recorded into the diagnostics.
///
/// The port keeps failures rather than returning them one by one, and keeps
/// only the first, which is the one that caused whatever followed. This tool
/// collects its errors in one place and prints them from one place, so the
/// port's is folded into that before anything is printed rather than being a
/// second thing to remember to look at.
///
/// It is called once. Calling it twice would report the same failure twice:
/// what the port holds, it holds until it is dropped.
function absorb_file_failure(files: root.common.Files, diag: Diagnostics) -> null {
    if let problem: string = files.failure() {
        diag.report(problem);
    }
    null
}

/// Records a command that failed: what was being done, and then what it said.
///
/// This tool has no log and no verbose level to put the second part behind, so
/// the message it prints is the only thing an operator ever sees. A caller with
/// somewhere else to show a command's output keeps its messages to the first
/// part; this one has nowhere, so it carries both.
///
/// Answers true when there was a failure to record.
function report_failed(diag: Diagnostics, result: root.common.CommandResult,
                       what: string) -> bool {
    let problem = root.common.must(result, what);
    if (problem == "") {
        return false;
    }
    let said = root.common.nonempty_lines(result.stderr);
    if (said.length() == 0) {
        diag.report(problem);
    } else {
        diag.report(problem + "\n" + said.join("\n"));
    }
    true
}
