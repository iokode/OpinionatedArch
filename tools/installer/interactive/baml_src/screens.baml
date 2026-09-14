// What the interactive installer needs from the terminal.
//
// This is a small widget vocabulary, not one method per screen: which
// questions get asked, in what order, and what counts as a valid answer are
// decisions, and decisions live in BAML. The host only knows how to draw a
// selector, a text field, a multi-select and a review screen.
//
// The form asks through this port, and the installation that follows it
// reports through the library's own, `root.installer.Ui`. The host implements
// both, so one terminal shows the form and then the installation.
//
// A null answer means "the user went back".

/// A screen of the form, as the outline takes it. A screen is answered rather
/// than performed, so the three forms a phase is read in are one and the same.
function screen(name: string) -> root.installer.Phase {
    root.installer.Phase { to_do: name, doing: name, done: name }
}

interface Screens {
    /// The whole list, sent once so the host can show progress through it. The
    /// order matches the order they are asked in.
    function outline(self, phases: root.installer.Phase[]) -> void throws never
    /// The screen now asked, which is what the step list marks.
    function step(self, title: string) -> void throws never
    /// What the screen is doing while nothing is asked, in words: `Looking for
    /// a network`, `Scanning with wlan0`.
    function action(self, message: string) -> void throws never
    function error(self, message: string) -> void throws never
    /// Something worth recording and not worth interrupting for: it goes to the
    /// runtime log, which the operator opens when they want it, rather than in
    /// front of the question they are answering.
    function warn(self, message: string) -> void throws never

    /// A note beside the question: what the answer means, or how to tell one
    /// option from another. It is shown until the next answer is given, so a
    /// question with nothing worth saying simply does not ask for one.
    ///
    /// What it says is a decision, which is why it is written where the
    /// questions are and not where they are drawn.
    function tip(self, lines: string[]) -> void throws never

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
    function review(self, title: string, rows: SummaryRow[]) -> bool throws never
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

test "index_of_option restores a selection and falls back to the first row" {
    assert.equal(index_of_option(["wipe-all", "keep-homes"], "keep-homes"), 1);
    assert.equal(index_of_option(["wipe-all", "keep-homes"], "nonsense"), 0);
    assert.equal(index_of_option([], "anything"), 0)
}

// ---------------------------------------------------------------- host side

/// Wraps the closures the host passes at the entrypoint, for the reason
/// `root.common.HostShell` wraps its own: an interface does not cross a
/// generated SDK boundary.
class HostScreens {
    on_outline: (root.installer.Phase[]) -> void throws never,
    on_step: (string) -> void throws never,
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_warn: (string) -> void throws never,
    on_tip: (string[]) -> void throws never,
    on_choose: (string, string, string[], int) -> int? throws never,
    on_choose_many: (string, string, string[], string[], int, int) -> string[]? throws never,
    on_text: (string, string, string, bool) -> string? throws never,
    on_pick_package: (string, string, string) -> string? throws never,
    on_pick_file: (string, string, string) -> string? throws never,
    on_review: (string, SummaryRow[]) -> bool throws never,

    implements root.installer.Ui {
        function outline(self, phases: root.installer.Phase[]) -> void {
            self.on_outline(phases)
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
        function text(self, title: string, prompt: string, initial: string, secret: bool) -> string? {
            self.on_text(title, prompt, initial, secret)
        }
    }

    implements Screens {
        function outline(self, phases: root.installer.Phase[]) -> void {
            self.on_outline(phases)
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
        function warn(self, message: string) -> void {
            self.on_warn(message)
        }
        function tip(self, lines: string[]) -> void {
            self.on_tip(lines)
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
        function review(self, title: string, rows: SummaryRow[]) -> bool {
            self.on_review(title, rows)
        }
    }
}

// ---------------------------------------------------------------- test side

/// Replays scripted answers in order, and records what it was asked, for the
/// form and for the installation after it alike.
///
/// An answer of "<back>" makes the screen return null. For `choose` the answer
/// is the option text; for `choose_many`, comma-separated option texts; for a
/// picker, the path that would have been walked to; for `review`, "start" or
/// "back".
class ScriptedScreens {
    answers: string[],
    asked: string[],
    steps: string[],
    /// What each screen or phase said it was doing, in order.
    actions: string[],
    errors: string[],
    outline: string[],
    /// Everything sent to the runtime log rather than to the screen.
    warnings: string[],
    /// Every note offered beside a question, one entry each, in the order they
    /// were offered. A test can hold a screen to explaining what it asks.
    tips: string[],
    /// What each multi-select was allowed to take, as `min to max`. The bounds
    /// are a decision of the screen, so a test can hold them to it.
    limits: string[],

    /// The next scripted answer, or backing out when the script says nothing.
    ///
    /// A script that has run out keeps answering `<back>`, which is what a test
    /// wanting to step back scripts, so there is nothing to notice about the
    /// first few. What has to be noticed is the end state: the first screen has
    /// nowhere to go back to, so a form whose script ran out asks it again, and
    /// again, for ever — allocating on every turn until the machine running the
    /// test gives up. The ceiling is far above what any honest form test asks
    /// and is reached in milliseconds by one that spins.
    function next(self) -> string {
        if let scripted: string = self.answers.shift() {
            return scripted;
        }
        assert.is_true(self.asked.length() < 200);
        "<back>"
    }

    function record_outline(self, phases: root.installer.Phase[]) -> void {
        let names: string[] = [];
        for (let phase in phases) {
            names.push(phase.to_do);
        }
        self.outline = names
    }

    function answer_choice(self, title: string, options: string[]) -> int? {
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

    /// A picker answers with a path, exactly as the text field does. What it
    /// saves the operator is having to know the path, and a script knows it by
    /// construction.
    function answer_text(self, title: string) -> string? {
        self.asked.push(title);
        let answer = self.next();
        if (answer == "<back>") {
            return null;
        }
        answer
    }

    implements root.installer.Ui {
        function outline(self, phases: root.installer.Phase[]) -> void {
            self.record_outline(phases)
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
            self.answer_choice(title, options)
        }
        function text(self, title: string, prompt: string, initial: string, secret: bool) -> string? {
            self.answer_text(title)
        }
    }

    implements Screens {
        function outline(self, phases: root.installer.Phase[]) -> void {
            self.record_outline(phases)
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
        function warn(self, message: string) -> void {
            self.warnings.push(message)
        }
        function tip(self, lines: string[]) -> void {
            self.tips.push(lines.join(" "))
        }
        function choose(self, title: string, prompt: string, options: string[], current: int) -> int? {
            self.answer_choice(title, options)
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
        function text(self, title: string, prompt: string, initial: string, secret: bool) -> string? {
            self.answer_text(title)
        }
        function pick_package(self, title: string, prompt: string, start: string) -> string? {
            self.answer_text(title)
        }
        function pick_file(self, title: string, prompt: string, start: string) -> string? {
            self.answer_text(title)
        }
        function review(self, title: string, rows: SummaryRow[]) -> bool {
            self.asked.push(title);
            self.next() == "start"
        }
    }
}

function scripted(answers: string[]) -> ScriptedScreens {
    ScriptedScreens {
        answers: answers, asked: [], steps: [], actions: [], errors: [], outline: [],
        warnings: [], tips: [], limits: [],
    }
}
