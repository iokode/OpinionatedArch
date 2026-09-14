// oparch-installer.
//
// Installs from a configuration file, takes over no terminal and asks nothing.
// Progress is written as plain timestamped lines, so that a run can be logged
// and read by a test. The command is documented in
// `docs/tools/installer/unattended/000-command.md`.
//
// There is no host program. Nothing here needs a terminal interface, and output
// read while a command still runs is not needed either: a command's output is
// reported once it has finished, which is late and is still all of it. So
// `baml pack` turns this into the executable itself.

class Options {
    config: string,
    assets: string,
    error: string,
}

/// Where the project keeps the assets this tool reads, as
/// `docs/decisions/015-oparch-tools.md` names it.
function default_asset_dir() -> string {
    "/usr/share/opinionatedarch/assets"
}

function option_names() -> string[] {
    ["--config", "--assets"]
}

function usage() -> string {
    "Usage: oparch-installer --config <path> [--assets <path>]"
}

function parse_options(argv: string[]) -> Options {
    let options = Options { config: "", assets: default_asset_dir(), error: "" };

    //# the packaged executable is called with its own path and the name of the
    //# entry point before anything we declared; ours start at the first flag
    let index = 0;
    while (index < argv.length()) {
        if ((argv.at(index) ?? "").starts_with("-")) {
            break;
        }
        index = index + 1;
    }

    while (index < argv.length()) {
        let name = argv.at(index) ?? "";
        if (!option_names().includes(name)) {
            options.error = `Unknown option: ${name}`;
            return options;
        }
        let value = argv.at(index + 1);
        if (value == null) {
            options.error = `${name} needs a value.`;
            return options;
        }
        let given = value;
        if (given.starts_with("-")) {
            options.error = `${name} needs a value.`;
            return options;
        }
        if (name == "--config") {
            options.config = given;
        }
        if (name == "--assets") {
            options.assets = given;
        }
        index = index + 2;
    }

    if (options.config == "") {
        options.error = usage();
    }
    options
}

/// The stamp in front of a line: the milliseconds since the run started, right
/// aligned, so a log shows where the time went.
function timestamp(milliseconds: string) -> string {
    let width = 6;
    let pad = if (milliseconds.length() < width) { " ".repeat(width - milliseconds.length()) } else { "" };
    `[${pad}${milliseconds}ms]`
}

/// Reports the installation as plain lines. Nothing is asked: a question the
/// installation does ask is one the file should have answered, and saying so
/// is the answer, because there is nobody to give another one.
class PlainUi {
    started: baml.time.Instant,

    function line(self, text: string) -> void {
        let elapsed = (baml.time.Instant.now() - self.started)._nanoseconds / 1000000;
        baml.io.println(`${timestamp(`${elapsed}`)} ${text}`);
    }

    function unanswered(self, title: string) -> void {
        baml.io.eprintln(`error: the config file left '${title}' unanswered`);
    }

    implements root.installer.Ui {
        function outline(self, phases: root.installer.Phase[]) -> void {
        }
        function step(self, title: string) -> void {
            self.line(title)
        }
        function action(self, message: string) -> void {
            self.line(message)
        }
        function error(self, message: string) -> void {
            baml.io.eprintln(`error: ${message}`)
        }
        function choose(self, title: string, prompt: string, options: string[], current: int) -> int? {
            self.unanswered(title);
            null
        }
        function text(self, title: string, prompt: string, initial: string, secret: bool) -> string? {
            self.unanswered(title);
            null
        }
    }
}

/// A shell that says what it runs. A long operation's standard error is written
/// out once it has finished, which is where `pacstrap` and `mkinitcpio` say
/// what is worth knowing. What is fed to a command is never written, because
/// that is where the secrets are.
class ReportingShell {
    inner: root.common.Shell,
    ui: PlainUi,

    implements root.common.Shell {
        function capture(self, program: string, args: string[]) -> root.common.CommandResult {
            self.ui.line(`${program} ${args.join(" ")}`.trim());
            self.inner.capture(program, args)
        }
        function stream(self, program: string, args: string[]) -> root.common.CommandResult {
            self.ui.line(`${program} ${args.join(" ")}`.trim());
            let result = self.inner.stream(program, args);
            for (let said in root.common.nonempty_lines(result.stderr)) {
                self.ui.line(said);
            }
            result
        }
        function feed(self, program: string, args: string[], input: string) -> root.common.CommandResult {
            self.inner.feed(program, args, input)
        }
    }
}

/// What the run ended as, in one line, and the exit status that goes with it.
function report_end(summary: root.installer.InstallSummary) -> int {
    if (summary.exit_code == 0) {
        baml.io.println(`Bootstrapped ${summary.disk} successfully.`);
        return 0;
    }
    if (summary.exit_code == 130) {
        baml.io.eprintln("Nothing was installed.");
        return 1;
    }
    baml.io.eprintln(`Install failed on ${summary.disk} with exit code ${summary.exit_code}.`);
    1
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let options = parse_options(baml.sys.argv());
    if (options.error != "") {
        baml.io.eprintln(options.error);
        return baml.sys.exit(2);
    }

    let files = root.common.system_files();
    if let text: string = files.read(options.config) {
        let ui = PlainUi { started: baml.time.Instant.now() };
        let shell = ReportingShell { inner: root.common.system_shell(), ui: ui };
        let summary = run(
            shell,
            root.installer.AnnouncingFiles { inner: files, ui: ui },
            root.installer.AgeSecrets { shell: shell },
            ui,
            text,
            options.assets,
        );
        return baml.sys.exit(report_end(summary));
    }
    baml.io.eprintln(`cannot read ${options.config}`);
    baml.sys.exit(2)
}

// -------------------------------------------------------------------- tests

test "the configuration file is required, and the assets are the project's by default" {
    let options = parse_options(["/usr/bin/oparch-installer", "main", "--config", "/root/machine.yaml"]);

    assert.equal(options.error, "");
    assert.equal(options.config, "/root/machine.yaml");
    assert.equal(options.assets, "/usr/share/opinionatedarch/assets")
}

test "without a configuration file there is nothing to install from" {
    assert.equal(parse_options(["/usr/bin/oparch-installer", "main"]).error, usage());
    assert.equal(parse_options(["/usr/bin/oparch-installer", "main", "--assets", "/assets"]).error,
                 usage())
}

test "an option is refused when it is not one, or has no value" {
    assert.equal(parse_options(["oparch-installer", "main", "--verbose"]).error,
                 "Unknown option: --verbose");
    assert.equal(parse_options(["oparch-installer", "main", "--config"]).error,
                 "--config needs a value.");
    assert.equal(parse_options(["oparch-installer", "main", "--config", "--assets", "/a"]).error,
                 "--config needs a value.")
}

test "given assets are the ones read" {
    let options = parse_options(["oparch-installer", "main", "--assets", "/assets", "--config", "/c.yaml"]);
    assert.equal(options.assets, "/assets");
    assert.equal(options.config, "/c.yaml")
}

test "a timestamp is right aligned, and a long run widens it rather than cutting it" {
    assert.equal(timestamp("7"), "[     7ms]");
    assert.equal(timestamp("123456"), "[123456ms]");
    assert.equal(timestamp("1234567"), "[1234567ms]")
}

test "a run that ends is reported with the status it ended with" {
    assert.equal(report_end(root.installer.InstallSummary { disk: "/dev/sda", exit_code: 0 }), 0);
    assert.equal(report_end(root.installer.InstallSummary { disk: "", exit_code: 130 }), 1);
    assert.equal(report_end(root.installer.InstallSummary { disk: "/dev/sda", exit_code: 1 }), 1)
}
