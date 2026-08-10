//# collects everything before anything is written to disk

function collect_config(shell: root.common.Shell, files: root.common.Files, ui: Ui,
                        asset_dir: string) -> InstallConfig? {
    let config = empty_config();
    ui.outline(step_names());
    let step = 0;

    while (step <= 9) {
        let advanced = if (step == 0) {
            step_disk(shell, ui, config)
        } else if (step == 1) {
            step_install_mode(ui, config)
        } else if (step == 2) {
            step_hardware(ui, config)
        } else if (step == 3) {
            step_swap(ui, config)
        } else if (step == 4) {
            step_users(ui, config)
        } else if (step == 5) {
            step_locale(shell, ui, config)
        } else if (step == 6) {
            step_identity(ui, config)
        } else if (step == 7) {
            step_dotfiles(ui, config)
        } else if (step == 8) {
            step_return_message(shell, files, ui, config, asset_dir)
        } else {
            step_summary(ui, config)
        };

        step
            = if (advanced) {
                step + 1
            } else {
                step - 1
            };
        //# backing out of the first screen cancels
        if (step < 0) {
            return null;
        }
    }

    config
}

/// The screens, in the order they are asked. Each `step_*` reports the same
/// title through `ui.step`, and a test keeps the two in agreement.
function step_names() -> string[] {
    [
        "Target disk", "Install mode", "Hardware", "Swap", "Users",
        "Locale", "Identity", "Dotfiles", "Return message", "Summary",
    ]
}

// ------------------------------------------------------------------ screens

function step_disk(shell: root.common.Shell, ui: Ui, config: InstallConfig) -> bool {
    ui.step("Target disk");
    let disks = list_disks(shell);
    if (disks.length() == 0) {
        ui.error("No selectable disks found.");
        return false;
    }

    let labels = disk_labels(disks);
    let current = 0;
    let index = 0;
    for (let disk in disks) {
        if (disk.path == config.disk) {
            current = index;
        }
        index = index + 1;
    }

    if let picked: int = ui.choose("Target disk", "Everything on the selected disk will be erased.", labels, current) {
        config.disk = (disks.at(picked))?.path ?? "";
        return true;
    }
    false
}

function step_install_mode(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Install mode");
    let options = ["wipe-all", "keep-homes"];
    if let picked: int = ui
        .choose(
            "Install mode",
            "wipe-all erases the disk. keep-homes preserves existing home subvolumes.",
            options,
            index_of_option(options, config.install_mode),
        ) {
        config.install_mode = options.at(picked) ?? "";
        return true;
    }
    false
}

function step_hardware(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Hardware");
    let ucodes = ["intel-ucode", "amd-ucode", "none"];
    let gpus = ["nvidia", "nvidia-open", "nouveau", "none"];
    let field = 0;

    while (field < 2) {
        if (field == 0) {
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
        } else {
            if let picked: int = ui.choose("Hardware", "GPU driver.", gpus, index_of_option(gpus, config.gpu_driver)) {
                config.gpu_driver = gpus.at(picked) ?? "";
                field = 2;
            } else {
                field = 0;
            }
        }
    }
    true
}

function step_swap(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Swap");
    let field = 0;

    while (field < 2) {
        if (field == 0) {
            if let answer: string = ui.text("Swap", "zram size in GB", `${config.swap.zram_gb}`, false) {
                if let size: int = parse_size_gb(answer) {
                    config.swap.zram_gb = size;
                    field = 1;
                } else {
                    ui.error("Swap sizes must be non-negative integers.");
                }
            } else {
                return false;
            }
        } else {
            if let answer: string = ui.text("Swap", "disk swapfile size in GB", `${config.swap.swapfile_gb}`, false) {
                if let size: int = parse_size_gb(answer) {
                    config.swap.swapfile_gb = size;
                    field = 2;
                } else {
                    ui.error("Swap sizes must be non-negative integers.");
                }
            } else {
                field = 0;
            }
        }
    }
    true
}

function step_users(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Users");
    let users_csv = config.login_users.join(",");
    let secret = "";
    let field = 0;

    while (field < 3) {
        if (field == 0) {
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
            if let answer: string = ui.text("Users", "Confirm shared secret", "", true) {
                if (answer != secret) {
                    ui.error("Shared secret values do not match.");
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

function step_locale(shell: root.common.Shell, ui: Ui, config: InstallConfig) -> bool {
    ui.step("Locale");
    let keymaps = list_keymaps(shell);
    let timezones = list_timezones(shell);
    let field = 0;

    while (field < 2) {
        if (field == 0) {
            if let picked: int = ui
                .choose(
                    "Locale",
                    "Console keymap.",
                    keymaps,
                    index_of_option(keymaps, config.console_keymap),
                ) {
                config.console_keymap = keymaps.at(picked) ?? "";
                field = 1;
            } else {
                return false;
            }
        } else {
            if let picked: int = ui
                .choose(
                    "Locale",
                    "Timezone. Type to filter.",
                    timezones,
                    index_of_option(timezones, config.timezone),
                ) {
                config.timezone = timezones.at(picked) ?? "";
                field = 2;
            } else {
                field = 0;
            }
        }
    }
    true
}

function step_identity(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Identity");
    while (true) {
        if let answer: string = ui.text("Identity", "Hostname", config.hostname, false) {
            if (validate_hostname(answer)) {
                config.hostname = answer;
                return true;
            }
            ui.error("Invalid hostname format.");
        } else {
            return false;
        }
    }
    false
}

function step_dotfiles(ui: Ui, config: InstallConfig) -> bool {
    ui.step("Dotfiles");
    let options = ["yes", "no"];
    let current = if (config.dotfiles == null) { 1 } else { 0 };
    let url = if let existing: DotfilesConfig = config.dotfiles { existing.repository_url } else { "" };
    let field = 0;

    while (field < 2) {
        if (field == 0) {
            if let picked: int = ui
                .choose("Dotfiles", "Clone a public dotfiles repository?", options, current) {
                //# the URL is only asked for when cloning is enabled
                if ((options.at(picked) ?? "") == "no") {
                    config.dotfiles = null;
                    return true;
                }
                field = 1;
            } else {
                return false;
            }
        } else {
            if let answer: string = ui.text("Dotfiles", "Dotfiles repository URL", url, false) {
                if (answer.trim() == "") {
                    ui.error(
                        "Dotfiles repository URL is required when dotfiles cloning is enabled.",
                    );
                } else {
                    config.dotfiles = DotfilesConfig { repository_url: answer.trim() };
                    field = 2;
                }
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
                             config: InstallConfig, asset_dir: string) -> bool {
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
            //# empty means the project's own package
            if let answer: string = ui.text("Return message",
                    "Template package directory or URL, or empty for the default one",
                    message.template, false) {
                let loaded = resolve_package(shell, files, asset_dir, answer.trim(),
                                             live_staging_dir());
                if (loaded.error != "") {
                    ui.error(loaded.error);
                } else {
                    message.template = answer.trim();
                    package = loaded.package;
                    asked = loaded.package.fields;
                    if (package.notice != "") {
                        ui.error(package.notice);
                    }
                    field = 2;
                }
            } else {
                field = 0;
            }
        } else if (field == 2) {
            //# empty means the project's own theme
            if let answer: string = ui.text("Return message",
                    "Theme directory or URL, or empty for the default one",
                    message.theme, false) {
                let loaded = resolve_theme(shell, files, asset_dir, answer.trim(),
                                           live_staging_dir());
                if (loaded.error != "") {
                    ui.error(loaded.error);
                } else {
                    message.theme = answer.trim();
                    theme = loaded.theme;
                    field = 3;
                }
            } else {
                field = 1;
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
                                           if (values.logo_url == "") { 1 } else { 0 }) {
                if ((yes_no.at(picked) ?? "") == "no") {
                    values.logo_url = "";
                    config.return_message = message;
                    return true;
                }
                if let answer: string = ui.text("Return message", "Logo URL", values.logo_url, false) {
                    if (answer.trim() == "") {
                        ui.error("Logo URL is required when the logo is included.");
                    } else {
                        values.logo_url = answer.trim();
                        config.return_message = message;
                        return true;
                    }
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
    ui.review("Summary", summary_lines(config))
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
    ScriptedUi { answers: answers, asked: [], steps: [], errors: [], outline: [], limits: [] }
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
            [
                "Target disk",
                "Install mode",
                "Hardware",
                "Swap",
                "Users",
                "Locale",
                "Identity",
                "Dotfiles",
                "Return message",
                "Summary",
            ],
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

test "the dotfiles URL is asked for only when cloning is enabled" {
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
            "https://example.invalid/dotfiles.git", // dotfiles
            "no",
            "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    if let collected: InstallConfig = config {
        if let dotfiles: DotfilesConfig = collected.dotfiles {
            assert.equal(dotfiles.repository_url, "https://example.invalid/dotfiles.git")
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
            "", // template package: the project's own
            "", // theme: the project's own
            "Ivan", // owner_name, as the package labels it
            "666 555 666", // phone
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
            assert.equal(message.values.fields.get("phone"), "666 555 666");
            assert.equal(message.values.languages, ["es"]);
            assert.equal(message.template, "")
        }
    }
}

test "the package's notice is shown before its fields are asked" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes", "", "", "Ivan", "666", "Español (es)", "no", "start",
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
            "/nowhere", // a package that is not there
            "", // then the project's own
            "", // theme: the project's own
            "Ivan", "666", "Español (es)", "no", "start",
        ],
    );

    let config = collect_config(fake_live_shell(), packaged_files(), ui, "/assets");

    assert.is_true(ui.errors.includes(
        "The template package has no manifest.yaml: /nowhere/manifest.yaml"));
    assert.not_null(config)
}

test "the theme is asked for beside the package, and kept as it was named" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes",
            "", // template package: the project's own
            "/nowhere", // a theme that is not there
            "/theme", // then one that is
            "Ivan", "666", "Español (es)", "no", "start",
        ],
    );
    let files = packaged_files();
    files.write("/theme/manifest.yaml", root.return_message.sample_theme());

    let config = collect_config(fake_live_shell(), files, ui, "/assets");

    assert.is_true(ui.errors.includes("The theme has no manifest.yaml: /nowhere/manifest.yaml"));
    assert.not_null(config);
    if let collected: InstallConfig = config {
        if let message: ReturnMessageInput = collected.return_message {
            assert.equal(message.theme, "/theme")
        }
    }
}

test "the languages the picker takes are the ones the theme lays out" {
    let ui = scripted(
        [
            "/dev/sda (476,9G, Samsung SSD 860)", "wipe-all", "none", "none", "0", "0",
            "ivan", "s", "s", "es", "UTC", "oparch", "no",
            "yes", "", "", "Ivan", "666",
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
    assert.equal(ui.steps.slice(0, 3), ["Target disk", "Install mode", "Target disk"])
}

test "backing out of the first screen cancels the installer" {
    let ui = scripted(["<back>"]);
    assert.is_true(collect_config(fake_live_shell(), packaged_files(), ui, "/assets") == null)
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
            "other",
            "one", // secret mismatch, then confirmed
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
