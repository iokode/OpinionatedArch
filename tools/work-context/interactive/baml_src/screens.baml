// What the interactive tool for work contexts needs from the terminal: a list
// to choose from, a text field, a place to say why an answer is not taken, and
// the screen a run ends on. Which screens there are, in what order, and what
// counts as an answer are decisions, and decisions live in BAML; the host only
// draws them.
//
// A null answer means "the operator went back".

interface Screens {
    /// Every screen of what is being done, in the order they are asked, so the
    /// host can show where the operator is.
    function outline(self, names: string[]) -> void throws never
    /// The screen now asked, which is what the step list marks.
    function step(self, title: string) -> void throws never
    /// What the tool is doing while nothing is asked, in words.
    function action(self, message: string) -> void throws never
    /// Why the answer just given is not taken. The next question shows it.
    function error(self, message: string) -> void throws never
    /// A list to choose one entry from. `current` is the entry highlighted first.
    function choose(self, title: string, prompt: string, options: string[], current: int) -> int? throws never
    /// A text field, starting with `initial`.
    function text(self, title: string, prompt: string, initial: string) -> string? throws never
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
    on_choose: (string, string, string[], int) -> int? throws never,
    on_text: (string, string, string) -> string? throws never,
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
        function choose(self, title: string, prompt: string, options: string[], current: int) -> int? {
            self.on_choose(title, prompt, options, current)
        }
        function text(self, title: string, prompt: string, initial: string) -> string? {
            self.on_text(title, prompt, initial)
        }
        function finish(self, title: string, lines: string[], failed: bool) -> void {
            self.on_finish(title, lines, failed)
        }
    }
}

// ---------------------------------------------------------------- test side

/// Replays scripted answers in order, and records what it was asked. For a
/// list, the answer is the text of the entry chosen; an entry that is not there
/// answers as going back. An answer of "<back>" makes the screen return null.
class ScriptedScreens {
    answers: string[],
    asked: string[],
    /// What each screen said above its question, in order.
    prompts: string[],
    /// The entries of each list offered, joined with ", ", in order; an empty
    /// entry for a text field.
    options: string[],
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
        function choose(self, title: string, prompt: string, options: string[], current: int) -> int? {
            self.asked.push(title);
            self.prompts.push(prompt);
            self.options.push(options.join(", "));
            let answer = self.next();
            let index = 0;
            for (let option in options) {
                if (option == answer) {
                    return index;
                }
                index = index + 1;
            }
            null
        }
        function text(self, title: string, prompt: string, initial: string) -> string? {
            self.asked.push(title);
            self.prompts.push(prompt);
            self.options.push("");
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
        answers: answers, asked: [], prompts: [], options: [], steps: [], actions: [], errors: [],
        outline: [], finished: [], failed: false,
    }
}
