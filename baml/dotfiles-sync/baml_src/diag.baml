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
