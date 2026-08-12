// The pre-boot return message: the values that make it, the theme that shows
// it, and the images drawn from the two.
//
// It runs before the initramfs is built, because the `plymouth` hook packs the
// theme, and everything the renderer put inside it, into the image it builds.
// An installation that asks for no return message does nothing here.

/// Where the installed system keeps what it was configured with. Nothing in
/// the base system creates it, so the phase does.
function oparch_config_directory() -> string {
    "/etc/opinionatedarch"
}

/// Where the values live in the installed system. The renderer reads them from
/// there whenever the message is rebuilt, which is what makes a new phone
/// number an edit and a re-run rather than a reinstallation.
function return_message_values_path() -> string {
    root.common.in_directory(oparch_config_directory(), "return-message.yaml")
}

/// The project's Plymouth theme. It is the theme the boot splash runs, and has
/// nothing to do with the `theme` of the values format, which is what the
/// message is drawn to look like and is the renderer's to resolve.
function plymouth_theme_name() -> string {
    "opinionatedarch"
}

/// Where the theme lives in the installed system, and so where the renderer is
/// told to write the three images the splash reads.
function plymouth_theme_directory(target: root.common.Target) -> string
        throws baml.errors.InvalidArgument {
    root.common.target_path(target, `/usr/share/plymouth/themes/${plymouth_theme_name()}`)
}

/// Where the theme is shipped, in the installer's own assets.
function plymouth_theme_source(asset_dir: string) -> string {
    root.common.in_directory(root.common.in_directory(asset_dir, "plymouth"), plymouth_theme_name())
}

/// Where the logo is staged in the live system. The renderer is given this
/// file: the source says where the logo came from, not what is read.
function staged_logo_path() -> string {
    root.common.in_directory(live_staging_dir(), "logo")
}

function return_message_renderer() -> string {
    "oparch-return-message-render"
}

/// Which logo the message was finally composed with: where it was taken from,
/// absent when the operator chose to go on without one, or what went wrong.
class LogoOutcome {
    source: root.common.Source?,
    error: string,
}

/// Brings one logo file here, whatever its origin: downloaded from a URL, or
/// copied from this machine. Whichever it is, what the renderer receives is the
/// file at `staged_logo_path`.
function fetch_logo(shell: root.common.Shell, files: root.common.Files,
                    source: root.common.Source) -> string {
    if (source.origin == "url") {
        let downloaded = shell.capture("curl",
            ["-fL", "--retry", "2", "--connect-timeout", "10", "-o", staged_logo_path(),
             source.location]);
        return root.common.must(downloaded, `Downloading the logo from ${source.location}`);
    }

    if (!files.exists(source.location)) {
        return `The logo is not there: ${source.location}`;
    }
    let copied = shell.capture("cp", [source.location, staged_logo_path()]);
    root.common.must(copied, `Copying the logo from ${source.location}`)
}

/// Brings the logo here, and asks when it cannot. A mistyped location and a
/// deliberate omission look identical once the installation is over, so the
/// operator answers this while there is still someone to ask, as
/// `docs/decisions/006-preboot-ownership-message.md` requires. Nothing is asked when
/// no logo was wanted in the first place.
function resolve_logo(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                      logo: root.common.Source?) -> LogoOutcome {
    let none = LogoOutcome { source: null, error: "" };
    if (logo == null) {
        return none;
    }
    let choices = ["retry with another logo", "continue without a logo"];
    let wanted = logo;
    files.mkdir(live_staging_dir());

    while (true) {
        let failure = fetch_logo(shell, files, wanted);
        if (failure == "") {
            return LogoOutcome { source: wanted, error: "" };
        }

        if let picked: int = ui.choose("Return message", failure, choices, 0) {
            if ((choices.at(picked) ?? "") == "continue without a logo") {
                return none;
            }
        } else {
            //# nobody answered, so nobody decided: going on either way would
            //# pick one of the two answers on the operator's behalf
            return LogoOutcome { source: null, error: failure };
        }

        if let answer: string = ui.text("Return message", location_prompt(wanted.origin),
                                        wanted.location, false) {
            //# the location comes back prefilled, so leaving it alone retries it
            if (answer.trim() != "") {
                wanted = root.common.source_at(wanted.origin, answer.trim());
            }
        } else {
            return LogoOutcome { source: null, error: failure };
        }
    }
    none
}

/// Puts the project's theme in the target, whole. What the splash shows is
/// images, and the renderer writes them inside this directory afterwards.
function install_plymouth_theme(shell: root.common.Shell, files: root.common.Files,
                                target: root.common.Target, asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
    let themes = root.common.target_path(target, "/usr/share/plymouth/themes");
    files.mkdir(themes);
    root.common.must(shell.capture("cp", ["-r", plymouth_theme_source(asset_dir), themes]),
                     "installing the Plymouth theme")
}

/// How the renderer is called. It runs in the live system and writes into the
/// target: the values it reads are the ones just written there, so the file the
/// installation leaves behind and the file the message is built from are one
/// file.
///
/// The package and the theme are named as directories, already resolved here.
/// The renderer works out no origin of its own, so what it is handed is where
/// the content ended up. `--logo` is passed only when there is one to compose.
function render_message_args(target: root.common.Target, asset_dir: string,
                             message: ReturnMessageInput, logo: string) -> string[]
        throws baml.errors.InvalidArgument {
    let args = [
        "--config", root.common.target_path(target, return_message_values_path()),
        "--assets", asset_dir,
        "--output", plymouth_theme_directory(target),
        "--template-package", package_directory(asset_dir, message.template),
        "--theme", theme_directory(asset_dir, message.theme),
    ];
    if (logo != "") {
        args.push("--logo");
        args.push(staged_logo_path());
    }
    args
}

//# the pre-boot return message, its theme and the images it is shown as
function configure_return_message(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                                  config: InstallConfig, target: root.common.Target,
                                  asset_dir: string) -> string
        throws baml.errors.InvalidArgument {
    if let message: ReturnMessageInput = config.return_message {
        ui.step("Rendering the pre-boot return message...");

        ui.action("Bringing the logo here...");
        let logo = resolve_logo(shell, files, ui, message.values.logo);
        if (logo.error != "") {
            return logo.error;
        }

        //# the file records the logo the message was really built with, so a
        //# rebuild produces the message this machine boots with. Where the
        //# package and the theme came from is not written: that is not this
        //# file's, and the renderer is handed both.
        files.mkdir(root.common.target_path(target, oparch_config_directory()));
        files.write(
            root.common.target_path(target, return_message_values_path()),
            root.return_message.render_values_file(root.return_message.ReturnMessageConfig {
                languages: message.values.languages,
                fields: message.values.fields,
                logo: logo.source,
            }));

        ui.action("Installing the Plymouth theme...");
        let installed = install_plymouth_theme(shell, files, target, asset_dir);
        if (installed != "") {
            return installed;
        }

        ui.action("Drawing the message...");
        let rendered = root.common.must(
            shell.capture(return_message_renderer(),
                          render_message_args(target, asset_dir, message,
                                              if (logo.source == null) { "" } else { "yes" })),
            "rendering the return message");
        if (rendered != "") {
            return rendered;
        }

        return root.common.must(
            root.common.run_in(shell, target, "plymouth-set-default-theme", [plymouth_theme_name()]),
            "setting the Plymouth theme");
    }
    ""
}

// -------------------------------------------------------------------- tests

/// A configuration asking for a message in one language, with a logo.
function return_message_config(logo: root.common.Source?) -> InstallConfig {
    let config = empty_config();
    let message = empty_return_message_input();
    message.values.languages = ["es"];
    let _ = message.values.fields.set("owner_name", "Ivan");
    let _ = message.values.fields.set("phone", "+376 000 000");
    message.values.logo = logo;
    config.return_message = message;
    config
}

function silent_ui() -> ScriptedUi {
    ScriptedUi { answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] }
}

function logo_url() -> string {
    "https://example.invalid/logo.png"
}

/// The logo the tests ask for: one file, taken from a URL.
function logo_source() -> root.common.Source {
    root.common.source_at("url", logo_url())
}

function logo_download(url: string) -> string {
    `curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/logo ${url}`
}

/// The renderer as it is called for the project's own package and theme: both
/// are named as directories, because it resolves nothing of its own.
function rendered_defaults() -> string {
    "oparch-return-message-render --config /mnt/etc/opinionatedarch/return-message.yaml"
        + " --assets /assets --output /mnt/usr/share/plymouth/themes/opinionatedarch"
        + " --template-package /assets/return-message --theme /assets/return-message-theme"
}

function rendered_with_logo() -> string {
    rendered_defaults() + " --logo /tmp/oparch/logo"
}

function rendered_without_logo() -> string {
    rendered_defaults()
}

test "the return message phase does nothing at all when none was asked for" {
    let shell = plain_shell();
    let files = root.common.recording_files();
    let ui = silent_ui();

    assert.equal(
        configure_return_message(shell, files, ui, empty_config(),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(shell.commands, []);
    assert.equal(ui.steps, []);
    assert.equal(files.directories, []);
    assert.is_true(files.written.get("/mnt/etc/opinionatedarch/return-message.yaml") == null)
}

test "the theme is installed and the renderer is run against it, in that order" {
    let shell = plain_shell();
    let files = root.common.recording_files();
    let ui = silent_ui();

    assert.equal(
        configure_return_message(shell, files, ui, return_message_config(logo_source()),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(shell.commands, [
        logo_download(logo_url()),
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes",
        rendered_with_logo(),
        "arch-chroot /mnt plymouth-set-default-theme opinionatedarch",
    ]);
    assert.equal(ui.steps, ["Rendering the pre-boot return message..."]);
    assert.equal(ui.asked, [])
}

test "the values are left in the target where the message can be rebuilt from them" {
    let shell = plain_shell();
    let files = root.common.recording_files();

    let _ = configure_return_message(shell, files, silent_ui(), return_message_config(logo_source()),
                                     root.common.chroot_target("/mnt"), "/assets");

    //# nothing in the base system creates either directory
    assert.equal(files.directories,
                 ["/tmp/oparch", "/mnt/etc/opinionatedarch", "/mnt/usr/share/plymouth/themes"]);
    assert.equal(files.written.get("/mnt/etc/opinionatedarch/return-message.yaml"),
                 "languages:\n  - \"es\"\n"
                     + "fields:\n  owner_name: \"Ivan\"\n  phone: \"+376 000 000\"\n"
                     + "logo:\n  origin: \"url\"\n"
                     + "  location: \"https://example.invalid/logo.png\"\n")
}

test "the theme the operator chose is handed to the renderer, not written down" {
    let shell = plain_shell();
    let files = root.common.recording_files();
    let config = empty_config();
    let message = empty_return_message_input();
    message.theme = root.common.source_at("tar", "https://example.invalid/andorra-dark.tar");
    message.values.languages = ["es"];
    let _ = message.values.fields.set("owner_name", "Ivan");
    config.return_message = message;

    assert.equal(
        configure_return_message(shell, files, silent_ui(), config,
                                 root.common.chroot_target("/mnt"), "/assets"),
        "");

    //# the theme was unpacked into the staging directory, and that is what the
    //# renderer is given: it works out no origin of its own
    assert.is_true(shell.commands.includes(
        "oparch-return-message-render --config /mnt/etc/opinionatedarch/return-message.yaml"
            + " --assets /assets --output /mnt/usr/share/plymouth/themes/opinionatedarch"
            + " --template-package /assets/return-message --theme /tmp/oparch/theme"));
    //# and the file the rebuild reads names no theme at all
    assert.equal(files.written.get("/mnt/etc/opinionatedarch/return-message.yaml"),
                 "languages:\n  - \"es\"\nfields:\n  owner_name: \"Ivan\"\n")
}

test "without a logo nothing is downloaded and the renderer is given none" {
    let shell = plain_shell();
    let files = root.common.recording_files();

    assert.equal(
        configure_return_message(shell, files, silent_ui(), return_message_config(null),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(shell.commands, [
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes",
        rendered_without_logo(),
        "arch-chroot /mnt plymouth-set-default-theme opinionatedarch",
    ]);
    assert.equal(files.written.get("/mnt/etc/opinionatedarch/return-message.yaml"),
                 "languages:\n  - \"es\"\n"
                     + "fields:\n  owner_name: \"Ivan\"\n  phone: \"+376 000 000\"\n")
}

test "a logo that will not download is retried with the URL the operator gives" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(logo_download(logo_url()), 22);
    let files = root.common.recording_files();
    let ui = scripted(["retry with another logo", "https://example.invalid/other.png"]);

    assert.equal(
        configure_return_message(shell, files, ui, return_message_config(logo_source()),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.equal(shell.commands, [
        logo_download(logo_url()),
        logo_download("https://example.invalid/other.png"),
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes",
        rendered_with_logo(),
        "arch-chroot /mnt plymouth-set-default-theme opinionatedarch",
    ]);
    //# the file names the logo the message was built with, not the one asked for
    assert.is_true((files.written.get("/mnt/etc/opinionatedarch/return-message.yaml") ?? "")
        .includes("  location: \"https://example.invalid/other.png\"\n"))
}

test "continuing without a logo says so in the values, and the renderer is told none" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(logo_download(logo_url()), 22);
    let files = root.common.recording_files();
    let ui = scripted(["continue without a logo"]);

    assert.equal(
        configure_return_message(shell, files, ui, return_message_config(logo_source()),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "");

    assert.is_true(!(files.written.get("/mnt/etc/opinionatedarch/return-message.yaml") ?? "")
        .includes("logo:"));
    assert.is_true(shell.commands.includes(rendered_without_logo()));
    assert.is_true(!shell.commands.includes(rendered_with_logo()))
}

test "a logo failure nobody answers stops the phase before anything is written" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(logo_download(logo_url()), 22);
    let files = root.common.recording_files();
    let ui = silent_ui();

    assert.equal(
        configure_return_message(shell, files, ui, return_message_config(logo_source()),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "Downloading the logo from https://example.invalid/logo.png"
            + " failed with exit code 22.");

    assert.equal(shell.commands, [logo_download(logo_url())]);
    assert.is_true(files.written.get("/mnt/etc/opinionatedarch/return-message.yaml") == null)
}

test "a theme that cannot be installed never reaches the renderer" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(
        "cp -r /assets/plymouth/opinionatedarch /mnt/usr/share/plymouth/themes", 1);
    let files = root.common.recording_files();

    assert.equal(
        configure_return_message(shell, files, silent_ui(), return_message_config(null),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "installing the Plymouth theme failed with exit code 1.");

    assert.is_true(!shell.commands.includes(rendered_without_logo()));
    assert.is_true(!shell.commands.includes("arch-chroot /mnt plymouth-set-default-theme opinionatedarch"))
}

test "a message that cannot be drawn never becomes the theme the machine boots" {
    let shell = plain_shell();
    let _ = shell.exit_codes.set(rendered_without_logo(), 1);
    let files = root.common.recording_files();

    assert.equal(
        configure_return_message(shell, files, silent_ui(), return_message_config(null),
                                 root.common.chroot_target("/mnt"), "/assets"),
        "rendering the return message failed with exit code 1.");

    assert.is_true(!shell.commands.includes("arch-chroot /mnt plymouth-set-default-theme opinionatedarch"))
}
