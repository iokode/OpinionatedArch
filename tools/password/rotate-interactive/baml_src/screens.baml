// What the interactive rotation needs from the terminal: a masked field, a
// place to say why an answer is not taken, and the screen a run ends on.
// Which screens there are, in what order, and what counts as an answer are
// decisions, and decisions live in BAML; the host only draws them.
//
// A null answer means "the operator went back".

interface Screens {
    /// Every screen, in the order they are asked, sent once so the host can
    /// show where the operator is.
    function outline(self, names: string[]) -> void throws never
    /// The screen now asked, which is what the step list marks.
    function step(self, title: string) -> void throws never
    /// What the tool is doing while nothing is asked, in words.
    function action(self, message: string) -> void throws never
    /// Why the answer just given is not taken. The next field shows it.
    function error(self, message: string) -> void throws never
    /// A masked field: what is typed is never shown.
    function secret(self, title: string, prompt: string) -> string? throws never
    /// The screen the run ends on, held until the operator leaves it.
    function finish(self, title: string, lines: string[], failed: bool) -> void throws never
}

// ---------------------------------------------------------------- host side

/// Wraps the closures the host passes at the entrypoint, for the reason
/// `root.common.HostShell` wraps its own: an interface does not cross a
/// generated SDK boundary.
class HostScreens {
    on_outline: (string[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_secret: (string, string) -> string? throws never,
    on_finish: (string, string[], bool) -> void throws never,

    implements Screens {
        function outline(self, names: string[]) -> void {
            self.on_outline(names)
        }
        function step(self, title: string) -> void {
            self.on_step(title)
        }
        function action(self, message: string) -> void {
            self.on_action(message)
        }
        function error(self, message: string) -> void {
            self.on_error(message)
        }
        function secret(self, title: string, prompt: string) -> string? {
            self.on_secret(title, prompt)
        }
        function finish(self, title: string, lines: string[], failed: bool) -> void {
            self.on_finish(title, lines, failed)
        }
    }
}

// ---------------------------------------------------------------- test side

/// Replays scripted answers in order, and records what it was asked. An answer
/// of "<back>" makes the field return null.
class ScriptedScreens {
    answers: string[],
    asked: string[],
    steps: string[],
    actions: string[],
    errors: string[],
    outline: string[],
    /// What the run ended saying.
    finished: string[],
    failed: bool,

    /// The next scripted answer, or going back when the script says nothing.
    ///
    /// The first screen has nowhere to go back to, so a script that has run out
    /// would have it asked for ever. The ceiling is far above what any honest
    /// test asks and is reached in milliseconds by one that spins.
    function next(self) -> string {
        if let scripted: string = self.answers.shift() {
            return scripted;
        }
        assert.is_true(self.asked.length() < 200);
        "<back>"
    }

    implements Screens {
        function outline(self, names: string[]) -> void {
            self.outline = names
        }
        function step(self, title: string) -> void {
            self.steps.push(title)
        }
        function action(self, message: string) -> void {
            self.actions.push(message)
        }
        function error(self, message: string) -> void {
            self.errors.push(message)
        }
        function secret(self, title: string, prompt: string) -> string? {
            self.asked.push(title);
            let answer = self.next();
            if (answer == "<back>") {
                return null;
            }
            answer
        }
        function finish(self, title: string, lines: string[], failed: bool) -> void {
            self.finished = lines;
            self.failed = failed
        }
    }
}

function scripted(answers: string[]) -> ScriptedScreens {
    ScriptedScreens {
        answers: answers, asked: [], steps: [], actions: [], errors: [], outline: [],
        finished: [], failed: false,
    }
}
