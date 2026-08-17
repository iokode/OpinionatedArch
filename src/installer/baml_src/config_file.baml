// The non-interactive entry point: the same InstallConfig the form collects,
// read from the YAML file defined in
// `docs/tools/oparch-installer/001-config-file-format.md`.
//
// Parsing is pure and lives here. Checks that need the live system are in
// `check_config`, which asks the Shell for them.

/// Either a config or the first thing wrong with the file.
class ConfigParse {
    config: InstallConfig,
    error: string,
}

function allowed_top_keys() -> string[] {
    [
        "disk", "install_mode", "preserved_work_contexts", "ucode_package", "gpu_driver",
        "swap", "work_contexts", "shared_secret", "console_keymap", "timezone",
        "hostname", "dotfiles", "secret_store", "return_message",
    ]
}

function allowed_secret_store_keys() -> string[] {
    ["archive", "passphrase"]
}

function allowed_swap_keys() -> string[] {
    ["zram_gb", "swapfile_gb"]
}

// ----------------------------------------------------------------- the file

function parse_config_file(text: string) -> ConfigParse {
    let document = baml.yaml.parse(text)
        catch (e) {
            _ => {
                return ConfigParse { config: empty_config(), error: `Invalid YAML: ${e.message}` };
            }
        };

    let top = root.common.as_map(document) ?? root.common.empty_json_map();
    if (root.common.as_map(document) == null) {
        return ConfigParse { config: empty_config(), error: "The configuration must be a mapping." };
    }
    if let unknown: string = root.common.unknown_key(top, allowed_top_keys()) {
        return ConfigParse { config: empty_config(), error: `Unknown key in config file: ${unknown}` };
    }

    let config = empty_config();
    let read_disk = root.common.read_text(top, "disk", "disk");
    if (read_disk.error != "") {
        return ConfigParse { config: config, error: read_disk.error };
    }
    config.disk = read_disk.value;

    let read_install_mode = root.common.read_text(top, "install_mode", "install_mode");
    if (read_install_mode.error != "") {
        return ConfigParse { config: config, error: read_install_mode.error };
    }
    config.install_mode = read_install_mode.value;

    let read_ucode_package = root.common.read_text(top, "ucode_package", "ucode_package");
    if (read_ucode_package.error != "") {
        return ConfigParse { config: config, error: read_ucode_package.error };
    }
    config.ucode_package = read_ucode_package.value;

    let read_gpu_driver = root.common.read_text(top, "gpu_driver", "gpu_driver");
    if (read_gpu_driver.error != "") {
        return ConfigParse { config: config, error: read_gpu_driver.error };
    }
    config.gpu_driver = read_gpu_driver.value;

    let read_shared_secret = root.common.read_text(top, "shared_secret", "shared_secret");
    if (read_shared_secret.error != "") {
        return ConfigParse { config: config, error: read_shared_secret.error };
    }
    config.shared_secret = read_shared_secret.value;

    let read_console_keymap = root.common.read_text(top, "console_keymap", "console_keymap");
    if (read_console_keymap.error != "") {
        return ConfigParse { config: config, error: read_console_keymap.error };
    }
    config.console_keymap = read_console_keymap.value;

    let read_timezone = root.common.read_text(top, "timezone", "timezone");
    if (read_timezone.error != "") {
        return ConfigParse { config: config, error: read_timezone.error };
    }
    config.timezone = read_timezone.value;

    let read_hostname = root.common.read_text(top, "hostname", "hostname");
    if (read_hostname.error != "") {
        return ConfigParse { config: config, error: read_hostname.error };
    }
    config.hostname = read_hostname.value;


    let swap_problem = read_swap(top, config);
    if (swap_problem != "") {
        return ConfigParse { config: config, error: swap_problem };
    }

    let users_problem = read_users(top, config);
    if (users_problem != "") {
        return ConfigParse { config: config, error: users_problem };
    }

    let dotfiles_problem = read_dotfiles(top, config);
    if (dotfiles_problem != "") {
        return ConfigParse { config: config, error: dotfiles_problem };
    }

    let store_problem = read_secret_store(top, config);
    if (store_problem != "") {
        return ConfigParse { config: config, error: store_problem };
    }
    if (config.secret_store != null && config.dotfiles == null) {
        return ConfigParse {
            config: config,
            error: "secret_store is only read with dotfiles: nothing else uses one.",
        };
    }

    let message_problem = read_return_message(top, config);
    if (message_problem != "") {
        return ConfigParse { config: config, error: message_problem };
    }

    ConfigParse { config: config, error: "" }
}

function read_swap(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (top.keys().includes("swap")) {
        let raw = top.get("swap");
        let fields = root.common.as_map(raw) ?? root.common.empty_json_map();
        if (root.common.as_map(raw) == null) {
            return "swap must be a mapping.";
        }
        if let unknown: string = root.common.unknown_key(fields, allowed_swap_keys()) {
            return `Unknown key in config file: swap.${unknown}`;
        }
        if (fields.keys().includes("zram_gb")) {
            let zram = fields.get("zram_gb");
            if let size: int = root.common.as_int(zram) {
                config.swap.zram_gb = size;
            } else {
                return "swap.zram_gb must be a non-negative integer.";
            }
        }
        if (fields.keys().includes("swapfile_gb")) {
            let swapfile = fields.get("swapfile_gb");
            if let size: int = root.common.as_int(swapfile) {
                config.swap.swapfile_gb = size;
            } else {
                return "swap.swapfile_gb must be a non-negative integer.";
            }
        }
        if (config.swap.zram_gb < 0 || config.swap.swapfile_gb < 0) {
            return "Swap sizes must be non-negative integers.";
        }
    }
    ""
}

function read_users(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (top.keys().includes("work_contexts")) {
        let raw = top.get("work_contexts");
        if let names: string[] = root.common.text_list(raw) {
            let parsed = parse_work_contexts_csv(names.join(","));
            if (parsed.error != "") {
                return parsed.error;
            }
            config.work_contexts = parsed.work_contexts;
        } else {
            return "work_contexts must be a list of names.";
        }
    } else {
        return "At least one valid work context name is required.";
    }

    if (top.keys().includes("preserved_work_contexts")) {
        let raw = top.get("preserved_work_contexts");
        if let names: string[] = root.common.text_list(raw) {
            let parsed = parse_optional_work_contexts_csv(names.join(","));
            if (parsed.error != "") {
                return parsed.error;
            }
            config.preserved_work_contexts = parsed.work_contexts;
        } else {
            return "preserved_work_contexts must be a list of names.";
        }
    }
    ""
}

//# a section that is there turns its feature on; there is no separate flag
function read_dotfiles(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    let read = read_source(top, "dotfiles", package_origins(), "dotfiles");
    if (read.error != "") {
        return read.error;
    }
    if (read.present) {
        //# the project ships no dotfiles, so there is nothing for a default to
        //# mean here: a section that is there names where its content is
        if (is_default_source(read.source)) {
            return "dotfiles.origin cannot be default: the project carries no dotfiles.";
        }
        config.dotfiles = read.source;
    }
    ""
}

//# the store is one file, so it is named the way a file is named, and the
//# passphrase sits beside it because there is nobody at the terminal to type one
function read_secret_store(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (!top.keys().includes("secret_store")) {
        return "";
    }
    let raw = top.get("secret_store");
    let fields = root.common.as_map(raw) ?? root.common.empty_json_map();
    if (root.common.as_map(raw) == null) {
        return "secret_store must be a mapping.";
    }
    if let unknown: string = root.common.unknown_key(fields, allowed_secret_store_keys()) {
        return `Unknown key in config file: secret_store.${unknown}`;
    }

    let archive = read_source(fields, "archive", file_origins(), "secret_store.archive");
    if (archive.error != "") {
        return archive.error;
    }
    if (!archive.present) {
        return "secret_store.archive is required.";
    }
    let passphrase = root.common.read_text(fields, "passphrase", "secret_store.passphrase");
    if (passphrase.error != "") {
        return passphrase.error;
    }
    if (passphrase.value == "") {
        return "secret_store.passphrase cannot be empty.";
    }

    config.secret_store = SecretStoreInput { archive: archive.source, passphrase: passphrase.value };
    ""
}

/// The keys of the section that are the installer's rather than the values
/// format's: where the template package and the theme come from, which this
/// file names because the installer is what resolves them.
function return_message_source_keys() -> string[] {
    ["template", "theme"]
}

/// The section is the values format of
/// `docs/tools/oparch-return-message-render/002-values-format.md`, embedded,
/// plus the two keys above. The values are read by the code that owns that
/// format, so that the installer and the renderer cannot disagree about what a
/// values file means; the two origins are read here, because they are ours.
function read_return_message(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (top.keys().includes("return_message")) {
        let raw = top.get("return_message");
        let section = root.common.as_map(raw) ?? root.common.empty_json_map();
        if (root.common.as_map(raw) == null) {
            return "return_message must be a mapping.";
        }

        let parsed = root.return_message.parse_return_message(
            section, "return_message.", return_message_source_keys());
        if (parsed.error != "") {
            return parsed.error;
        }

        let template = read_source(section, "template", package_origins(),
                                               "return_message.template");
        if (template.error != "") {
            return template.error;
        }
        let theme = read_source(section, "theme", package_origins(),
                                            "return_message.theme");
        if (theme.error != "") {
            return theme.error;
        }

        //# the values format carries this key and does not read it: where the
        //# logo came from is the installer's question, so the installer reads it
        let logo = read_source(section, "logo", file_origins(), "return_message.logo");
        if (logo.error != "") {
            return logo.error;
        }

        //# a key that is not there is the project's own, which is what the
        //# format says an absent origin means
        config.return_message = ReturnMessageInput {
            template: template.source,
            theme: theme.source,
            values: parsed.message,
            logo: if (logo.present) { logo.source } else { null },
        };
    }
    ""
}

// ------------------------------------------------- checks against the system

function one_of(value: string, options: string[]) -> bool {
    options.includes(value)
}

/// Everything the file cannot decide on its own: that the disk is really a
/// block device, that the timezone exists, that the templates are installed.
/// Returns "" when the config describes something this machine can install.
function check_config(shell: root.common.Shell, files: root.common.Files, secrets: Secrets,
                      config: InstallConfig, asset_dir: string) -> string {
    //# everything the file points at is brought here first, before a single
    //# check has been made: this is the last moment at which a medium is
    //# certainly still attached and the target disk certainly still intact
    let brought = bring_every_source(shell, files, config, live_staging_dir());
    if (brought != "") {
        return brought;
    }

    if (config.disk == "") {
        return "disk cannot be empty.";
    }
    if (shell.capture("test", ["-b", config.disk]).exit_code != 0) {
        return `disk must be an existing block device: ${config.disk}`;
    }
    if (!one_of(config.install_mode, ["wipe-all", "keep-homes"])) {
        return "install_mode must be wipe-all or keep-homes.";
    }
    //# the format admits it, the installer does not implement it, and this is
    //# the last place a file-driven run can be stopped before the disk is touched
    if (config.install_mode == "keep-homes") {
        return "keep-homes is not implemented yet.";
    }
    if (!one_of(config.ucode_package, ["intel-ucode", "amd-ucode", "none"])) {
        return "ucode_package must be intel-ucode, amd-ucode, or none.";
    }
    if (!one_of(config.gpu_driver, ["nvidia-open", "none"])) {
        return "gpu_driver must be nvidia-open or none.";
    }
    if (config.shared_secret == "") {
        return "shared_secret cannot be empty.";
    }
    if (config.console_keymap == "") {
        return "console_keymap cannot be empty.";
    }

    //# the same list the picker offers, so both entry points accept the same set
    if (!list_timezones(shell).includes(config.timezone)) {
        return `Invalid timezone: ${config.timezone}`;
    }
    if (!validate_hostname(config.hostname)) {
        return "Invalid hostname.";
    }

    //# the map decides what the package has to hold, and only the tool reads
    //# maps; it is asked here, after the hostname and the users it plans for
    //# have been found sound, and before the disk is touched
    if (config.dotfiles != null) {
        let wanted = required_dotfiles_secrets(shell, config, live_staging_dir());
        if (wanted.error != "") {
            return wanted.error;
        }
        //# a store is only opened and judged when the map asks for one, and what
        //# judges it is the same plan, this time held to the files being there.
        //# A file that names no store and needs one is answered by the tool
        //# naming what is missing, rather than by a sentence written here.
        if (wanted.files.length() > 0) {
            if let store: SecretStoreInput = config.secret_store {
                let failure = open_secret_store(shell, files, secrets, store.passphrase,
                                                live_staging_dir());
                if (failure != "") {
                    return failure;
                }
            }
            let refused = check_staged_secrets(shell, config, live_staging_dir());
            if (refused != "") {
                return refused;
            }
        }
    }

    //# the package decides which languages exist and which fields are needed,
    //# and the theme how many languages it has an arrangement for; both are
    //# read here so that a message that cannot be drawn is refused before the
    //# disk is touched
    if let message: ReturnMessageInput = config.return_message {
        //# already brought here, so both are read from where they landed
        let loaded = root.return_message.load_package(
            files, package_directory(asset_dir, message.template));
        if (loaded.error != "") {
            return loaded.error;
        }
        let problem = root.return_message.check_values(loaded.package, message.values,
                                                       "return_message.");
        if (problem != "") {
            return problem;
        }

        let theme = root.return_message.load_theme(
            shell, files, theme_directory(asset_dir, message.theme));
        if (theme.error != "") {
            return theme.error;
        }
        return root.return_message.check_language_count(theme.theme, message.values);
    }
    ""
}

// -------------------------------------------------------------------- tests

/// A complete configuration, used by the tests here and by the flow tests.
function full_config_text() -> string {
    "# a complete configuration\n"
        + "disk: /dev/sda\n"
        + "install_mode: wipe-all\n"
        + "ucode_package: amd-ucode\n"
        + "gpu_driver: none\n"
        + "swap:\n"
        + "  zram_gb: 8\n"
        + "  swapfile_gb: 0\n"
        + "work_contexts:\n"
        + "  - ivan\n"
        + "shared_secret: \"hunter2\"\n"
        + "console_keymap: es\n"
        + "timezone: Europe/Madrid\n"
        + "hostname: oparch\n"
}

/// A filesystem holding the project's package and its theme, for tests that
/// validate a configuration against them.
function packaged_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/assets/return-message/manifest.yaml", root.return_message.sample_manifest());
    files.write("/assets/return-message/es.txt", "Hola {{owner_name}}[[, {{phone}}]]");
    files.write("/assets/return-message/ca.txt", "Hola {{owner_name}}");
    files.write("/assets/return-message-theme/manifest.yaml", root.return_message.sample_theme());
    files.write("/assets/pacman-hooks/90-oparch-netboot.hook", "[Trigger]\nTarget = ipxe\n");
    files.write("/assets/pacman-hooks/90-oparch-grub.hook", "[Trigger]\nTarget = grub\n");
    files.write("/assets/pacman-hooks/90-oparch-microcode-amd.hook",
                "[Trigger]\nTarget = boot/amd-ucode.img\n");
    files.write("/assets/pacman-hooks/90-oparch-microcode-intel.hook",
                "[Trigger]\nTarget = boot/intel-ucode.img\n");
    files
}

/// The same, with a third language in the package. What the package offers and
/// what the theme lays out are different limits, and telling them apart needs a
/// package offering a number the theme has no arrangement for.
function three_language_files() -> root.common.RecordingFiles {
    let files = packaged_files();
    files.write("/assets/return-message/manifest.yaml",
                root.return_message.sample_manifest() + "  - code: \"en\"\n    name: \"English\"\n");
    files.write("/assets/return-message/en.txt", "Hello {{owner_name}}");
    files
}

function checking_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [],
        streamed: [],
        fed: [],
        exit_codes: {},
        replies: {
            "timedatectl list-timezones": "Europe/Madrid\nUTC\n",
        },
    }
}

test "parse_config_file reads a complete file" {
    let parsed = parse_config_file(full_config_text());

    assert.equal(parsed.error, "");
    assert.equal(parsed.config.disk, "/dev/sda");
    assert.equal(parsed.config.swap.zram_gb, 8);
    assert.equal(parsed.config.work_contexts, ["ivan"]);
    assert.equal(parsed.config.shared_secret, "hunter2");
    assert.equal(parsed.config.timezone, "Europe/Madrid")
}

test "an absent section leaves its feature off" {
    let parsed = parse_config_file(full_config_text());
    assert.is_true(parsed.config.dotfiles == null);
    assert.is_true(parsed.config.return_message == null)
}

test "a section that is present turns its feature on" {
    let text = full_config_text()
        + "dotfiles:\n  origin: git\n  location: \"https://example.invalid/dotfiles.git\"\n"
        + "return_message:\n  languages:\n    - es\n  fields:\n    phone: \"+376 000 000\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    if let dotfiles: Source = parsed.config.dotfiles {
        assert.equal(dotfiles.origin, "git");
        assert.equal(dotfiles.location, "https://example.invalid/dotfiles.git")
    }
    if let message: ReturnMessageInput = parsed.config.return_message {
        assert.equal(message.values.languages, ["es"]);
        assert.equal(message.values.fields.get("phone"), "+376 000 000")
    }
}

test "a value YAML would read as a number must be quoted" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - es\n  fields:\n    phone: +376000000555666\n";

    assert.equal(parse_config_file(text).error,
                 "return_message.fields.phone must be quoted: YAML read it as a number, not as text."
                     + " Wrap the value in double quotes.")
}

test "quoting keeps the value exactly as written" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - es\n  fields:\n    phone: \"+376000000555666\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    if let message: ReturnMessageInput = parsed.config.return_message {
        assert.equal(message.values.fields.get("phone"), "+376000000555666")
    }
}

test "the rule applies to every text value, not only to message fields" {
    assert.equal(parse_config_file("disk: /dev/sda\nwork_contexts:\n  - ivan\nhostname: 12345\n").error,
                 "hostname must be quoted: YAML read it as a number, not as text."
                     + " Wrap the value in double quotes.")
}

test "field names are the template's, so they are not refused" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - ca\n  fields:\n"
        + "    police_contact: Policia d'Andorra\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    if let message: ReturnMessageInput = parsed.config.return_message {
        assert.equal(message.values.fields.get("police_contact"), "Policia d'Andorra")
    }
}

test "an unknown key is refused, at the top level and inside a section" {
    assert.equal(parse_config_file("disk: /dev/sda\nwat: 1\n").error,
                 "Unknown key in config file: wat");
    assert.equal(
        parse_config_file("disk: /dev/sda\nwork_contexts:\n  - ivan\nswap:\n  wat: 1\n").error,
        "Unknown key in config file: swap.wat")
}

test "invalid YAML is reported as such" {
    assert.is_true(parse_config_file("disk: [unclosed\n").error.starts_with("Invalid YAML"))
}

test "a bad value is reported with the key that carries it" {
    assert.equal(
        parse_config_file("disk: /dev/sda\nwork_contexts:\n  - ivan\nswap:\n  zram_gb: lots\n").error,
        "swap.zram_gb must be a non-negative integer.");
    assert.equal(parse_config_file("disk: /dev/sda\nwork_contexts:\n  - Ivan\n").error,
                 "Invalid work context name: Ivan")
}

test "a return message must name at least one language" {
    let text = full_config_text() + "return_message:\n  fields: {}\n";
    assert.equal(parse_config_file(text).error,
                 "return_message.languages must name at least one language.")
}

test "check_config accepts a configuration this machine can install" {
    let shell = checking_shell();
    let parsed = parse_config_file(full_config_text());

    assert.equal(check_config(shell, packaged_files(), recording_secrets(), parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes("test -b /dev/sda"))
}

test "check_config rejects a disk that is not a block device" {
    let shell = checking_shell();
    let _ = shell.exit_codes.set("test -b /dev/sda", 1);
    let parsed = parse_config_file(full_config_text());

    assert.equal(check_config(shell, packaged_files(), recording_secrets(), parsed.config, "/assets"),
                 "disk must be an existing block device: /dev/sda")
}

test "check_config rejects keep-homes before anything is touched" {
    let parsed = parse_config_file(full_config_text());
    parsed.config.install_mode = "keep-homes";

    assert.equal(check_config(checking_shell(), packaged_files(), recording_secrets(), parsed.config, "/assets"),
                 "keep-homes is not implemented yet.")
}

test "check_config rejects a timezone that is not in the canonical list" {
    let parsed = parse_config_file(full_config_text());
    parsed.config.timezone = "Mars/Olympus";

    assert.equal(check_config(checking_shell(), packaged_files(), recording_secrets(), parsed.config, "/assets"),
                 "Invalid timezone: Mars/Olympus")
}

test "a template named by URL is fetched before it is read" {
    let shell = checking_shell();
    let _ = shell.replies.set(
        "tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\nes.txt\nca.txt\n");
    let files = packaged_files();
    files.write("/tmp/oparch/template-package/manifest.yaml", root.return_message.sample_manifest());
    files.write("/tmp/oparch/template-package/es.txt", "Hola {{owner_name}}");
    files.write("/tmp/oparch/template-package/ca.txt", "Hola {{owner_name}}");

    let text = full_config_text()
        + "return_message:\n  template:\n    origin: tar\n"
        + "    location: \"https://example.invalid/pkg.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    assert.equal(check_config(shell, files, recording_secrets(), parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes("tar -tf /tmp/oparch/template-package.tar"))
}

test "check_config refuses a theme that is not where the file says" {
    let shell = checking_shell();
    //# neither a directory nor a file, which is what makes it unreachable
    let _ = shell.exit_codes.set("test -d /nowhere", 1);

    let text = full_config_text()
        + "return_message:\n  theme:\n    origin: local\n    location: \"/nowhere\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    //# the location the file named, not the staging path it would have landed in
    assert.equal(check_config(shell, packaged_files(), recording_secrets(), parsed.config, "/assets"),
                 "The theme is not there: /nowhere")
}

test "check_config refuses a number of languages the theme does not lay out" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - \"es\"\n    - \"ca\"\n    - \"en\"\n"
        + "  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    //# the package offers all three; the theme is what refuses three of them
    assert.equal(check_config(checking_shell(), three_language_files(), recording_secrets(), parsed.config, "/assets"),
                 "The theme lays out 1, 2 or 4 languages, and 3 were selected.")
}

test "a theme named by URL is fetched into a directory of its own" {
    let shell = checking_shell();
    let _ = shell.replies.set("tar -tf /tmp/oparch/theme.tar", "manifest.yaml\n");
    let files = packaged_files();
    files.write("/tmp/oparch/theme/manifest.yaml", root.return_message.sample_theme());

    let text = full_config_text()
        + "return_message:\n  theme:\n    origin: tar\n"
        + "    location: \"https://example.invalid/theme.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(check_config(shell, files, recording_secrets(), parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes(
        "tar -xf /tmp/oparch/theme.tar -C /tmp/oparch/theme"))
}

test "everything the file names is brought here before a single check is made" {
    let shell = checking_shell();
    let text = full_config_text()
        + "dotfiles:\n  origin: git\n  location: \"https://example.invalid/dotfiles.git\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    assert.equal(check_config(shell, packaged_files(), recording_secrets(), parsed.config, "/assets"), "");
    //# nothing consumes the dotfiles yet, and it is brought all the same: the
    //# medium it came from is gone once the installation starts
    assert.is_true(shell.commands.includes(
        "git clone https://example.invalid/dotfiles.git /tmp/oparch/dotfiles"))
}

test "a source that cannot be brought here stops the run before anything is checked" {
    let shell = checking_shell();
    let _ = shell.exit_codes.set(
        "git clone https://example.invalid/gone.git /tmp/oparch/dotfiles", 128);
    let text = full_config_text()
        + "dotfiles:\n  origin: git\n  location: \"https://example.invalid/gone.git\"\n";
    let parsed = parse_config_file(text);

    assert.equal(check_config(shell, packaged_files(), recording_secrets(), parsed.config, "/assets"),
                 "Cloning the dotfiles package from https://example.invalid/gone.git"
                     + " failed with exit code 128.");
    //# the disk was never even looked at
    assert.is_true(!shell.commands.includes("test -b /dev/sda"))
}

test "a package fetched from a URL that tries to escape is refused" {
    let shell = checking_shell();
    let _ = shell.replies.set(
        "tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\n../../etc/passwd\n");

    let text = full_config_text()
        + "return_message:\n  template:\n    origin: tar\n"
        + "    location: \"https://example.invalid/pkg.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(check_config(shell, root.common.recording_files(), recording_secrets(), parsed.config, "/assets"),
                 "The template package holds an entry that would be written outside it: ../../etc/passwd");
    assert.is_true(!shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package"))
}
