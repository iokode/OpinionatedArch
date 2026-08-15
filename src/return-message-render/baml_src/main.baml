// oparch-return-message-render.
//
// Builds the three images the boot splash shows and installs them into the
// theme, from a template package, the values that fill it and a theme. The
// command is documented in
// `docs/tools/oparch-return-message-render/000-command.md`.
//
// There is no host program. Nothing here needs a terminal interface or the
// output of a command while it is still running, which is all a host was ever
// for, so `baml pack` turns this into the executable itself.

function message_image() -> string {
    "return-message.png"
}

function prompt_image() -> string {
    "password-prompt.png"
}

function mask_image() -> string {
    "password-mask.png"
}

function script_file() -> string {
    "opinionatedarch.script"
}

/// The body of the Plymouth script, in the project's assets. It is read from
/// there and never from the output directory: the tool may be run again over
/// the script it wrote last time, and a prelude would stack on every run.
function script_body_path(assets: string) -> string {
    root.common.in_directory(assets, "plymouth/opinionatedarch/opinionatedarch.script")
}

/// The line asking for the secret that unlocks the machine. It names neither
/// the disk nor the passphrase, for the reason recorded in
/// `docs/decisions/010-preboot-ownership-message.md`: this screen is read by
/// whoever finds the machine, and it has nothing to tell them.
function prompt_text() -> string {
    "Enter your password"
}

/// Runs one drawing command, naming what it was for if it fails.
function draw(shell: root.common.Shell, args: string[], what: string) -> string {
    let result = shell.capture(magick(), args);
    if (result.exit_code != 0) {
        return `Drawing ${what} failed with exit code ${result.exit_code}.`;
    }
    ""
}

function staged(staging: string, name: string) -> string {
    root.common.in_directory(staging, name)
}

/// An image that was drawn, or what stopped it.
class DrawnContent {
    path: string,
    error: string,
}

/// The width of an image, which the panel around the prompt has to know.
function image_width(shell: root.common.Shell, path: string) -> int {
    let result = shell.capture("identify", ["-format", "%w", path]);
    if (result.exit_code != 0) {
        return 0;
    }
    root.common.parse_int(result.stdout.trim()) ?? 0
}

/// One language: its own name over its message, both at the width of the cell
/// the arrangement gave it.
function draw_content(shell: root.common.Shell, files: root.common.Files,
                      theme: root.return_message.Theme,
                      loaded: root.return_message.LoadedPackage,
                      values: map<string, string>, code: string, inner: int,
                      staging: string) -> DrawnContent {
    let heading_source = staged(staging, `heading-${code}.markup`);
    let heading_image = staged(staging, `heading-${code}.png`);
    files.write(heading_source,
                plain_markup(theme, theme.language_heading_style,
                             root.return_message.language_name(loaded.package, code), inner));

    let heading_style = root.return_message.style_named(theme, theme.language_heading_style);
    let drawn = draw(shell, text_args(theme, heading_source, inner, heading_style.align, heading_image),
                     `the name of ${code}`);
    if (drawn != "") {
        return DrawnContent { path: "", error: drawn };
    }

    let body_style = root.return_message.style_named(theme, theme.body_style);
    let markup = render_markup(theme, loaded.package, loaded.bodies.get(code) ?? "", values, inner);

    let pieces: string[] = [];
    let index = 0;
    for (let paragraph in paragraphs(markup)) {
        let source = staged(staging, `body-${code}-${index}.markup`);
        let image = staged(staging, `body-${code}-${index}.png`);
        files.write(source, wrap_style(theme, theme.body_style, paragraph, inner));
        let problem = draw(shell, text_args(theme, source, inner, body_style.align, image),
                           `the message in ${code}`);
        if (problem != "") {
            return DrawnContent { path: "", error: problem };
        }
        pieces.push(image);
        index = index + 1;
    }

    let body_image = staged(staging, `body-${code}.png`);
    let joined = draw(shell, joined_args(pieces, theme.spacing.paragraph_gap, true, body_image),
                      `the message in ${code}`);
    if (joined != "") {
        return DrawnContent { path: "", error: joined };
    }

    let content = staged(staging, `content-${code}.png`);
    let stacked = draw(shell,
        joined_args([heading_image, body_image], theme.spacing.language_heading_gap, true, content),
        `the block for ${code}`);
    if (stacked != "") {
        return DrawnContent { path: "", error: stacked };
    }
    DrawnContent { path: content, error: "" }
}

/// Every panel of a row is drawn to the height of the tallest content in it,
/// so two languages of different lengths do not leave one card short.
function draw_row(shell: root.common.Shell, files: root.common.Files,
                  theme: root.return_message.Theme, loaded: root.return_message.LoadedPackage,
                  values: map<string, string>, plan: RowPlan, number: int,
                  staging: string) -> DrawnContent {
    let contents: string[] = [];
    let tallest = 0;
    let index = 0;

    for (let code in plan.codes) {
        let width = plan.widths.at(index) ?? 0;
        let drawn = draw_content(shell, files, theme, loaded, values, code,
                                 inner_width(theme, width), staging);
        if (drawn.error != "") {
            return drawn;
        }
        contents.push(drawn.path);
        let height = image_height(shell, drawn.path);
        if (height > tallest) {
            tallest = height;
        }
        index = index + 1;
    }

    let height = tallest + 2 * panel_inset(theme.language_panel);
    let cells: string[] = [];
    index = 0;
    for (let code in plan.codes) {
        let cell = staged(staging, `cell-${code}.png`);
        let problem = draw(shell,
            panel_args(theme.language_panel, plan.widths.at(index) ?? 0, height,
                       contents.at(index) ?? "", cell),
            `the panel of ${code}`);
        if (problem != "") {
            return DrawnContent { path: "", error: problem };
        }
        cells.push(cell);
        index = index + 1;
    }

    let row = staged(staging, `row-${number}.png`);
    let joined = draw(shell, joined_args(cells, theme.canvas.column_gap, false, row), "a row");
    if (joined != "") {
        return DrawnContent { path: "", error: joined };
    }
    DrawnContent { path: row, error: "" }
}

/// The password prompt: one line, its panel fitted to it, placed across the
/// width so it and the message scale by the same factor.
function draw_prompt(shell: root.common.Shell, files: root.common.Files,
                     theme: root.return_message.Theme, staging: string) -> string {
    let inset = panel_inset(theme.password_prompt_panel);
    let inner = theme.canvas.width - 2 * inset;
    let source = staged(staging, "prompt.markup");
    let text = staged(staging, "prompt-text.png");
    files.write(source, plain_markup(theme, theme.password_prompt_style, prompt_text(), inner));

    let style = root.return_message.style_named(theme, theme.password_prompt_style);
    let drawn = draw(shell, fitted_text_args(theme, source, style.align, text), "the password prompt");
    if (drawn != "") {
        return drawn;
    }

    let width = image_width(shell, text) + 2 * inset;
    let height = image_height(shell, text) + 2 * inset;
    let panel = staged(staging, "prompt-panel.png");
    let framed = draw(shell, panel_args(theme.password_prompt_panel, width, height, text, panel),
                      "the password prompt");
    if (framed != "") {
        return framed;
    }

    draw(shell, place_args(theme, panel, height, style.align, staged(staging, prompt_image())),
         "the password prompt")
}

/// Builds the three images in the staging directory. The output directory is
/// not touched here: a message that cannot be drawn must leave the one the
/// machine already boots with alone.
function draw_all(shell: root.common.Shell, files: root.common.Files,
                  theme: root.return_message.Theme, loaded: root.return_message.LoadedPackage,
                  message: root.return_message.ReturnMessageConfig,
                  logo: string, staging: string) -> string {
    files.mkdir(staging);

    let rows: string[] = [];
    let number = 0;
    for (let plan in plan_rows(theme, message.languages)) {
        number = number + 1;
        let drawn = draw_row(shell, files, theme, loaded, message.fields, plan, number, staging);
        if (drawn.error != "") {
            return drawn.error;
        }
        rows.push(drawn.path);
    }

    //# with a logo the arrangement is composed first and the logo put beside
    //# it, so the message is one image either way
    let composed = if (logo == "") {
        staged(staging, message_image())
    } else {
        staged(staging, "message.png")
    };
    let joined = draw(shell, joined_args(rows, theme.canvas.row_gap, true, composed), "the message");
    if (joined != "") {
        return joined;
    }

    if (logo != "") {
        let fitted = staged(staging, "logo.png");
        let resized = draw(shell, logo_args(theme, logo, fitted), "the logo");
        if (resized != "") {
            return resized;
        }
        let order = if (((theme.logo)?.position ?? "above") == "below") {
            [composed, fitted]
        } else {
            [fitted, composed]
        };
        let placed = draw(shell,
            joined_args(order, (theme.logo)?.gap ?? 0, true, staged(staging, message_image())),
            "the message with its logo");
        if (placed != "") {
            return placed;
        }
    }

    let prompt = draw_prompt(shell, files, theme, staging);
    if (prompt != "") {
        return prompt;
    }

    draw(shell, mask_args(theme, staged(staging, mask_image())), "the password mask")
}

/// Puts the finished images where the splash reads them. Copying is the last
/// thing that happens, so the three arrive together or not at all.
function install_images(shell: root.common.Shell, files: root.common.Files,
                        theme: root.return_message.Theme, staging: string,
                        output: string) -> string {
    files.mkdir(output);
    for (let name in [message_image(), prompt_image(), mask_image()]) {
        let result = shell.capture("cp", [staged(staging, name), root.common.in_directory(output, name)]);
        if (result.exit_code != 0) {
            return `Installing ${name} failed with exit code ${result.exit_code}.`;
        }
    }

    //# the background is the theme's and the splash paints it, so it travels
    //# beside the images rather than into them
    if (theme.screen.background_image != "") {
        let source = root.common.in_directory(theme.directory, theme.screen.background_image);
        let result = shell.capture("cp", [source, root.common.in_directory(output, "background.png")]);
        if (result.exit_code != 0) {
            return `Installing the background failed with exit code ${result.exit_code}.`;
        }
    }
    ""
}

/// The value of one hexadecimal digit.
function hex_digit(character: string) -> int {
    let value = "0123456789abcdefABCDEF".chars().index_of(character) ?? 0;
    if (value > 15) {
        return value - 6;
    }
    value
}

/// One component of a `#RRGGBB` colour, as the fraction between 0 and 1 the
/// splash paints with. An alpha component is refused on this key, so the six
/// digits are always there to read.
function color_component(color: string, index: int) -> float {
    let at = 1 + 2 * index;
    (16 * hex_digit(color.substring(at, at + 1)) + hex_digit(color.substring(at + 1, at + 2)))
        * 1.0 / 255.0
}

/// The seven values the body of the Plymouth script expects above it, as
/// literals. Every one of them is a number: a theme may be fetched from a URL,
/// and a name of its own reaching the script would make the theme a program.
function script_prelude(screen: root.return_message.ScreenValues) -> string {
    let has_background_image = if (screen.background_image != "") { 1 } else { 0 };
    `background_red = ${color_component(screen.background_color, 0)};` + "\n"
        + `background_green = ${color_component(screen.background_color, 1)};` + "\n"
        + `background_blue = ${color_component(screen.background_color, 2)};` + "\n"
        + `has_background_image = ${has_background_image};` + "\n"
        + `fit = ${screen.fit};` + "\n"
        + `message_gap = ${screen.message_gap};` + "\n"
        + `mask_gap = ${screen.mask_gap};` + "\n"
        + "\n"
}

/// Writes the script the splash runs: the prelude, and then the body it was
/// given. This is the last thing installed, so the values and the images that
/// were composed for them arrive together.
function install_script(files: root.common.Files, screen: root.return_message.ScreenValues,
                        body: string, output: string) -> string {
    files.write(root.common.in_directory(output, script_file()), script_prelude(screen) + body);
    files.failure() ?? ""
}

/// Everything read and checked, before anything is drawn.
class Prepared {
    message: root.return_message.ReturnMessageConfig,
    loaded: root.return_message.LoadedPackage,
    theme: root.return_message.Theme,
    error: string,
}

/// The template package to compose: the one given, or the project's own.
function package_directory(options: Options) -> string {
    if (options.template_package == "") {
        root.return_message.default_package_directory(options.assets)
    } else {
        options.template_package
    }
}

/// The theme to compose it with: the one given, or the project's own.
function theme_directory(options: Options) -> string {
    if (options.theme == "") {
        root.return_message.default_theme_directory(options.assets)
    } else {
        options.theme
    }
}

test "a package and a theme default to the project's own, inside the asset dir" {
    let options = default_options();
    options.assets = "/assets";
    assert.equal(package_directory(options), "/assets/return-message");
    assert.equal(theme_directory(options), "/assets/return-message-theme");

    options.template_package = "/home/ivan/andorra";
    options.theme = "/home/ivan/andorra-dark";
    assert.equal(package_directory(options), "/home/ivan/andorra");
    assert.equal(theme_directory(options), "/home/ivan/andorra-dark")
}

/// Reads the values, the package and the theme, and checks each against the
/// others. Nothing is drawn here, and that is the point: a theme may carry the
/// font its icons are drawn with, and fontconfig only finds it if the commands
/// that draw are told where the theme is. Which theme that is, is what this
/// answers, so drawing cannot start until it has.
function prepare(shell: root.common.Shell, files: root.common.Files, options: Options) -> Prepared {
    let nothing = Prepared {
        message: root.return_message.empty_return_message(),
        loaded: root.return_message.LoadedPackage {
            package: root.return_message.empty_package(), bodies: {}, error: "",
        },
        theme: root.return_message.empty_theme(),
        error: "",
    };

    let text = files.read(options.config);
    if (text == null) {
        nothing.error = `Cannot read the return message configuration: ${options.config}`;
        return nothing;
    }

    let parsed = root.return_message.parse_values_file(text);
    if (parsed.error != "") {
        nothing.error = parsed.error;
        return nothing;
    }

    //# both are directories that are already there: this tool is given them,
    //# and where they came from is the caller's business
    let loaded = root.return_message.load_package(files, package_directory(options));
    if (loaded.error != "") {
        nothing.error = loaded.error;
        return nothing;
    }

    let themed = root.return_message.load_theme(shell, files, theme_directory(options));
    if (themed.error != "") {
        nothing.error = themed.error;
        return nothing;
    }

    let prepared = Prepared {
        message: parsed.message, loaded: loaded, theme: themed.theme, error: "",
    };

    let problem = root.return_message.check_values(loaded.package, parsed.message, "");
    if (problem != "") {
        prepared.error = problem;
        return prepared;
    }
    let arranged = root.return_message.check_language_count(themed.theme, parsed.message);
    if (arranged != "") {
        prepared.error = arranged;
        return prepared;
    }

    if (options.logo != "") {
        if (themed.theme.logo == null) {
            prepared.error = "The theme draws no logo, and one was given.";
            return prepared;
        }
        if (!files.exists(options.logo)) {
            prepared.error = `The logo is not there: ${options.logo}`;
            return prepared;
        }
    }
    prepared
}

/// Draws what `prepare` read, and installs it if every step worked.
function draw_and_install(shell: root.common.Shell, files: root.common.Files,
                          prepared: Prepared, options: Options) -> string {
    let drawn = draw_all(shell, files, prepared.theme, prepared.loaded, prepared.message,
                         options.logo, staging_dir());
    if (drawn != "") {
        return drawn;
    }

    if let failed: string = files.failure() {
        return failed;
    }

    //# read before anything is installed, so a body that is not there stops the
    //# tool while the machine still boots with what it had
    let path = script_body_path(options.assets);
    let body = files.read(path);
    if (body == null) {
        return `Cannot read the Plymouth script: ${path}`;
    }

    let installed = install_images(shell, files, prepared.theme, staging_dir(), options.output);
    if (installed != "") {
        return installed;
    }
    install_script(files, prepared.theme.screen, body, options.output)
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let options = parse_options(baml.sys.argv());
    if (options.error != "") {
        baml.io.eprintln(options.error);
        return baml.sys.exit(2);
    }

    let files = root.common.system_files();
    let prepared = prepare(root.common.system_shell(), files, options);
    if (prepared.error != "") {
        baml.io.eprintln(prepared.error);
        return baml.sys.exit(1);
    }

    //# fontconfig looks in `$XDG_DATA_HOME/fonts`, so pointing it at the theme
    //# is what makes a font the theme carries the font that gets drawn with,
    //# instead of whatever fontconfig would have substituted in silence
    let drawing = root.common.with_env(root.common.system_shell(),
                                       { "XDG_DATA_HOME": prepared.theme.directory });
    let problem = draw_and_install(drawing, files, prepared, options);
    if (problem != "") {
        baml.io.eprintln(problem);
        return baml.sys.exit(1);
    }

    baml.io.println(`Wrote the return message into ${options.output}`);
    baml.sys.exit(0)
}

// -------------------------------------------------------------------- tests

/// Stands in for the body of the Plymouth script, which the assets carry and
/// this tool only ever copies.
function test_script_body() -> string {
    "Window.SetBackgroundTopColor(background_red, background_green, background_blue);\n"
}

/// A machine with the project's package and theme installed, and a values file
/// on it.
function test_files(values: string) -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/assets/plymouth/opinionatedarch/opinionatedarch.script", test_script_body());
    files.write("/assets/return-message/manifest.yaml", root.return_message.sample_manifest());
    files.write("/assets/return-message/es.txt", "Pertenece a {{owner_name}}.\n\nLlame a {{phone}}.\n");
    files.write("/assets/return-message/ca.txt", "Pertany a {{owner_name}}.\n");
    files.write("/assets/return-message-theme/manifest.yaml", root.return_message.sample_theme());
    files.write("/etc/opinionatedarch/return-message.yaml", values);
    files
}

/// Content is 600 tall and the prompt 900 by 120, so the panels around them
/// have a size a test can assert.
function test_shell() -> root.common.RecordingShell {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    for (let code in ["es", "ca"]) {
        let _ = shell.replies.set(
            `identify -format %h /tmp/oparch-return-message/content-${code}.png`, "600");
    }
    let _ = shell.replies.set("identify -format %h /tmp/oparch-return-message/prompt-text.png", "120");
    let _ = shell.replies.set("identify -format %w /tmp/oparch-return-message/prompt-text.png", "900");
    shell
}

function test_options() -> Options {
    let options = default_options();
    options.assets = "/assets";
    options
}

/// The two steps the tool takes, for a test that cares about the result rather
/// than about which of them produced it.
function rendered(shell: root.common.RecordingShell, files: root.common.RecordingFiles,
                  options: Options) -> string {
    let prepared = prepare(shell, files, options);
    if (prepared.error != "") {
        return prepared.error;
    }
    draw_and_install(shell, files, prepared, options)
}

function one_language_values() -> string {
    "languages:\n  - \"es\"\nfields:\n  owner_name: \"Ivan\"\n  phone: \"+376 000 000\"\n"
}

test "the message is drawn from the theme and installed where the splash reads it" {
    let files = test_files(one_language_values());
    let shell = test_shell();

    assert.equal(rendered(shell, files, test_options()), "");

    //# the markup is this tool's, with the value in the style its kind asks for
    let markup = files.written.get("/tmp/oparch-return-message/body-es-1.markup") ?? "";
    assert.is_true(markup.includes("+376 000 000"));
    assert.is_true(markup.includes("<span font_family=\"Noto Sans\""));

    //# the panel is the content plus the theme's padding and border, both sides
    assert.is_true(shell.commands.join("\n").includes("-size 3840x736"));

    assert.is_true(shell.commands.includes(
        "cp /tmp/oparch-return-message/return-message.png"
            + " /usr/share/plymouth/themes/opinionatedarch/return-message.png"))
}

test "each paragraph is drawn on its own and joined by the theme's gap" {
    let files = test_files(one_language_values());
    let shell = test_shell();

    assert.equal(rendered(shell, files, test_options()), "");
    assert.is_true(files.written.get("/tmp/oparch-return-message/body-es-0.markup") != null);
    assert.is_true(files.written.get("/tmp/oparch-return-message/body-es-1.markup") != null);
    assert.is_true(shell.commands.join("\n").includes("-splice 0x64"))
}

test "a number of languages the theme does not arrange is refused before drawing" {
    let files = test_files("languages:\n  - \"es\"\n  - \"ca\"\nfields:\n  owner_name: \"Ivan\"\n");
    //# a theme that lays out one language and nothing else
    files.write("/assets/return-message-theme/manifest.yaml",
                root.return_message.sample_theme()
                    .replace("  \"2\": [[1], [1]]\n", "")
                    .replace("  \"4\": [[1, 1], [1, 1]]\n", ""));
    let shell = test_shell();

    assert.equal(rendered(shell, files, test_options()),
                 "The theme lays out 1 languages, and 2 were selected.");
    assert.equal(shell.commands, [])
}

test "a values file that is not there stops before anything is drawn" {
    let options = test_options();
    options.config = "/etc/opinionatedarch/nowhere.yaml";
    let shell = test_shell();

    assert.equal(rendered(shell, test_files(one_language_values()), options),
                 "Cannot read the return message configuration: /etc/opinionatedarch/nowhere.yaml");
    assert.equal(shell.commands, [])
}

test "a drawing that fails installs nothing" {
    let files = test_files(one_language_values());
    let shell = test_shell();
    let theme = root.return_message.parse_theme(root.return_message.sample_theme(),
                                                "/assets/return-message-theme").theme;
    let _ = shell.exit_codes.set(
        `magick ${mask_args(theme, "/tmp/oparch-return-message/password-mask.png").join(" ")}`, 1);

    assert.equal(rendered(shell, files, test_options()),
                 "Drawing the password mask failed with exit code 1.");
    assert.is_true(!shell.commands.join("\n").includes("cp "))
}

test "a logo is refused when the theme draws none" {
    let files = test_files(one_language_values());
    files.write("/assets/return-message-theme/manifest.yaml",
                root.return_message.sample_theme()
                    .replace("logo: { width: 1200, gap: 120, position: above }\n", ""));
    files.write("/tmp/logo.png", "");
    let options = test_options();
    options.logo = "/tmp/logo.png";

    assert.equal(rendered(test_shell(), files, options), "The theme draws no logo, and one was given.")
}

test "a logo the theme does draw is fitted to its box and put where it says" {
    let files = test_files(one_language_values());
    files.write("/tmp/logo.png", "");
    let options = test_options();
    options.logo = "/tmp/logo.png";
    let shell = test_shell();

    assert.equal(rendered(shell, files, options), "");
    assert.is_true(shell.commands.join("\n").includes("-resize 1200x"));
    //# above, so the logo comes first
    assert.is_true(shell.commands.join("\n").includes(
        "magick /tmp/oparch-return-message/logo.png ( /tmp/oparch-return-message/message.png"))
}

test "a file that could not be written is noticed before anything is installed" {
    let files = test_files(one_language_values());
    files.fails_with = "cannot write /tmp/oparch-return-message/body-es-0.markup: read-only";
    let shell = test_shell();

    assert.equal(rendered(shell, files, test_options()),
                 "cannot write /tmp/oparch-return-message/body-es-0.markup: read-only");
    assert.is_true(!shell.commands.join("\n").includes("cp "))
}

function installed_script() -> string {
    "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script"
}

test "the script the splash runs is the theme's numbers and then the body" {
    let files = test_files(one_language_values());

    assert.equal(rendered(test_shell(), files, test_options()), "");

    //# the panel colour of the sample theme, #12202C, as fractions
    assert.equal(files.written.get(installed_script()),
                 "background_red = 0.07058823529411765;\n"
                     + "background_green = 0.12549019607843137;\n"
                     + "background_blue = 0.17254901960784313;\n"
                     + "has_background_image = 0;\n"
                     + "fit = 0.85;\n"
                     + "message_gap = 120;\n"
                     + "mask_gap = 48;\n"
                     + "\n"
                     + test_script_body())
}

test "a colour becomes three fractions of one" {
    assert.equal(color_component("#000000", 0), 0.0);
    assert.equal(color_component("#FFFFFF", 2), 1.0);
    //# the lower case of a digit is the same digit
    assert.equal(color_component("#0B1620", 0), color_component("#0b1620", 0));
    assert.equal(color_component("#0B1620", 1), 22.0 / 255.0);
    assert.equal(color_component("#0B1620", 2), 32.0 / 255.0)
}

test "running the tool again writes the same script, not a second prelude" {
    let files = test_files(one_language_values());

    assert.equal(rendered(test_shell(), files, test_options()), "");
    let once = files.written.get(installed_script()) ?? "";

    assert.equal(rendered(test_shell(), files, test_options()), "");
    assert.equal(files.written.get(installed_script()), once)
}

test "a background image the theme carries is announced to the script and travels with it" {
    let files = test_files(one_language_values());
    files.write("/assets/return-message-theme/manifest.yaml",
                root.return_message.sample_theme()
                    .replace("screen: { background_palette: panel,",
                             "screen: { background_palette: panel, background_image: \"art.png\","));
    files.write("/assets/return-message-theme/art.png", "");
    let shell = test_shell();

    assert.equal(rendered(shell, files, test_options()), "");
    assert.is_true((files.written.get(installed_script()) ?? "").includes("has_background_image = 1;\n"));
    assert.is_true(shell.commands.includes(
        "cp /assets/return-message-theme/art.png"
            + " /usr/share/plymouth/themes/opinionatedarch/background.png"))
}

test "a drawing that fails leaves the script the machine already boots with alone" {
    let files = test_files(one_language_values());
    let shell = test_shell();
    let theme = root.return_message.parse_theme(root.return_message.sample_theme(),
                                                "/assets/return-message-theme").theme;
    let _ = shell.exit_codes.set(
        `magick ${mask_args(theme, "/tmp/oparch-return-message/password-mask.png").join(" ")}`, 1);

    assert.equal(rendered(shell, files, test_options()),
                 "Drawing the password mask failed with exit code 1.");
    assert.is_true(files.written.get(installed_script()) == null)
}

test "assets without the body of the script install nothing at all" {
    let files = test_files(one_language_values());
    let options = test_options();
    options.assets = "/elsewhere";
    files.write("/elsewhere/return-message/manifest.yaml", root.return_message.sample_manifest());
    files.write("/elsewhere/return-message/es.txt", "Pertenece a {{owner_name}}.\n");
    files.write("/elsewhere/return-message/ca.txt", "Pertany a {{owner_name}}.\n");
    files.write("/elsewhere/return-message-theme/manifest.yaml", root.return_message.sample_theme());
    let shell = test_shell();

    assert.equal(rendered(shell, files, options),
                 "Cannot read the Plymouth script:"
                     + " /elsewhere/plymouth/opinionatedarch/opinionatedarch.script");
    assert.is_true(!shell.commands.join("\n").includes("cp "));
    assert.is_true(files.written.get(installed_script()) == null)
}
