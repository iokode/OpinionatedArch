//# collects everything before anything is written to disk

function collect_config(shell: root.common.Shell, files: root.common.Files, secrets: Secrets,
                        ui: Ui, asset_dir: string) -> InstallConfig? {
    let config = empty_config();
    //# read once: what a question says about itself does not change while it
    //# is being answered
    let tips = load_tips(files, ui, asset_dir);
    ui.outline(form_phases());
    let step = 0;

    while (step <= 8) {
        let advanced = if (step == 0) {
            step_keymap(shell, ui, tips, config)
        } else if (step == 1) {
            step_disk(shell, ui, tips, config)
        } else if (step == 2) {
            step_data_preservation(ui, tips, config)
        } else if (step == 3) {
            step_hardware(ui, tips, config)
        } else if (step == 4) {
            step_work_contexts(ui, tips, config)
        } else if (step == 5) {
            step_locale_and_identity(shell, ui, tips, config)
        } else if (step == 6) {
            step_dotfiles(shell, files, secrets, ui, tips, config)
        } else if (step == 7) {
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
        "Keymap", "Target disk", "Data preservation", "Hardware", "Work contexts",
        "Locale and identity", "Dotfiles", "Return message", "Summary",
    ]
}

/// The same list, as the outline takes it. A screen is answered, not performed,
/// so it reads the same whether it is ahead, current or behind.
function form_phases() -> Phase[] {
    let phases: Phase[] = [];
    for (let name in step_names()) {
        phases.push(screen(name));
    }
    phases
}

// ------------------------------------------------------------------ screens

/// The keymap, before anything else is asked.
///
/// It comes first because it is the only answer that changes how every later
/// answer is typed. Until it is applied, the console is whatever the live
/// medium defaults to, and the questions worst served by that are the ones
/// nobody can see themselves getting wrong: the shared secret, which unlocks
/// the disk, and the passphrase of a secret store, which is the longest thing
/// anyone types here. Both are masked.
///
/// Applying it is part of answering it. A keymap chosen and not applied is the
/// state this screen exists to remove, so a `loadkeys` that fails is reported
/// and the question asked again rather than accepted with a warning.
function step_keymap(shell: root.common.Shell, ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Keymap");
    let keymaps = list_keymaps(shell);

    while (true) {
        ui.tip(tip_for(tips, "keymap"));
        if let picked: int = ui
            .choose("Keymap", "Console keymap. Everything after this is typed with it.",
                    keymaps, index_of_option(keymaps, config.console_keymap)) {
            let chosen = keymaps.at(picked) ?? "";
            let applied = root.common.must(shell.capture("loadkeys", [chosen]),
                                           `Applying the ${chosen} keymap`);
            if (applied == "") {
                config.console_keymap = chosen;
                return true;
            }
            ui.error(applied);
        } else {
            return false;
        }
    }
    false
}

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
    while (true) {
        if let picked: int = ui
            .choose(
                "Data preservation",
                "wipe-all erases the disk. keep-homes preserves existing home subvolumes.",
                options,
                index_of_option(options, config.install_mode),
            ) {
            let mode = options.at(picked) ?? "";
            //# the mode is offered because the layout admits it and refused here
            //# because nothing implements it yet. Saying so at the question is
            //# what keeps the run from ending at the summary, with every other
            //# answer already given.
            if (mode == "keep-homes") {
                ui.error("keep-homes is not implemented yet.");
            } else {
                config.install_mode = mode;
                return true;
            }
        } else {
            return false;
        }
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

function step_work_contexts(ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Work contexts");
    let users_csv = config.work_contexts.join(",");
    let secret = "";
    let field = 0;

    while (field < 3) {
        if (field == 0) {
            ui.tip(tip_for(tips, "work_contexts"));
            if let answer: string = ui
                .text("Work contexts", "Work context names (comma-separated)", users_csv, false) {
                users_csv = answer;
                let parsed = parse_work_contexts_csv(answer);
                if (parsed.error != "") {
                    ui.error(parsed.error);
                } else {
                    config.work_contexts = parsed.work_contexts;
                    field = 1;
                }
            } else {
                return false;
            }
        } else if (field == 1) {
            ui.tip(tip_for(tips, "shared_secret"));
            if let answer: string = ui.text("Work contexts", "Shared secret", "", true) {
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
            if let answer: string = ui.text("Work contexts", "Confirm shared secret", "", true) {
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
    let timezones = list_timezones(shell);
    //# the keymap was the first thing asked, and is already in force
    let field = 1;

    while (field < 3) {
        if (field == 1) {
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
                return false;
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
    source: Source,
    answered: bool,
}

/// What each origin is called on screen. The names belong to the format; the
/// wording is the screen's, and says what the operator will be asked for next.
///
/// `local` is the one origin whose wording depends on what is being asked for,
/// because it is the one that names the content rather than a transport: a
/// package on this machine is a directory or an archive, and a file is a file.
function origin_label(origin: string, packages: bool) -> string {
    if (origin == "default") {
        "the one this project ships"
    } else if (origin == "local") {
        if (packages) {
            "a directory or a .tar on this machine"
        } else {
            "a file on this machine"
        }
    } else if (origin == "tar") {
        "a .tar by URL"
    } else if (origin == "git") {
        "a git repository"
    } else {
        "a URL"
    }
}

function origin_labels(origins: string[], packages: bool) -> string[] {
    let labels: string[] = [];
    for (let origin in origins) {
        labels.push(origin_label(origin, packages));
    }
    labels
}

test "the origin on this machine is named after what is being asked for" {
    assert.equal(origin_labels(file_origins(), false), ["a URL", "a file on this machine"]);
    assert.equal(origin_labels(supplied_package_origins(), true),
                 ["a directory or a .tar on this machine", "a .tar by URL", "a git repository"]);
    //# the origins that name a transport read the same either way
    assert.equal(origin_label("tar", true), origin_label("tar", false));
    assert.equal(origin_label("git", true), origin_label("git", false));
    assert.equal(origin_label("default", true), origin_label("default", false))
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
/// which of the two pickers that is, and what the origin on this machine is
/// called.
///
/// Nothing is deduced from the answer. Backing out of the location returns to
/// the origin, so a wrong choice is one keystroke to undo.
/// `note` is the key the note is read under. It names what is being asked for
/// — the dotfiles package, the return message's — rather than which half of the
/// question is on screen, because the operator is answering the one and not
/// the other.
function ask_source(ui: Ui, tips: Tips, note: string, title: string, prompt: string,
                    origins: string[], packages: bool,
                    current: Source) -> SourceAnswer {
    let refused = SourceAnswer { source: default_source(), answered: false };
    let labels = origin_labels(origins, packages);
    let at = index_of_option(origins, current.origin);
    let location = current.location;

    while (true) {
        ui.tip(tip_for(tips, note));
        if let picked: int = ui.choose(title, prompt, labels, at) {
            let origin = origins.at(picked) ?? "";
            if (origin == "default") {
                return SourceAnswer { source: default_source(), answered: true };
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
                        source: source_at(origin, answer.trim()), answered: true,
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

//# the package is brought here as it is chosen and judged by the tool that will
//# have to apply it, so a package that cannot be applied is refused while there
//# is still somebody to ask and a disk nobody has touched
function step_dotfiles(shell: root.common.Shell, files: root.common.Files, secrets: Secrets,
                       ui: Ui, tips: Tips, config: InstallConfig) -> bool {
    ui.step("Dotfiles");
    let staging = live_staging_dir();
    let options = ["yes", "no"];
    let current = if (config.dotfiles == null) { 1 } else { 0 };
    let existing = config.dotfiles ?? source_at("git", "");
    let store = config.secret_store
        ?? SecretStoreInput { archive: source_at("local", ""), passphrase: "" };
    let wanted: string[] = [];
    let field = 0;

    while (field < 4) {
        if (field == 0) {
            ui.tip(tip_for(tips, "dotfiles"));
            if let picked: int = ui
                .choose("Dotfiles", "Install a public dotfiles package?", options, current) {
                //# where it comes from is only asked for when there is one
                if ((options.at(picked) ?? "") == "no") {
                    config.dotfiles = null;
                    config.secret_store = null;
                    return true;
                }
                field = 1;
            } else {
                return false;
            }
        } else if (field == 1) {
            //# the project ships no dotfiles, so its own is not among the origins
            let answered = ask_source(ui, tips, "dotfiles_source", "Dotfiles",
                                      "Where the dotfiles package comes from.",
                                      supplied_package_origins(), true, existing);
            if (!answered.answered) {
                field = 0;
            } else {
                existing = answered.source;
                let judged = resolve_dotfiles(shell, files, config, answered.source, staging);
                if (judged.error != "") {
                    ui.error(judged.error);
                } else {
                    config.dotfiles = answered.source;
                    wanted = judged.files;
                    //# a map that declares no secrets is never asked for any
                    if (wanted.length() == 0) {
                        config.secret_store = null;
                        return true;
                    }
                    field = 2;
                }
            }
        } else if (field == 2) {
            let answered = ask_source(ui, tips, "dotfiles_secrets", "Dotfiles",
                                      "Where the encrypted secret store comes from.",
                                      file_origins(), false, store.archive);
            if (!answered.answered) {
                field = 1;
            } else {
                let brought = bring_file_here(shell, files, answered.source,
                                              staged_store_path(staging), "secret store");
                if (brought != "") {
                    ui.error(brought);
                } else if (!secrets.sealed(staged_store_path(staging))) {
                    //# asked of the file rather than of the passphrase, because
                    //# the answer to this is another file, and there is no sense
                    //# in typing a passphrase to be told that. It is named as
                    //# the operator named it, not as the copy of it here.
                    ui.error(`Not an encrypted secret store: ${answered.source.location}`);
                } else {
                    store.archive = answered.source;
                    field = 3;
                }
            }
        } else {
            //# the passphrase proves itself: what it opens is either what the
            //# map asked for or nothing at all, so it is asked once and asked
            //# again when it fails, and never confirmed against a second copy
            ui.tip(tip_for(tips, "dotfiles_secrets"));
            if let given: string = ui.text("Dotfiles", "Passphrase for the secret store", "", true) {
                let failure = open_secret_store(shell, files, secrets, given, staging);
                if (failure != "") {
                    ui.error(failure);
                } else {
                    let refused = check_staged_secrets(shell, config, staging);
                    if (refused != "") {
                        //# it opened, and what came out is not what is needed:
                        //# the answer to that is another archive, not another
                        //# attempt at the same one
                        ui.error(refused);
                        field = 2;
                    } else {
                        store.passphrase = given;
                        config.secret_store = store;
                        return true;
                    }
                }
            } else {
                field = 2;
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
                                      package_origins(), true, message.template);
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
                                      package_origins(), true, message.theme);
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
                                           if (message.logo == null) { 1 } else { 0 }) {
                if ((yes_no.at(picked) ?? "") == "no") {
                    message.logo = null;
                    config.return_message = message;
                    return true;
                }
                //# one file, so a repository or an archive would be a container
                //# around something that needs none
                //# one file, walked to rather than typed when it is on this
                //# machine, and typed when it is not
                let answered = ask_source(ui, tips, "return_message_source", "Return message",
                                          "Where the logo comes from.",
                                          file_origins(), false,
                                          message.logo ?? source_at("url", ""));
                if (answered.answered) {
                    message.logo = answered.source;
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
    ScriptedUi { answers: answers, asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [], limits: [] }
}

test "the form walks every screen and collects the whole config" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)", // target disk
            "wipe-all", // install mode
            "amd-ucode",
            "none", // hardware
            "8",
            "0", // swap
            "ivan",
            "hunter2",
            "hunter2", // users
                        "Europe/Madrid", // locale
            "oparch", // hostname
            "no", // dotfiles
            "no", // return message
            "start", // summary
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

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
        assert.equal(collected.work_contexts, ["ivan"]);
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
            "es", "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
                        "UTC",
            "oparch",
            "yes",
            "a git repository", // dotfiles: the origin is answered, not guessed
            "https://example.invalid/dotfiles.git",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    if let collected: InstallConfig = config {
        if let dotfiles: Source = collected.dotfiles {
            assert.equal(dotfiles.origin, "git");
            assert.equal(dotfiles.location, "https://example.invalid/dotfiles.git")
        }
    }
}

/// What the tool is asked while the form is being answered, as the recording
/// shell writes the two command lines down.
function listing_command() -> string {
    "oparch-dotfiles-sync --list-secrets --source /tmp/oparch/dotfiles --hostname oparch"
        + " --user ivan"
}

function confirming_command() -> string {
    "oparch-dotfiles-sync --dry-run --source /tmp/oparch/dotfiles --hostname oparch --user ivan"
        + " --secrets-root /tmp/oparch/secrets"
}

/// The answers up to the dotfiles screen, for a machine called `oparch` with
/// one work context.
function up_to_dotfiles() -> string[] {
    [
        "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
        "ivan", "s", "s", "UTC", "oparch",
    ]
}

test "the keymap is asked first, and in force before anything else is typed" {
    let shell = fake_live_shell();
    let ui = scripted(up_to_dotfiles().concat(["no", "no", "start"]));

    let config = collect_config(shell, packaged_files(), recording_secrets(), ui, "/assets");

    //# the list is read, the choice is applied, and only then is anything else
    //# even looked at — the disk is the next thing the installer asks the system
    assert.equal(shell.commands.slice(0, 3),
                 ["localectl list-keymaps", "loadkeys es", "lsblk -dpno NAME,TYPE"]);
    assert.equal(ui.steps.at(0) ?? "", "Keymap");
    if let collected: InstallConfig = config {
        assert.equal(collected.console_keymap, "es")
    }
}

test "a keymap that cannot be applied is reported, and another one is asked for" {
    let shell = fake_live_shell();
    let _ = shell.exit_codes.set("loadkeys es", 1);
    let ui = scripted(
        ["es", "us"].concat(up_to_dotfiles().slice(1, up_to_dotfiles().length()))
            .concat(["no", "no", "start"]));

    let config = collect_config(shell, packaged_files(), recording_secrets(), ui, "/assets");

    //# not a warning: a keymap that was chosen and not applied is the state this
    //# screen exists to remove, so it is not an answer the form accepts
    assert.equal(ui.errors, ["Applying the es keymap failed with exit code 1."]);
    if let collected: InstallConfig = config {
        assert.equal(collected.console_keymap, "us")
    }
}

test "a package the tool refuses is reported in its words and asked again" {
    let shell = fake_live_shell();
    let _ = shell.exit_codes.set(listing_command(), 1);
    let ui = scripted(
        up_to_dotfiles().concat([
            "yes",
            "a git repository",
            "https://example.invalid/dotfiles.git", // refused by the tool
            "<back>", // so the screen asks again, and the operator gives up
            "no",
            "no", "start",
        ]));

    let config = collect_config(shell, packaged_files(), recording_secrets(), ui, "/assets");

    //# the recording shell carries no standard error, so what is relayed is that
    //# it was refused at all; what it said is covered where a result can carry it
    assert.equal(ui.errors,
                 ["The dotfiles package was refused, without saying why (exit code 1)."]);
    //# a package the tool will not have is not one the installation carries
    if let collected: InstallConfig = config {
        assert.is_true(collected.dotfiles == null);
        assert.is_true(collected.secret_store == null)
    }
}

test "a map that declares secrets is given a store, and the store is opened" {
    let shell = fake_live_shell();
    let _ = shell.replies.set(listing_command(), "global/github.token\nuser/ivan/backup.key\n");
    let secrets = recording_secrets();
    let ui = scripted(
        up_to_dotfiles().concat([
            "yes",
            "a git repository",
            "https://example.invalid/dotfiles.git",
            "a URL", // the store is one file, so it is asked for as one
            "https://example.invalid/store.dfsec",
            "sixteen words from the short list",
            "no", "start",
        ]));

    let config = collect_config(shell, packaged_files(), secrets, ui, "/assets");

    assert.equal(secrets.opened, ["/tmp/oparch/store.dfsec -> /tmp/oparch/store.tar"]);
    //# opened, unpacked, and then held to what the map asked for
    assert.is_true(shell.commands.includes("tar -xf /tmp/oparch/store.tar -C /tmp/oparch/secrets"));
    assert.is_true(shell.commands.includes(confirming_command()));
    if let collected: InstallConfig = config {
        if let store: SecretStoreInput = collected.secret_store {
            assert.equal(store.archive.origin, "url");
            assert.equal(store.passphrase, "sixteen words from the short list")
        }
    }
}

test "a file that is not a store is refused before a passphrase is asked for" {
    let shell = fake_live_shell();
    let _ = shell.replies.set(listing_command(), "global/github.token\n");
    let secrets = recording_secrets();
    let _ = secrets.unsealed.push("/tmp/oparch/store.dfsec");
    let ui = scripted(
        up_to_dotfiles().concat([
            "yes", "a git repository", "https://example.invalid/dotfiles.git",
            "a URL", "https://example.invalid/not-a-store.png",
            "<back>", "<back>", "no", "no", "start",
        ]));

    let _ = collect_config(shell, packaged_files(), secrets, ui, "/assets");

    //# named as the operator named it, not as the copy of it in the staging path
    assert.equal(ui.errors,
                 ["Not an encrypted secret store: https://example.invalid/not-a-store.png"]);
    //# and nothing was opened, because nothing was typed to open it with
    assert.equal(secrets.opened, [])
}

test "a passphrase that does not open the store is asked again" {
    let shell = fake_live_shell();
    let _ = shell.replies.set(listing_command(), "global/github.token\n");
    let secrets = recording_secrets();
    let _ = secrets.refusals.set("/tmp/oparch/store.dfsec",
                                 "The passphrase does not open the secret store.");
    let ui = scripted(
        up_to_dotfiles().concat([
            "yes", "a git repository", "https://example.invalid/dotfiles.git",
            "a URL", "https://example.invalid/store.dfsec",
            "wrong words", // refused, and asked again rather than confirmed
            "<back>", // the operator gives up on the passphrase,
            "<back>", // on the archive,
            "<back>", // and on the package
            "no", "no", "start",
        ]));

    let _ = collect_config(shell, packaged_files(), secrets, ui, "/assets");

    assert.equal(ui.errors, ["The passphrase does not open the secret store."]);
    //# asked once, not confirmed against a second copy of itself
    assert.equal(secrets.opened.length(), 1)
}

test "the return message asks the fields the template package declares" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
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

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.not_null(config);
    if let collected: InstallConfig = config {
        if let message: ReturnMessageInput = collected.return_message {
            //# the names come from the package, not from the installer
            assert.equal(message.values.fields.get("owner_name"), "Ivan");
            assert.equal(message.values.fields.get("phone"), "+376 000 000");
            assert.equal(message.values.languages, ["es"]);
            assert.is_true(is_default_source(message.template))
        }
    }
}

test "the package's notice is shown before its fields are asked" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "UTC", "oparch", "no",
            "yes", "the one this project ships", "the one this project ships",
            "Ivan", "666", "Español (es)", "no", "start",
        ],
    );

    let _ = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.is_true(ui.errors.includes("Every contact field is optional."))
}

test "a template package that cannot be read is reported and asked again" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "UTC", "oparch", "no",
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

    let config = collect_config(shell, packaged_files(), recording_secrets(), ui, "/assets");

    //# the location the operator gave, not the staging path it never reached
    assert.is_true(ui.errors.includes("The template package is not there: /nowhere"));
    assert.not_null(config)
}

test "the theme is asked for beside the package, and kept as it was named" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "UTC", "oparch", "no",
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

    let config = collect_config(shell, files, recording_secrets(), ui, "/assets");

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
            "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "UTC", "oparch", "no",
            "yes", "the one this project ships", "the one this project ships", "Ivan", "666",
            "Español (es), Català (ca), English (en)", // three, which the theme has no arrangement for
            "Español (es), Català (ca)",
            "no", "start",
        ],
    );

    let config = collect_config(fake_live_shell(), three_language_files(), recording_secrets(), ui, "/assets");

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
            "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "UTC", "oparch", "no", "no", "start",
        ],
    );
    let files = packaged_files();
    files.write("/assets/installer-tips.yaml",
                "gpu:\n  - \"which driver, and why\"\nhostname:\n  - \"what to call it\"\n");

    let _ = collect_config(fake_live_shell(), files, recording_secrets(), ui, "/assets");

    //# one note per question asked, whether or not the assets hold one
    assert.equal(ui.tips.length(), ui.asked.length() - 1);
    //# the fifth question is the GPU driver, and the twelfth the hostname
    assert.equal(ui.tips.at(4), "which driver, and why");
    assert.equal(ui.tips.at(11), "what to call it");
    //# a question the file says nothing about is asked without a note
    assert.equal(ui.tips.at(0), "")
}

test "going back re-asks the previous screen" {
    let ui = scripted(
        [
            "es", // keymap
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
            "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.not_null(config);
    assert.equal(ui.steps.slice(1, 4), ["Target disk", "Data preservation", "Target disk"])
}

test "backing out of the first screen asks it again rather than leaving" {
    let ui = scripted(
        [
            "<back>", // there is nowhere behind it
            "es", "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "UTC", "oparch", "no", "no", "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.not_null(config);
    //# the first screen is the keymap now, and it is the one with nothing behind it
    assert.equal(ui.steps.slice(0, 2), ["Keymap", "Keymap"])
}

test "an invalid hostname is rejected and asked again" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
                        "UTC",
            "-nope",
            "still bad",
            "oparch", // hostname: two rejections
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.equal(ui.errors, ["Invalid hostname format.", "Invalid hostname format."]);
    if let collected: InstallConfig = config {
        assert.equal(collected.hostname, "oparch")
    }
}

test "swap sizes must be integers, and users must confirm the secret" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)",
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
                        "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

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

test "keep-homes is refused at the question and asked again" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)",
            "keep-homes",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "ivan",
            "s",
            "s",
                        "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.equal(ui.errors, ["keep-homes is not implemented yet."]);
    if let collected: InstallConfig = config {
        assert.equal(collected.install_mode, "wipe-all")
    }
}

test "an invalid username is reported with the offending name" {
    let ui = scripted(
        [
            "es", "/dev/sda (476,9G, Samsung SSD 860)",
            "wipe-all",
            "none",
            "none",
            "0",
            "0",
            "Ivan",
            "ivan",
            "s",
            "s", // rejected, then accepted
                        "UTC",
            "oparch",
            "no",
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), recording_secrets(), ui, "/assets");

    assert.equal(ui.errors, ["Invalid work context name: Ivan"]);
    if let collected: InstallConfig = config {
        assert.equal(collected.work_contexts, ["ivan"])
    }
}
