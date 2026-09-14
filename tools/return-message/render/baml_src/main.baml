// oparch-return-message-render.
//
// Builds the three images the boot splash shows and installs them into the
// theme, from a template package, the values that fill it and a theme. The
// command is documented in
// `docs/tools/return-message/render/000-command.md`, and what it runs is
// the return message's library.
//
// There is no host program. Nothing here needs a terminal interface or the
// output of a command while it is still running, which is all a host was ever
// for, so `baml pack` turns this into the executable itself.

/// What the command line asks the library for.
function render_request(options: Options) -> root.return_message.RenderRequest {
    root.return_message.RenderRequest {
        config: options.config,
        assets: options.assets,
        output: options.output,
        template_package: options.template_package,
        theme: options.theme,
        logo: options.logo,
    }
}

/// ENTRYPOINT. `baml pack main` turns this file into the executable.
function main() -> null {
    let options = parse_options(baml.sys.argv());
    if (options.error != "") {
        baml.io.eprintln(options.error);
        return baml.sys.exit(2);
    }

    let request = render_request(options);
    let files = root.common.system_files();
    let prepared = root.return_message.prepare(root.common.system_shell(), files, request);
    if (prepared.error != "") {
        baml.io.eprintln(prepared.error);
        return baml.sys.exit(1);
    }

    //# fontconfig looks in `$XDG_DATA_HOME/fonts`, so pointing it at the theme
    //# is what makes a font the theme carries the font that gets drawn with,
    //# instead of whatever fontconfig would have substituted in silence
    let drawing = root.common.with_env(root.common.system_shell(),
                                       { "XDG_DATA_HOME": prepared.theme.directory });
    let problem = root.return_message.draw_and_install(drawing, files, prepared, request);
    if (problem != "") {
        baml.io.eprintln(problem);
        return baml.sys.exit(1);
    }

    baml.io.println(`Wrote the return message into ${options.output}`);
    baml.sys.exit(0)
}

test "the command line is handed to the library as the request it names" {
    let request = render_request(parse_options([
        "/usr/bin/oparch-return-message-render", "main",
        "--config", "/home/ivan/message.yaml",
        "--theme", "/home/ivan/andorra-dark",
        "--logo", "/tmp/logo.png",
    ]));

    assert.equal(request.config, "/home/ivan/message.yaml");
    assert.equal(request.assets, "/usr/share/opinionatedarch/assets");
    assert.equal(request.output, "/usr/share/plymouth/themes/opinionatedarch");
    assert.equal(request.template_package, "");
    assert.equal(request.theme, "/home/ivan/andorra-dark");
    assert.equal(request.logo, "/tmp/logo.png")
}
