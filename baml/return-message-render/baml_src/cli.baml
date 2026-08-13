// The command line, as documented in
// `docs/tools/oparch-return-message-render/000-command.md`.
//
// The options are read from `argv` rather than declared as parameters of the
// entry point, because a packaged entry point makes every declared parameter
// mandatory, and all four of these are optional.

class Options {
    config: string,
    assets: string,
    output: string,
    /// The template package to compose. Empty means the project's own, inside
    /// `assets`. Like every path here it is a directory that already exists:
    /// obtaining one is the caller's job, as decided in
    /// `docs/tools/oparch-installer/003-input-sources.md`.
    template_package: string,
    /// The theme to compose it with. Empty means the project's own.
    theme: string,
    /// The logo file to compose in. Empty means the message carries no logo:
    /// the tool is given a file, and downloading one is the installer's job.
    logo: string,
    error: string,
}

function default_config_path() -> string {
    "/etc/opinionatedarch/return-message.yaml"
}

function default_asset_dir() -> string {
    "/usr/share/opinionatedarch/assets"
}

function default_output_dir() -> string {
    "/usr/share/plymouth/themes/opinionatedarch"
}

/// Where the images are built before any of them is installed.
function staging_dir() -> string {
    "/tmp/oparch-return-message"
}

function option_names() -> string[] {
    ["--config", "--assets", "--output", "--template-package", "--theme", "--logo"]
}

function default_options() -> Options {
    Options {
        config: default_config_path(),
        assets: default_asset_dir(),
        output: default_output_dir(),
        template_package: "",
        theme: "",
        logo: "",
        error: "",
    }
}

function parse_options(argv: string[]) -> Options {
    let options = default_options();

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
        if (name == "--output") {
            options.output = given;
        }
        if (name == "--template-package") {
            options.template_package = given;
        }
        if (name == "--theme") {
            options.theme = given;
        }
        if (name == "--logo") {
            options.logo = given;
        }
        index = index + 2;
    }
    options
}

test "with nothing given, every path is the documented default" {
    let options = parse_options(["/usr/bin/oparch-return-message-render", "main"]);

    assert.equal(options.error, "");
    assert.equal(options.config, "/etc/opinionatedarch/return-message.yaml");
    assert.equal(options.assets, "/usr/share/opinionatedarch/assets");
    assert.equal(options.output, "/usr/share/plymouth/themes/opinionatedarch");
    //# empty is what says "the project's own", resolved against the asset dir
    assert.equal(options.template_package, "");
    assert.equal(options.theme, "");
    assert.equal(options.logo, "")
}

test "every option is read past what the runner puts in front" {
    let options = parse_options([
        "/usr/bin/oparch-return-message-render", "main",
        "--config", "/home/ivan/message.yaml",
        "--assets", "/opt/assets",
        "--output", "/tmp/theme",
        "--template-package", "/home/ivan/andorra",
        "--theme", "/home/ivan/andorra-dark",
        "--logo", "/tmp/logo.png",
    ]);

    assert.equal(options.error, "");
    assert.equal(options.config, "/home/ivan/message.yaml");
    assert.equal(options.assets, "/opt/assets");
    assert.equal(options.output, "/tmp/theme");
    assert.equal(options.template_package, "/home/ivan/andorra");
    assert.equal(options.theme, "/home/ivan/andorra-dark");
    assert.equal(options.logo, "/tmp/logo.png")
}

test "an option nobody declared is refused rather than ignored" {
    assert.equal(parse_options(["/bin/x", "main", "--colour", "red"]).error, "Unknown option: --colour");
    assert.equal(parse_options(["/bin/x", "main", "-c", "x"]).error, "Unknown option: -c")
}

test "an option left without a value is refused" {
    assert.equal(parse_options(["/bin/x", "main", "--config"]).error, "--config needs a value.");
    assert.equal(parse_options(["/bin/x", "main", "--config", "--logo", "/l.png"]).error,
                 "--config needs a value.")
}
