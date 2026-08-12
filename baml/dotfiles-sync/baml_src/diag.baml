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
