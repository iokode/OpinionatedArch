//# collects everything before anything is written to disk

function collect_config(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                        asset_dir: string) -> InstallConfig? {
    let config = empty_config();
    //# read once: what a question says about itself does not change while it
    //# is being answered
    let tips = load_tips(files, ui, asset_dir);
    ui.outline(step_names());
    let step = 0;

    while (step <= 7) {
        let advanced = if (step == 0) {
            step_disk(shell, ui, tips, config)
        } else if (step == 1) {
            step_data_preservation(ui, tips, config)
        } else if (step == 2) {
            step_hardware(ui, tips, config)
        } else if (step == 3) {
            step_users(ui, tips, config)
        } else if (step == 4) {
            step_locale_and_identity(shell, ui, tips, config)
        } else if (step == 5) {
            step_dotfiles(ui, tips, config)
        } else if (step == 6) {
            step_return_message(shell, files, ui, tips, config, asset_dir)
        } else {
            step_summary(ui, config)
        };

        step
            = if (advanced) {
                step + 1
            } else {
                step - 1
            };
        //# there is nothing behind the first screen. Leaving is F6, explicitly,
        //# so that a key meant to step back never ends the installation
        if (step < 0) {
            step = 0;
        }
    }

    config
}

/// The screens, in the order they are asked. Each `step_*` reports the same
/// title through `ui.step`, and a test keeps the two in agreement.
function step_names() -> string[] {
    [
        "Target disk", "Data preservation", "Hardware", "Users",
        "Locale and identity", "Dotfiles", "Return message", "Summary",
    ]
}

// ------------------------------------------------------------------ screens

function step_disk(shell: root.common.Shell, ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Target disk");
    let disks = list_disks(shell);
    if (disks.length() == 0) {
        ui.error("No selectable disks found.");
        return false;
    }

    ui.tip(tip_for(tips, "disk"));
    let labels = disk_labels(disks);
    let current = 0;
    let index = 0;
    for (let disk in disks) {
        if (disk.path == config.disk) {
            current = index;
        }
        index = index + 1;
    }

    if let picked: int = ui.choose("Target disk", "Where the system will be installed. How much of it is kept is the next question.", labels, current) {
        config.disk = (disks.at(picked))?.path ?? "";
        return true;
    }
    false
}

function step_data_preservation(ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Data preservation");
    ui.tip(tip_for(tips, "data_preservation"));
    let options = ["wipe-all", "keep-homes"];
    if let picked: int = ui
        .choose(
            "Data preservation",
            "wipe-all erases the disk. keep-homes preserves existing home subvolumes.",
            options,
            index_of_option(options, config.install_mode),
        ) {
        config.install_mode = options.at(picked) ?? "";
        return true;
    }
    false
}

function step_hardware(ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Hardware");
    let ucodes = ["intel-ucode", "amd-ucode", "none"];
    let gpus = ["nvidia", "nvidia-open", "nouveau", "none"];
    let field = 0;

    while (field < 4) {
        if (field == 0) {
            ui.tip(tip_for(tips, "ucode"));
            if let picked: int = ui
                .choose(
                    "Hardware",
                    "Microcode package for this CPU.",
                    ucodes,
                    index_of_option(ucodes, config.ucode_package),
                ) {
                config.ucode_package = ucodes.at(picked) ?? "";
                field = 1;
            } else {
                return false;
            }
        } else if (field == 1) {
            ui.tip(tip_for(tips, "gpu"));
            if let picked: int = ui.choose("Hardware", "GPU driver.", gpus, index_of_option(gpus, config.gpu_driver)) {
                config.gpu_driver = gpus.at(picked) ?? "";
                field = 2;
            } else {
                field = 0;
            }
        } else if (field == 2) {
            ui.tip(tip_for(tips, "zram"));
            if let answer: string = ui.text("Hardware", "zram size in GB", `${config.swap.zram_gb}`, false) {
                if let size: int = parse_size_gb(answer) {
                    config.swap.zram_gb = size;
                    field = 3;
                } else {
                    ui.error("Swap sizes must be non-negative integers.");
                }
            } else {
                field = 1;
            }
        } else {
            ui.tip(tip_for(tips, "swapfile"));
            if let answer: string = ui.text("Hardware", "disk swapfile size in GB",
                                            `${config.swap.swapfile_gb}`, false) {
                if let size: int = parse_size_gb(answer) {
                    config.swap.swapfile_gb = size;
                    field = 4;
                } else {
                    ui.error("Swap sizes must be non-negative integers.");
                }
            } else {
                field = 2;
            }
        }
    }
    true
}

function step_users(ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Users");
    let users_csv = config.login_users.join(",");
    let secret = "";
    let field = 0;

    while (field < 3) {
        if (field == 0) {
            ui.tip(tip_for(tips, "usernames"));
            if let answer: string = ui.text("Users", "Login usernames (comma-separated)", users_csv, false) {
                users_csv = answer;
                let parsed = parse_login_users_csv(answer);
                if (parsed.error != "") {
                    ui.error(parsed.error);
                } else {
                    config.login_users = parsed.users;
                    field = 1;
                }
            } else {
                return false;
            }
        } else if (field == 1) {
            ui.tip(tip_for(tips, "shared_secret"));
            if let answer: string = ui.text("Users", "Shared secret", "", true) {
                if (answer == "") {
                    ui.error("Shared secret is required.");
                } else {
                    secret = answer;
                    field = 2;
                }
            } else {
                field = 0;
            }
        } else {
            ui.tip(tip_for(tips, "confirm_secret"));
            if let answer: string = ui.text("Users", "Confirm shared secret", "", true) {
                if (answer != secret) {
                    //# what did not match is the pair, so the pair is asked
                    //# again: retyping the confirmation of a secret that was
                    //# mistyped in the first place can only fail again
                    ui.error("Shared secret values do not match.");
                    secret = "";
                    field = 1;
                } else {
                    config.shared_secret = secret;
                    field = 3;
                }
            } else {
                field = 1;
            }
        }
    }
    true
}

function step_locale_and_identity(shell: root.common.Shell, ui: Ui, tips: Tips,
                                  config: InstallConfig) -> bool {
    ui.step("Locale and identity");
    let title = "Locale and identity";
    let keymaps = list_keymaps(shell);
    let timezones = list_timezones(shell);
    let field = 0;

    while (field < 3) {
        if (field == 0) {
            ui.tip(tip_for(tips, "keymap"));
            if let picked: int = ui
                .choose(
                    title,
                    "Console keymap.",
                    keymaps,
                    index_of_option(keymaps, config.console_keymap),
                ) {
                config.console_keymap = keymaps.at(picked) ?? "";
                field = 1;
            } else {
                return false;
            }
        } else if (field == 1) {
            ui.tip(tip_for(tips, "timezone"));
            if let picked: int = ui
                .choose(
                    title,
                    "Timezone. Type to filter.",
                    timezones,
                    index_of_option(timezones, config.timezone),
                ) {
                config.timezone = timezones.at(picked) ?? "";
                field = 2;
            } else {
                field = 0;
            }
        } else {
            ui.tip(tip_for(tips, "hostname"));
            if let answer: string = ui.text(title, "Hostname", config.hostname, false) {
                if (validate_hostname(answer)) {
                    config.hostname = answer;
                    field = 3;
                } else {
                    ui.error("Invalid hostname format.");
                }
            } else {
                field = 1;
            }
        }
    }
    true
}

// -------------------------------------------------------- asking for content

/// A source as a screen answers it. `answered` is false when the operator went
/// back, which is the one thing a source of its own cannot express.
class SourceAnswer {
    source: root.common.Source,
    answered: bool,
}

/// What each origin is called on screen. The names belong to the format; the
/// wording is the screen's, and says what the operator will be asked for next.
function origin_label(origin: string) -> string {
    if (origin == "default") {
        "the one this project ships"
    } else if (origin == "local") {
        "a directory or a .tar on this machine"
    } else if (origin == "tar") {
        "a .tar by URL"
    } else if (origin == "git") {
        "a git repository"
    } else {
        "a URL"
    }
}

function origin_labels(origins: string[]) -> string[] {
    let labels: string[] = [];
    for (let origin in origins) {
        labels.push(origin_label(origin));
    }
    labels
}

/// What the location is called, once the origin is known. Asking "URL or path"
/// is what having answered the origin already removes.
function location_prompt(origin: string) -> string {
    if (origin == "local") {
        "Where it is on this machine"
    } else if (origin == "git") {
        "Repository URL"
    } else {
        "URL"
    }
}

/// Where a picker starts walking: where the operator last chose, or the top of
/// the filesystem the first time. A location that is a `.tar` starts at the
/// directory holding it, so reopening the picker shows it beside its neighbours.
function picker_start(location: string) -> string {
    if (location == "") {
        return "/";
    }
    if (location.ends_with(".tar")) {
        let cut = location.split("/");
        let _ = cut.pop();
        let parent = cut.join("/");
        return if (parent == "") { "/" } else { parent };
    }
    location
}

test "a picker starts where the last choice was, or at the top" {
    assert.equal(picker_start(""), "/");
    assert.equal(picker_start("/run/oparch/media/sdb1/andorra"), "/run/oparch/media/sdb1/andorra");
    //# an archive is a file, so what is walked is what holds it
    assert.equal(picker_start("/run/oparch/media/sdb1/andorra.tar"), "/run/oparch/media/sdb1");
    assert.equal(picker_start("/andorra.tar"), "/")
}

/// Asks where content comes from: the origin, and then the location, unless the
/// origin is the project's own and there is none to ask for.
///
/// A location that is somewhere else is typed, because a URL cannot be walked
/// to. A location on this machine is walked to, because it can: nobody should
/// have to remember a path on a machine they are installing. `packages` says
/// which of the two pickers that is.
///
/// Nothing is deduced from the answer. Backing out of the location returns to
/// the origin, so a wrong choice is one keystroke to undo.
/// `note` is the key the note is read under. It names what is being asked for
/// — the dotfiles package, the return message's — rather than which half of the
/// question is on screen, because the operator is answering the one and not
/// the other.
function ask_source(ui: Ui, tips: Tips, note: string, title: string, prompt: string,
                    origins: string[], packages: bool,
                    current: root.common.Source) -> SourceAnswer {
    let refused = SourceAnswer { source: root.common.default_source(), answered: false };
    let labels = origin_labels(origins);
    let at = index_of_option(origins, current.origin);
    let location = current.location;

    while (true) {
        ui.tip(tip_for(tips, note));
        if let picked: int = ui.choose(title, prompt, labels, at) {
            let origin = origins.at(picked) ?? "";
            if (origin == "default") {
                return SourceAnswer { source: root.common.default_source(), answered: true };
            }
            at = picked;

            ui.tip(tip_for(tips, note));
            let given = if (origin == "local") {
                if (packages) {
                    ui.pick_package(title, location_prompt(origin), picker_start(location))
                } else {
                    ui.pick_file(title, location_prompt(origin), picker_start(location))
                }
            } else {
                ui.text(title, location_prompt(origin), location, false)
            };

            if let answer: string = given {
                if (answer.trim() == "") {
                    ui.error(`${location_prompt(origin)} cannot be empty.`);
                } else {
                    return SourceAnswer {
                        source: root.common.source_at(origin, answer.trim()), answered: true,
                    };
                }
            }
            location = "";
        } else {
            return refused;
        }
    }
    refused
}

function step_dotfiles(ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Dotfiles");
    let options = ["yes", "no"];
    let current = if (config.dotfiles == null) { 1 } else { 0 };
    let existing = config.dotfiles ?? root.common.source_at("git", "");
    let field = 0;

    while (field < 2) {
        if (field == 0) {
            ui.tip(tip_for(tips, "dotfiles"));
            if let picked: int = ui
                .choose("Dotfiles", "Install a public dotfiles package?", options, current) {
                //# where it comes from is only asked for when there is one
                if ((options.at(picked) ?? "") == "no") {
                    config.dotfiles = null;
                    return true;
                }
                field = 1;
            } else {
                return false;
            }
        } else {
            //# the project ships no dotfiles, so its own is not among the origins
            let answered = ask_source(ui, tips, "dotfiles_source", "Dotfiles",
                                      "Where the dotfiles package comes from.",
                                      root.common.supplied_package_origins(), true, existing);
            if (answered.answered) {
                config.dotfiles = answered.source;
                field = 2;
            } else {
                field = 0;
            }
        }
    }
    true
}

//# the template decides what is asked here, and the theme how many languages
//# may be answered, so both are loaded before asking
function step_return_message(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                             tips: Tips, config: InstallConfig, asset_dir: string) -> bool {
    ui.step("Return message");
    let yes_no = ["yes", "no"];
    let existing = config.return_message;

    let message = if let present: ReturnMessageInput = existing {
        present
    } else {
        empty_return_message_input()
    };
    let values = message.values;

    let field = 0;
    let package = root.return_message.empty_package();
    let theme = root.return_message.empty_theme();
    let asked: root.return_message.TemplateField[] = [];

    while (true) {
        if (field == 0) {
            ui.tip(tip_for(tips, "return_message"));
            if let picked: int = ui.choose("Return message", "Include a pre-boot return message?",
                    yes_no, if (existing == null) { 1 } else { 0 }) {
                if ((yes_no.at(picked) ?? "") == "no") {
                    config.return_message = null;
                    return true;
                }
                field = 1;
            } else {
                return false;
            }
        } else if (field == 1) {
            let answered = ask_source(ui, tips, "return_message_source", "Return message",
                                      "Where the template package comes from.",
                                      root.common.package_origins(), true, message.template);
            if (!answered.answered) {
                field = 0;
            } else {
                //# brought here as it is chosen, and read from where it landed
                let loaded = resolve_package(shell, files, asset_dir, answered.source,
                                             live_staging_dir());
                if (loaded.error != "") {
                    ui.error(loaded.error);
                } else {
                    message.template = answered.source;
                    package = loaded.package;
                    asked = loaded.package.fields;
                    if (package.notice != "") {
                        ui.error(package.notice);
                    }
                    field = 2;
                }
            }
        } else if (field == 2) {
            let answered = ask_source(ui, tips, "return_message_source", "Return message",
                                      "Where the theme comes from.",
                                      root.common.package_origins(), true, message.theme);
            if (!answered.answered) {
                field = 1;
            } else {
                let loaded = resolve_theme(shell, files, asset_dir, answered.source,
                                           live_staging_dir());
                if (loaded.error != "") {
                    ui.error(loaded.error);
                } else {
                    message.theme = answered.source;
                    theme = loaded.theme;
                    field = 3;
                }
            }
        } else if (field <= asked.length() + 2) {
            let declared = asked.at(field - 3);
            if let current: root.return_message.TemplateField = declared {
                if let answer: string = ui.text("Return message", current.label,
                        values.fields.get(current.name) ?? "", false) {
                    if (current.required && answer.trim() == "") {
                        ui.error(`${current.label} cannot be empty.`);
                    } else {
                        let _ = values.fields.set(current.name, answer.trim());
                        field = field + 1;
                    }
                } else {
                    field = field - 1;
                }
            } else {
                field = field + 1;
            }
        } else if (field == asked.length() + 3) {
            //# how many languages may be shown is the theme's: it is what has an
            //# arrangement for each number, so the picker offers no more than
            //# the largest it lays out and the theme judges what was picked
            let accepted = root.return_message.accepted_counts(theme);
            let listed: string[] = [];
            for (let count in accepted) {
                listed.push(`${count}`);
            }
            let most = accepted.at(accepted.length() - 1) ?? 1;

            if let picked: string[] = ui.choose_many("Return message",
                    `Return-message languages (${listed.join(", ")}).`,
                    root.return_message.package_language_labels(package), values.languages, 1, most) {
                //# the operator picks labels; the config keeps codes
                let codes: string[] = [];
                let labels = root.return_message.package_language_labels(package);
                let all = root.return_message.package_language_codes(package);
                let index = 0;
                for (let label in labels) {
                    if (picked.includes(label)) {
                        codes.push(all.at(index) ?? "");
                    }
                    index = index + 1;
                }
                values.languages = codes;

                let problem = root.return_message.check_language_count(theme, values);
                if (problem != "") {
                    ui.error(problem);
                } else {
                    field = field + 1;
                }
            } else {
                field = field - 1;
            }
        } else {
            if let picked: int = ui.choose("Return message", "Include a company logo?", yes_no,
                                           if (values.logo == null) { 1 } else { 0 }) {
                if ((yes_no.at(picked) ?? "") == "no") {
                    values.logo = null;
                    config.return_message = message;
                    return true;
                }
                //# one file, so a repository or an archive would be a container
                //# around something that needs none
                //# one file, walked to rather than typed when it is on this
                //# machine, and typed when it is not
                let answered = ask_source(ui, tips, "return_message_source", "Return message",
                                          "Where the logo comes from.",
                                          root.common.file_origins(), false,
                                          values.logo ?? root.common.source_at("url", ""));
                if (answered.answered) {
                    values.logo = answered.source;
                    config.return_message = message;
                    return true;
                }
            } else {
                field = field - 1;
            }
        }
    }
    true
}

function step_summary(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Summary");
    ui.review("Summary", summary_rows(config))
}

// -------------------------------------------------------------------- tests

/// A live system with one disk, two keymaps, three timezones and two
/// return-message templates.
function fake_live_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [],
        fed: [],
        streamed: [],
        exit_codes: {},
        replies: {
            "lsblk -dpno NAME,TYPE": "/dev/sda disk\n/dev/sr0 rom\n",
            "lsblk -dno SIZE /dev/sda": "476,9G\n",
            "lsblk -dno MODEL /dev/sda": "Samsung SSD 860\n",
            "localectl list-keymaps": "es\nus\n",
            "timedatectl list-timezones": "Europe/Madrid\nUTC\n",
        },
    }
}

function scripted(answers: string[]) -> ScriptedUi {
    ScriptedUi { answers: answers, asked: [], steps: [], errors: [], outline: [], warnings: [], tips: [], limits: [] }
}

test "the form walks every screen and collects the whole config" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", // target disk
            "wipe-all", // install mode
            "amd-ucode",
            "none", // hardware
            "8",
            "0", // swap
            "ivan",
            "hunter2",
            "hunter2", // users
            "es",
            "Europe/Madrid", // locale
            "oparch", // hostname
            "no", // dotfiles
            "no", // return message
            "start", // summary
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.not_null(config);
    assert.equal(ui.errors, []);
    assert
        .equal(
            ui.steps,
            step_names(),
        );

    if let collected: InstallConfig = config {
        assert.equal(collected.disk, "/dev/sda");
        assert.equal(collected.install_mode, "wipe-all");
        assert.equal(collected.ucode_package, "amd-ucode");
        assert.equal(collected.gpu_driver, "none");
        assert.equal(collected.swap.zram_gb, 8);
        assert.equal(collected.swap.swapfile_gb, 0);
        assert.equal(collected.login_users, ["ivan"]);
        assert.equal(collected.shared_secret, "hunter2");
        assert.equal(collected.console_keymap, "es");
        assert.equal(collected.timezone, "Europe/Madrid");
        assert.equal(collected.hostname, "oparch");
        assert.is_true(collected.dotfiles == null);
        assert.is_true(collected.return_message == null);
        assert.is_true(true)
    }
}

test "where the dotfiles come from is asked for only when there are any" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
            "es",
            "UTC",
            "oparch",
            "yes",
            "a git repository", // dotfiles: the origin is answered, not guessed
            "https://example.invalid/dotfiles.git",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    if let collected: InstallConfig = config {
        if let dotfiles: root.common.Source = collected.dotfiles {
            assert.equal(dotfiles.origin, "git");
            assert.equal(dotfiles.location, "https://example.invalid/dotfiles.git")
        }
    }
}

test "the return message asks the fields the template package declares" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
            "es",
            "UTC",
            "oparch",
            "no",
            "yes", // include return message
            "the one this project ships", // template package
            "the one this project ships", // theme
            "Ivan", // owner_name, as the package labels it
            "+376 000 000", // phone
            "Español (es)", // languages
            "no", // logo
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.not_null(config);
    if let collected: InstallConfig = config {
        if let message: ReturnMessageInput = collected.return_message {
            //# the names come from the package, not from the installer
            assert.equal(message.values.fields.get("owner_name"), "Ivan");
            assert.equal(message.values.fields.get("phone"), "+376 000 000");
            assert.equal(message.values.languages, ["es"]);
            assert.is_true(root.common.is_default_source(message.template))
        }
    }
}

test "the package's notice is shown before its fields are asked" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes", "the one this project ships", "the one this project ships",
            "Ivan", "666", "Español (es)", "no", "start",
        ],
    );

    let _ = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.is_true(ui.errors.includes("Every contact field is optional."))
}

test "a template package that cannot be read is reported and asked again" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes",
            "a directory or a .tar on this machine",
            "/nowhere", // a package that is not there
            "the one this project ships", // then the project's own
            "the one this project ships", // theme
            "Ivan", "666", "Español (es)", "no", "start",
        ],
    );
    let shell = fake_live_shell();
    //# neither a directory nor a file, which is what makes it unreachable
    let _ = shell.exit_codes.set("test -d /nowhere", 1);

    let config = collect_config(shell, packaged_files(), ui, "/assets");

    //# the location the operator gave, not the staging path it never reached
    assert.is_true(ui.errors.includes("The template package is not there: /nowhere"));
    assert.not_null(config)
}

test "the theme is asked for beside the package, and kept as it was named" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes",
            "the one this project ships", // template package
            "a directory or a .tar on this machine",
            "/nowhere", // a theme that is not there
            "a directory or a .tar on this machine",
            "/theme", // then one that is
            "Ivan", "666", "Español (es)", "no", "start",
        ],
    );
    let files = packaged_files();
    //# what the copy into the staging directory would have left there
    files.write("/tmp/oparch/theme/manifest.yaml", root.return_message.sample_theme());
    let shell = fake_live_shell();
    let _ = shell.exit_codes.set("test -d /nowhere", 1);

    let config = collect_config(shell, files, ui, "/assets");

    assert.is_true(ui.errors.includes("The theme is not there: /nowhere"));
    assert.not_null(config);
    if let collected: InstallConfig = config {
        if let message: ReturnMessageInput = collected.return_message {
            //# the config keeps where it came from, not where it landed
            assert.equal(message.theme.origin, "local");
            assert.equal(message.theme.location, "/theme")
        }
    }
}

test "the languages the picker takes are the ones the theme lays out" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes", "the one this project ships", "the one this project ships", "Ivan", "666",
            "Español (es), Català (ca), English (en)", // three, which the theme has no arrangement for
            "Español (es), Català (ca)",
            "no", "start",
        ],
    );

    let config = collect_config(fake_live_shell(), three_language_files(), ui, "/assets");

    //# four is the largest the theme lays out, not a number the installer holds
    assert.equal(ui.limits, ["1 to 4", "1 to 4"]);
    assert.is_true(ui.errors.includes(
        "The theme lays out 1, 2 or 4 languages, and 3 were selected."));
    if let collected: InstallConfig = config {
        if let message: ReturnMessageInput = collected.return_message {
            assert.equal(message.values.languages, ["es", "ca"])
        }
    }
}

test "a screen offers the note the assets hold for the question it is asking" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no", "no", "start",
        ],
    );
    let files = packaged_files();
    files.write("/assets/installer-tips.yaml",
                "gpu:\n  - \"which driver, and why\"\nhostname:\n  - \"what to call it\"\n");

    let _ = collect_config(fake_live_shell(), files, ui, "/assets");

    //# one note per question asked, whether or not the assets hold one
    assert.equal(ui.tips.length(), ui.asked.length() - 1);
    //# the fourth question is the GPU driver, and the twelfth the hostname
    assert.equal(ui.tips.at(3), "which driver, and why");
    assert.equal(ui.tips.at(11), "what to call it");
    //# a question the file says nothing about is asked without a note
    assert.equal(ui.tips.at(0), "")
}

test "going back re-asks the previous screen" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", // disk
            "<back>", // back out of install mode
            "/dev/sda (476,9G, Samsung SSD 860)", // disk again
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
            "es",
            "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.not_null(config);
    assert.equal(ui.steps.slice(0, 3), ["Target disk", "Data preservation", "Target disk"])
}

test "backing out of the first screen asks it again rather than leaving" {
    let ui = scripted(
        [
            "<back>", // there is nowhere behind it
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no", "no", "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.not_null(config);
    assert.equal(ui.steps.slice(0, 2), ["Target disk", "Target disk"])
}

test "an invalid hostname is rejected and asked again" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
            "es",
            "UTC",
            "-nope",
            "still bad",
            "oparch", // hostname: two rejections
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.equal(ui.errors, ["Invalid hostname format.", "Invalid hostname format."]);
    if let collected: InstallConfig = config {
        assert.equal(collected.hostname, "oparch")
    }
}

test "swap sizes must be integers, and users must confirm the secret" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "lots",
            "8",
            "0", // swap: one rejection
            "ivan",
            "one",
            "other", // the confirmation does not match
            "one",
            "one", // so both are asked again, and this time they agree
            "es",
            "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert
        .equal(
            ui.errors,
            ["Swap sizes must be non-negative integers.", "Shared secret values do not match."],
        );
    if let collected: InstallConfig = config {
        assert.equal(collected.swap.zram_gb, 8);
        assert.equal(collected.shared_secret, "one")
    }
}

test "an invalid username is reported with the offending name" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "Ivan",
            "ivan",
            "s",
            "s", // rejected, then accepted
            "es",
            "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.equal(ui.errors, ["Invalid username: Ivan"]);
    if let collected: InstallConfig = config {
        assert.equal(collected.login_users, ["ivan"])
    }
}
