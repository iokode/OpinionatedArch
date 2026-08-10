// What the installer needs from the terminal.
//
// This is a small widget vocabulary, not one method per screen: which
// questions get asked, in what order, and what counts as a valid answer are
// decisions, and decisions live in BAML. The host only knows how to draw a
// selector, a text field, a multi-select and a review screen.
//
// A null answer means "the user went back".

interface Ui {
    /// The whole list of screens, sent once so the host can show progress
    /// through the form. The order matches the order they are asked in.
    function outline(self, names: string[]) -> void throws never
    function step(self, title: string) -> void throws never
    function error(self, message: string) -> void throws never

    function choose(self, title: string, prompt: string, options: string[], current: int) -> int? throws never
    function choose_many(self, title: string, prompt: string, options: string[],
                         selected: string[], min: int, max: int) -> string[]? throws never
    function text(self, title: string, prompt: string, initial: string, secret: bool) -> string? throws never

    /// Walks the filesystem so that content on this machine is chosen rather
    /// than typed. `start` is where the walk begins, and is the location that
    /// was chosen before when there was one.
    ///
    /// A package is a directory or a `.tar`, and both are offered in the same
    /// list: which of the two it is, is a fact of the filesystem rather than of
    /// what the operator would have typed.
    function pick_package(self, title: string, prompt: string, start: string) -> string? throws never
    /// The same, for one file.
    function pick_file(self, title: string, prompt: string, start: string) -> string? throws never

    /// The review screen. True starts the installation, false goes back.
    function review(self, title: string, lines: string[]) -> bool throws never
}

/// Position of `value` in `options`, or 0 when it is not there. Used to
/// restore the highlighted row when the user walks back into a screen.
function index_of_option(options: string[], value: string) -> int {
    let index = 0;
    for (let option in options) {
        if (option == value) {
            return index;
        }
        index = index + 1;
    }
    0
}

// ---------------------------------------------------------------- host side

class HostUi {
    on_outline: (string[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_choose: (string, string, string[], int) -> int? throws never,
    on_choose_many: (string, string, string[], string[], int, int) -> string[]? throws never,
    on_text: (string, string, string, bool) -> string? throws never,
    on_pick_package: (string, string, string) -> string? throws never,
    on_pick_file: (string, string, string) -> string? throws never,
    on_review: (string, string[]) -> bool throws never,
    implements Ui {
        function outline(self, names: string[]) -> void {
            self.on_outline(names)
        }
        function step(self, title: string) -> void {
            self.on_step(title)
        }
        function error(self, message: string) -> void {
            self.on_error(message)
        }
        function choose(
            self,
            title: string,
            prompt: string,
            options: string[],
            current: int,
        ) -> int? {
            self.on_choose(title, prompt, options, current)
        }
        function choose_many(
            self,
            title: string,
            prompt: string,
            options: string[],
            selected: string[],
            min: int,
            max: int,
        ) -> string[]? {
            self.on_choose_many(title, prompt, options, selected, min, max)
        }
        function text(
            self,
            title: string,
            prompt: string,
            initial: string,
            secret: bool,
        ) -> string? {
            self.on_text(title, prompt, initial, secret)
        }
        function pick_package(self, title: string, prompt: string, start: string) -> string? {
            self.on_pick_package(title, prompt, start)
        }
        function pick_file(self, title: string, prompt: string, start: string) -> string? {
            self.on_pick_file(title, prompt, start)
        }
        function review(self, title: string, lines: string[]) -> bool {
            self.on_review(title, lines)
        }
    }
}

// ---------------------------------------------------------------- test side

/// Replays scripted answers in order, and records what it was asked.
///
/// An answer of "<back>" makes the screen return null. For `choose` the answer
/// is the option text; for `choose_many`, comma-separated option texts; for a
/// picker, the path that would have been walked to; for `review`, "start" or
/// "back".
class ScriptedUi {
    answers: string[],
    asked: string[],
    steps: string[],
    errors: string[],
    outline: string[],
    /// What each multi-select was allowed to take, as `min to max`. The bounds
    /// are a decision of the screen, so a test can hold them to it.
    limits: string[],

    function next(self) -> string {
        self.answers.shift() ?? "<back>"
    }

    implements Ui {
        function outline(self, names: string[]) -> void {
            self.outline = names
        }
        function step(self, title: string) -> void {
            self.steps.push(title)
        }
        function error(self, message: string) -> void {
            self.errors.push(message)
        }

        function choose(
            self,
            title: string,
            prompt: string,
            options: string[],
            current: int,
        ) -> int? {
            self.asked.push(title);
            let answer = self.next();
            if (answer == "<back>") {
                return null;
            }
            let index = 0;
            for (let option in options) {
                if (option == answer) {
                    return index;
                }
                index = index + 1;
            }
            null
        }

        function choose_many(
            self,
            title: string,
            prompt: string,
            options: string[],
            selected: string[],
            min: int,
            max: int,
        ) -> string[]? {
            self.asked.push(title);
            self.limits.push(`${min} to ${max}`);
            let answer = self.next();
            if (answer == "<back>") {
                return null;
            }
            answer
                .split(",")
                .map((v) -> {
                    v.trim()
                })
                .filter((v) -> {
                    v != ""
                })
        }

        function text(
            self,
            title: string,
            prompt: string,
            initial: string,
            secret: bool,
        ) -> string? {
            self.asked.push(title);
            let answer = self.next();
            if (answer == "<back>") {
                return null;
            }
            answer
        }

        /// A picker answers with a path, exactly as the text field did. What it
        /// saves the operator is having to know the path, and a script knows it
        /// by construction.
        function pick_package(self, title: string, prompt: string, start: string) -> string? {
            self.asked.push(title);
            let answer = self.next();
            if (answer == "<back>") {
                return null;
            }
            answer
        }
        function pick_file(self, title: string, prompt: string, start: string) -> string? {
            self.asked.push(title);
            let answer = self.next();
            if (answer == "<back>") {
                return null;
            }
            answer
        }

        function review(self, title: string, lines: string[]) -> bool {
            self.asked.push(title);
            self.next() == "start"
        }
    }
}

test "index_of_option restores a selection and falls back to the first row" {
    assert.equal(index_of_option(["wipe-all", "keep-homes"], "keep-homes"), 1);
    assert.equal(index_of_option(["wipe-all", "keep-homes"], "nonsense"), 0);
    assert.equal(index_of_option([], "anything"), 0)
}
