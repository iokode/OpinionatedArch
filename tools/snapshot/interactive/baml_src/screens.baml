// What browsing the snapshots needs from the terminal: a list to choose from,
// a field to type into, a question answered yes or no, and a box saying how an
// operation went. Which screens there are, what they offer and what counts as
// an answer are decisions, and decisions live in BAML; the host only draws
// them.

/// What was done with a list.
class Choice {
    /// The option chosen, by its place among the options; null when the
    /// operator went back or is leaving.
    index: int?,
    /// The operator asked to leave the tool.
    leave: bool,
}

/// What was done with a field.
class Typed {
    /// What was typed; null when the operator went back or is leaving.
    value: string?,
    /// The operator asked to leave the tool.
    leave: bool,
}

interface Screens {
    /// What the tool is doing while nothing is asked, in words.
    function action(self, message: string) -> void throws never
    /// Why the answer just given is not taken, or what stopped a screen from
    /// showing what it shows. The next list or field shows it.
    function error(self, message: string) -> void throws never
    /// A list, which typing filters. `can_go_back` is false on the screen that
    /// has nothing behind it.
    function choose(self, title: string, prompt: string, options: string[], can_go_back: bool) -> Choice throws never
    /// A field, holding `initial` to begin with.
    function text(self, title: string, prompt: string, initial: string) -> Typed throws never
    /// A question over the screen, answered yes or no.
    function confirm(self, title: string, lines: string[]) -> bool throws never
    /// How an operation went, over the screen until the operator closes it.
    function notice(self, title: string, lines: string[]) -> void throws never
}

// ---------------------------------------------------------------- host side

/// Wraps the closures the host passes at the entrypoint, for the reason
/// `root.common.HostShell` wraps its own: an interface does not cross a
/// generated SDK boundary.
class HostScreens {
    on_action: (string) -> void throws never,
    on_error: (string) -> void throws never,
    on_choose: (string, string, string[], bool) -> Choice throws never,
    on_text: (string, string, string) -> Typed throws never,
    on_confirm: (string, string[]) -> bool throws never,
    on_notice: (string, string[]) -> void throws never,

    implements Screens {
        function action(self, message: string) -> void {
            self.on_action(message)
        }
        function error(self, message: string) -> void {
            self.on_error(message)
        }
        function choose(self, title: string, prompt: string, options: string[], can_go_back: bool) -> Choice {
            self.on_choose(title, prompt, options, can_go_back)
        }
        function text(self, title: string, prompt: string, initial: string) -> Typed {
            self.on_text(title, prompt, initial)
        }
        function confirm(self, title: string, lines: string[]) -> bool {
            self.on_confirm(title, lines)
        }
        function notice(self, title: string, lines: string[]) -> void {
            self.on_notice(title, lines)
        }
    }
}

// ---------------------------------------------------------------- test side

/// Replays scripted answers in order, and records what it was asked and shown.
///
/// An answer of "<back>" goes back and "<leave>" leaves. On a list, any other
/// answer chooses the option it is, or else the first option that contains it;
/// in a field, it is what is typed; to a question, "yes" answers yes and
/// anything else no.
class ScriptedScreens {
    answers: string[],
    /// The title of every list and field, in the order they were asked.
    asked: string[],
    /// The options each list offered the last time it was asked, by title.
    shown: map<string, string[]>,
    /// What each field held when it was asked, in order.
    initials: string[],
    /// Whether each list could go back, in order.
    backs: bool[],
    actions: string[],
    errors: string[],
    /// The title of every question, and then of every notice, with its lines.
    confirmed: string[],
    noticed: string[],

    /// The next scripted answer, or leaving when the script says nothing.
    ///
    /// The list of snapshots is asked again after everything, so a script that
    /// has run out leaves rather than having it asked for ever. The ceiling is
    /// far above what any honest test asks and is reached in milliseconds by
    /// one that spins.
    function next(self) -> string {
        if let scripted: string = self.answers.shift() {
            return scripted;
        }
        assert.is_true(self.asked.length() < 200);
        "<leave>"
    }

    implements Screens {
        function action(self, message: string) -> void {
            self.actions.push(message)
        }
        function error(self, message: string) -> void {
            self.errors.push(message)
        }
        function choose(self, title: string, prompt: string, options: string[], can_go_back: bool) -> Choice {
            self.asked.push(title);
            let _ = self.shown.set(title, options);
            self.backs.push(can_go_back);
            let answer = self.next();
            if (answer == "<leave>") {
                return Choice { index: null, leave: true };
            }
            if (answer == "<back>") {
                return Choice { index: null, leave: false };
            }
            let index = 0;
            for (let option in options) {
                if (option == answer) {
                    return Choice { index: index, leave: false };
                }
                index = index + 1;
            }
            index = 0;
            for (let option in options) {
                if (option.includes(answer)) {
                    return Choice { index: index, leave: false };
                }
                index = index + 1;
            }
            //# a script choosing what the list does not offer is a broken test
            assert.equal(options, [answer]);
            Choice { index: null, leave: true }
        }
        function text(self, title: string, prompt: string, initial: string) -> Typed {
            self.asked.push(title);
            self.initials.push(initial);
            let answer = self.next();
            if (answer == "<leave>") {
                return Typed { value: null, leave: true };
            }
            if (answer == "<back>") {
                return Typed { value: null, leave: false };
            }
            Typed { value: answer, leave: false }
        }
        function confirm(self, title: string, lines: string[]) -> bool {
            self.confirmed.push(title);
            self.confirmed = self.confirmed.concat(lines);
            self.next() == "yes"
        }
        function notice(self, title: string, lines: string[]) -> void {
            self.noticed.push(title);
            self.noticed = self.noticed.concat(lines)
        }
    }
}

function scripted(answers: string[]) -> ScriptedScreens {
    ScriptedScreens {
        answers: answers, asked: [], shown: {}, initials: [], backs: [], actions: [], errors: [],
        confirmed: [], noticed: [],
    }
}
