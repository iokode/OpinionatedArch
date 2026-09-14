// The configuration file an unattended installation is read from, as defined
// in `docs/tools/oparch-installer/001-config-file-format.md`: the same
// InstallConfig the interactive form collects.
//
// Parsing is pure and lives here. What needs the live system is the library's
// `check_config`, which asks the Shell for it.

/// Either a config or the first thing wrong with the file.
class ConfigParse {
    config: root.installer.InstallConfig,
    error: string,
}

function allowed_top_keys() -> string[] {
    [
        "disk", "install_mode", "offline", "preserved_work_contexts", "ucode_package",
        "gpu_driver", "swap", "work_contexts", "shared_secret", "console_keymap",
        "timezone", "hostname", "dotfiles", "secret_store", "return_message",
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
                return ConfigParse { config: root.installer.empty_config(), error: `Invalid YAML: ${e.message}` };
            }
        };

    let top = root.common.as_map(document) ?? root.common.empty_json_map();
    if (root.common.as_map(document) == null) {
        return ConfigParse { config: root.installer.empty_config(), error: "The configuration must be a mapping." };
    }
    if let unknown: string = root.common.unknown_key(top, allowed_top_keys()) {
        return ConfigParse { config: root.installer.empty_config(), error: `Unknown key in config file: ${unknown}` };
    }

    let config = root.installer.empty_config();
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

    //# absent is the installation with a network, which is what a file written
    //# for a machine that has one says by saying nothing
    if (top.keys().includes("offline")) {
        if let chosen: bool = root.common.as_bool(top.get("offline")) {
            config.offline = chosen;
        } else {
            return ConfigParse { config: config, error: "offline must be true or false." };
        }
    }

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

function read_swap(top: map<string, baml.json.json>, config: root.installer.InstallConfig) -> string {
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

function read_users(top: map<string, baml.json.json>, config: root.installer.InstallConfig) -> string {
    if (top.keys().includes("work_contexts")) {
        let raw = top.get("work_contexts");
        if let names: string[] = root.common.text_list(raw) {
            let parsed = root.installer.parse_work_contexts_csv(names.join(","));
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
            let parsed = root.installer.parse_optional_work_contexts_csv(names.join(","));
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
function read_dotfiles(top: map<string, baml.json.json>, config: root.installer.InstallConfig) -> string {
    let read = root.installer.read_source(top, "dotfiles", root.installer.package_origins(), "dotfiles");
    if (read.error != "") {
        return read.error;
    }
    if (read.present) {
        //# the project ships no dotfiles, so there is nothing for a default to
        //# mean here: a section that is there names where its content is
        if (root.installer.is_default_source(read.source)) {
            return "dotfiles.origin cannot be default: the project carries no dotfiles.";
        }
        config.dotfiles = read.source;
    }
    ""
}

//# the store is one file, so it is named the way a file is named, and the
//# passphrase sits beside it because there is nobody at the terminal to type one
function read_secret_store(top: map<string, baml.json.json>, config: root.installer.InstallConfig) -> string {
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

    let archive = root.installer.read_source(fields, "archive", root.installer.file_origins(),
                                             "secret_store.archive");
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

    config.secret_store = root.installer.SecretStoreInput {
        archive: archive.source, passphrase: passphrase.value,
    };
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
function read_return_message(top: map<string, baml.json.json>, config: root.installer.InstallConfig) -> string {
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

        let template = root.installer.read_source(section, "template", root.installer.package_origins(),
                                                  "return_message.template");
        if (template.error != "") {
            return template.error;
        }
        let theme = root.installer.read_source(section, "theme", root.installer.package_origins(),
                                               "return_message.theme");
        if (theme.error != "") {
            return theme.error;
        }

        //# the values format carries this key and does not read it: where the
        //# logo came from is the installer's question, so the installer reads it
        let logo = root.installer.read_source(section, "logo", root.installer.file_origins(),
                                              "return_message.logo");
        if (logo.error != "") {
            return logo.error;
        }

        //# a key that is not there is the project's own, which is what the
        //# format says an absent origin means
        config.return_message = root.installer.ReturnMessageInput {
            template: template.source,
            theme: theme.source,
            values: parsed.message,
            logo: if (logo.present) { logo.source } else { null },
        };
    }
    ""
}

// -------------------------------------------------------------------- tests

/// A complete configuration, used by the tests here and by the run tests.
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
    if let dotfiles: root.installer.Source = parsed.config.dotfiles {
        assert.equal(dotfiles.origin, "git");
        assert.equal(dotfiles.location, "https://example.invalid/dotfiles.git")
    }
    if let message: root.installer.ReturnMessageInput = parsed.config.return_message {
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
    if let message: root.installer.ReturnMessageInput = parsed.config.return_message {
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
    if let message: root.installer.ReturnMessageInput = parsed.config.return_message {
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

    assert.equal(root.installer.check_config(shell, root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes("test -b /dev/sda"))
}

test "check_config rejects a disk that is not a block device" {
    let shell = checking_shell();
    let _ = shell.exit_codes.set("test -b /dev/sda", 1);
    let parsed = parse_config_file(full_config_text());

    assert.equal(root.installer.check_config(shell, root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "disk must be an existing block device: /dev/sda")
}

test "check_config rejects keep-homes before anything is touched" {
    let parsed = parse_config_file(full_config_text());
    parsed.config.install_mode = "keep-homes";

    assert.equal(root.installer.check_config(checking_shell(), root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "keep-homes is not implemented yet.")
}

test "a file says where the packages come from, and saying nothing says the network" {
    assert.equal(parse_config_file(full_config_text()).config.offline, false);
    assert.equal(parse_config_file(full_config_text() + "offline: true\n").config.offline, true);
    assert.equal(parse_config_file(full_config_text() + "offline: false\n").config.offline, false)
}

test "offline written as anything but a boolean is refused" {
    //# quoted, it is text, and a reader taking both would let the quoting
    //# decide whether this machine reaches for a network
    assert.equal(parse_config_file(full_config_text() + "offline: \"true\"\n").error,
                 "offline must be true or false.");
    assert.equal(parse_config_file(full_config_text() + "offline: 1\n").error,
                 "offline must be true or false.")
}

test "check_config takes offline on a medium that carries a repository" {
    let parsed = parse_config_file(full_config_text() + "offline: true\n");

    assert.equal(root.installer.check_config(checking_shell(), root.installer.medium_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"), "")
}

test "check_config refuses offline where there is nothing to install from" {
    let parsed = parse_config_file(full_config_text() + "offline: true\n");

    //# the disk is still whole at this point, which is the whole reason this
    //# is asked here and not when `pacstrap` discovers it
    assert.equal(root.installer.check_config(checking_shell(), root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "offline needs a medium carrying a repository of its own, and this one carries none.")
}

test "check_config rejects a timezone that is not in the canonical list" {
    let parsed = parse_config_file(full_config_text());
    parsed.config.timezone = "Mars/Olympus";

    assert.equal(root.installer.check_config(checking_shell(), root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "Invalid timezone: Mars/Olympus")
}

test "a template named by URL is fetched before it is read" {
    let shell = checking_shell();
    let _ = shell.replies.set(
        "tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\nes.txt\nca.txt\n");
    let files = root.installer.packaged_files();
    files.write("/tmp/oparch/template-package/manifest.yaml", root.return_message.sample_manifest());
    files.write("/tmp/oparch/template-package/es.txt", "Hola {{owner_name}}");
    files.write("/tmp/oparch/template-package/ca.txt", "Hola {{owner_name}}");

    let text = full_config_text()
        + "return_message:\n  template:\n    origin: tar\n"
        + "    location: \"https://example.invalid/pkg.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    assert.equal(root.installer.check_config(shell, files, root.installer.recording_secrets(),
                                             parsed.config, "/assets"), "");
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
    assert.equal(root.installer.check_config(shell, root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "The theme is not there: /nowhere")
}

test "check_config refuses a number of languages the theme does not lay out" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - \"es\"\n    - \"ca\"\n    - \"en\"\n"
        + "  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    //# the package offers all three; the theme is what refuses three of them
    assert.equal(root.installer.check_config(checking_shell(), root.installer.three_language_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "The theme lays out 1, 2 or 4 languages, and 3 were selected.")
}

test "a theme named by URL is fetched into a directory of its own" {
    let shell = checking_shell();
    let _ = shell.replies.set("tar -tf /tmp/oparch/theme.tar", "manifest.yaml\n");
    let files = root.installer.packaged_files();
    files.write("/tmp/oparch/theme/manifest.yaml", root.return_message.sample_theme());

    let text = full_config_text()
        + "return_message:\n  theme:\n    origin: tar\n"
        + "    location: \"https://example.invalid/theme.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(root.installer.check_config(shell, files, root.installer.recording_secrets(),
                                             parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes(
        "tar -xf /tmp/oparch/theme.tar -C /tmp/oparch/theme"))
}

test "everything the file names is brought here before a single check is made" {
    let shell = checking_shell();
    let text = full_config_text()
        + "dotfiles:\n  origin: git\n  location: \"https://example.invalid/dotfiles.git\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    assert.equal(root.installer.check_config(shell, root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"), "");
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

    assert.equal(root.installer.check_config(shell, root.installer.packaged_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
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

    assert.equal(root.installer.check_config(shell, root.common.recording_files(),
                                             root.installer.recording_secrets(), parsed.config, "/assets"),
                 "The template package holds an entry that would be written outside it: ../../etc/passwd");
    assert.is_true(!shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package"))
}
