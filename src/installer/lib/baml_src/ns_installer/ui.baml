// How the installation speaks to whoever runs it, and what it may ask them.
//
// The installation says what it is doing, and in one place asks a question:
// what to do when a logo will not download. Whether a terminal somebody is
// watching answers, or a file nobody is reading, is not this code's to know, so
// it speaks through this port and each interface implements it.
//
// A null answer means that nobody answered, which the installation treats as
// nobody having decided.

/// A step of what is being done, in the three forms it is read in: the list says
/// what will be done, and the log says what is being done while it is, and what
/// was done once it is over.
class Phase {
    to_do: string,
    doing: string,
    done: string,
}

interface Ui {
    /// The whole list, sent once so that progress through it can be shown. The
    /// order matches the order they run in.
    function outline(self, phases: Phase[]) -> void throws never
    /// The phase now under way, which is what the step list marks. Each one
    /// ends when the next begins.
    function step(self, title: string) -> void throws never
    /// What the phase is doing right now, in words rather than as the command
    /// line that does it: `Wiping the disk`, `Writing /etc/hostname`. Wording
    /// it is a decision, which is why it is said here and not drawn from what
    /// happens to be running.
    function action(self, message: string) -> void throws never
    function error(self, message: string) -> void throws never

    /// One of `options`, answered with the position of the one taken.
    function choose(self, title: string, prompt: string, options: string[], current: int) -> int? throws never
    /// A line of text, starting from `initial`. `secret` keeps what is typed
    /// from being shown.
    function text(self, title: string, prompt: string, initial: string, secret: bool) -> string? throws never
}

// ---------------------------------------------------------------- test side

/// Replays scripted answers in order, and records what it was asked.
///
/// An answer of "<back>" is no answer. For `choose` the answer is the option
/// text.
class ScriptedUi {
    answers: string[],
    asked: string[],
    steps: string[],
    /// What each phase said it was doing, in order.
    actions: string[],
    errors: string[],
    outline: string[],

    /// The next scripted answer, or no answer when the script says nothing.
    ///
    /// A script that has run out keeps answering `<back>`. What has to be
    /// noticed is a caller that asks again whenever it is not answered: it
    /// would ask for ever, allocating on every turn until the machine running
    /// the test gives up. The ceiling is far above what any honest test asks and
    /// is reached in milliseconds by one that spins.
    function next(self) -> string {
        if let scripted: string = self.answers.shift() {
            return scripted;
        }
        assert.is_true(self.asked.length() < 200);
        "<back>"
    }

    implements Ui {
        function outline(self, phases: Phase[]) -> void {
            let names: string[] = [];
            for (let phase in phases) {
                names.push(phase.to_do);
            }
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
    }
}

function scripted(answers: string[]) -> ScriptedUi {
    ScriptedUi { answers: answers, asked: [], steps: [], actions: [], errors: [], outline: [] }
}

/// A filesystem that says what it did, in the words of what it did.
///
/// The port underneath performs the operation; this only speaks. It exists
/// because files are touched here, through `baml.fs`, where nothing that runs
/// commands can see them go by and log them the way it logs the commands.
///
/// Only what changes the target is announced. Reading a file, or asking whether
/// one is there, changes nothing, and a log of every question asked is a log
/// nobody reads.
class AnnouncingFiles {
    inner: root.common.Files,
    ui: Ui,

    implements root.common.Files {
        function failure(self) -> string? { self.inner.failure() }
        function read(self, path: string) -> string? { self.inner.read(path) }
        function exists(self, path: string) -> bool { self.inner.exists(path) }
        function read_dir(self, path: string) -> root.common.DirEntry[]? {
            self.inner.read_dir(path)
        }

        function write(self, path: string, content: string) -> void {
            self.ui.action(`Write '${path}'`);
            self.inner.write(path, content);
        }
        function mkdir(self, path: string) -> void {
            self.ui.action(`Mkdir '${path}'`);
            self.inner.mkdir(path);
        }
        function symlink(self, path: string, points_to: string) -> void {
            self.ui.action(`Symlink '${path}' to '${points_to}'`);
            self.inner.symlink(path, points_to);
        }
        function chmod(self, path: string, mode: int) -> void {
            self.ui.action(`Chmod '${root.common.octal_mode(mode)}' on '${path}'`);
            self.inner.chmod(path, mode);
        }
    }
}
