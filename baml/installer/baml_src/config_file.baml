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
        "disk", "install_mode", "preserved_home_users", "ucode_package", "gpu_driver",
        "swap", "login_users", "shared_secret", "console_keymap", "timezone",
        "hostname", "dotfiles", "return_message",
    ]
}

function allowed_swap_keys() -> string[] {
    ["zram_gb", "swapfile_gb"]
}

function allowed_dotfiles_keys() -> string[] {
    ["repository_url"]
}

function allowed_return_message_keys() -> string[] {
    ["template", "languages", "fields", "logo_url"]
}

// ------------------------------------------------------------- reading yaml

/// A scalar as text. Only a YAML string counts: a value YAML read as a number
/// comes back in its canonical form, which is not what was written. `+34600...`
/// would lose its `+`, and `1.10` its trailing zero, without anything failing.
function as_text(value: baml.json.json) -> string? {
    match (value) {
        let s: string => s,
        _ => null,
    }
}

/// A text value read from a mapping. Distinguishes absent from present-but-not
/// text, so a number cannot quietly become an empty string.
class TextRead {
    value: string,
    error: string,
}

/// What YAML made of a value, for an error message. The value itself is never
/// echoed back: what arrives is already the canonical form of whatever YAML
/// decided, so repeating it would suggest the very value that was lost.
function json_kind(value: baml.json.json) -> string {
    match (value) {
        let b: bool => "a boolean",
        let i: int => "a number",
        let f: float => "a number",
        let s: string => "text",
        let items: baml.json.json[] => "a list",
        let entries: map<string, baml.json.json> => "a mapping",
        _ => "nothing",
    }
}

function read_text(entries: map<string, baml.json.json>, key: string, path: string) -> TextRead {
    if (!entries.keys().includes(key)) {
        return TextRead { value: "", error: "" };
    }
    let value = entries.get(key);
    if let text: string = as_text(value) {
        return TextRead { value: text, error: "" };
    }
    TextRead {
        value: "",
        error: `${path} must be quoted: YAML read it as ${json_kind(value)}, not as text.`
            + " Wrap the value in double quotes.",
    }
}

function as_int(value: baml.json.json) -> int? {
    match (value) {
        let i: int => i,
        _ => null,
    }
}

function as_map(value: baml.json.json) -> map<string, baml.json.json>? {
    match (value) {
        let entries: map<string, baml.json.json> => entries,
        _ => null,
    }
}

function empty_names() -> string[] {
    let empty: string[] = [];
    empty
}

function empty_json_map() -> map<string, baml.json.json> {
    let empty: map<string, baml.json.json> = {};
    empty
}



/// The first name in `entries` that is not in `allowed`, if any.
function unknown_key(entries: map<string, baml.json.json>, allowed: string[]) -> string? {
    for (let key in entries.keys()) {
        if (!allowed.includes(key)) {
            return key;
        }
    }
    null
}

/// Reads a list of names, refusing anything that is not a scalar.
function text_list(value: baml.json.json) -> string[]? {
    match (value) {
        let items: baml.json.json[] => {
            let names: string[] = [];
            for (let item in items) {
                if let text: string = as_text(item) {
                    names.push(text);
                } else {
                    return null;
                }
            }
            names
        },
        _ => null,
    }
}

// ----------------------------------------------------------------- the file

function parse_config_file(text: string) -> ConfigParse {
    let document = baml.yaml.parse(text)
        catch (e) {
            _ => {
                return ConfigParse { config: empty_config(), error: `Invalid YAML: ${e.message}` };
            }
        };

    let top = as_map(document) ?? empty_json_map();
    if (as_map(document) == null) {
        return ConfigParse { config: empty_config(), error: "The configuration must be a mapping." };
    }
    if let unknown: string = unknown_key(top, allowed_top_keys()) {
        return ConfigParse { config: empty_config(), error: `Unknown key in config file: ${unknown}` };
    }

    let config = empty_config();
    let read_disk = read_text(top, "disk", "disk");
    if (read_disk.error != "") {
        return ConfigParse { config: config, error: read_disk.error };
    }
    config.disk = read_disk.value;

    let read_install_mode = read_text(top, "install_mode", "install_mode");
    if (read_install_mode.error != "") {
        return ConfigParse { config: config, error: read_install_mode.error };
    }
    config.install_mode = read_install_mode.value;

    let read_ucode_package = read_text(top, "ucode_package", "ucode_package");
    if (read_ucode_package.error != "") {
        return ConfigParse { config: config, error: read_ucode_package.error };
    }
    config.ucode_package = read_ucode_package.value;

    let read_gpu_driver = read_text(top, "gpu_driver", "gpu_driver");
    if (read_gpu_driver.error != "") {
        return ConfigParse { config: config, error: read_gpu_driver.error };
    }
    config.gpu_driver = read_gpu_driver.value;

    let read_shared_secret = read_text(top, "shared_secret", "shared_secret");
    if (read_shared_secret.error != "") {
        return ConfigParse { config: config, error: read_shared_secret.error };
    }
    config.shared_secret = read_shared_secret.value;

    let read_console_keymap = read_text(top, "console_keymap", "console_keymap");
    if (read_console_keymap.error != "") {
        return ConfigParse { config: config, error: read_console_keymap.error };
    }
    config.console_keymap = read_console_keymap.value;

    let read_timezone = read_text(top, "timezone", "timezone");
    if (read_timezone.error != "") {
        return ConfigParse { config: config, error: read_timezone.error };
    }
    config.timezone = read_timezone.value;

    let read_hostname = read_text(top, "hostname", "hostname");
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

    let message_problem = read_return_message(top, config);
    if (message_problem != "") {
        return ConfigParse { config: config, error: message_problem };
    }

    ConfigParse { config: config, error: "" }
}

function read_swap(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (top.keys().includes("swap")) {
        let raw = top.get("swap");
        let fields = as_map(raw) ?? empty_json_map();
        if (as_map(raw) == null) {
            return "swap must be a mapping.";
        }
        if let unknown: string = unknown_key(fields, allowed_swap_keys()) {
            return `Unknown key in config file: swap.${unknown}`;
        }
        if (fields.keys().includes("zram_gb")) {
            let zram = fields.get("zram_gb");
            if let size: int = as_int(zram) {
                config.swap.zram_gb = size;
            } else {
                return "swap.zram_gb must be a non-negative integer.";
            }
        }
        if (fields.keys().includes("swapfile_gb")) {
            let swapfile = fields.get("swapfile_gb");
            if let size: int = as_int(swapfile) {
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
    if (top.keys().includes("login_users")) {
        let raw = top.get("login_users");
        if let names: string[] = text_list(raw) {
            let parsed = parse_login_users_csv(names.join(","));
            if (parsed.error != "") {
                return parsed.error;
            }
            config.login_users = parsed.users;
        } else {
            return "login_users must be a list of names.";
        }
    } else {
        return "At least one valid login username is required.";
    }

    if (top.keys().includes("preserved_home_users")) {
        let raw = top.get("preserved_home_users");
        if let names: string[] = text_list(raw) {
            let parsed = parse_optional_users_csv(names.join(","));
            if (parsed.error != "") {
                return parsed.error;
            }
            config.preserved_home_users = parsed.users;
        } else {
            return "preserved_home_users must be a list of names.";
        }
    }
    ""
}

//# a section that is there turns its feature on; there is no separate flag
function read_dotfiles(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (top.keys().includes("dotfiles")) {
        let raw = top.get("dotfiles");
        let fields = as_map(raw) ?? empty_json_map();
        if (as_map(raw) == null) {
            return "dotfiles must be a mapping.";
        }
        if let unknown: string = unknown_key(fields, allowed_dotfiles_keys()) {
            return `Unknown key in config file: dotfiles.${unknown}`;
        }
        let url = read_text(fields, "repository_url", "dotfiles.repository_url");
        if (url.error != "") {
            return url.error;
        }
        if (url.value == "") {
            return "dotfiles.repository_url is required.";
        }
        config.dotfiles = DotfilesConfig { repository_url: url.value };
    }
    ""
}

function read_return_message(top: map<string, baml.json.json>, config: InstallConfig) -> string {
    if (top.keys().includes("return_message")) {
        let raw = top.get("return_message");
        let section = as_map(raw) ?? empty_json_map();
        if (as_map(raw) == null) {
            return "return_message must be a mapping.";
        }
        if let unknown: string = unknown_key(section, allowed_return_message_keys()) {
            return `Unknown key in config file: return_message.${unknown}`;
        }

        let languages: string[] = if (section.keys().includes("languages")) {
            text_list(section.get("languages")) ?? empty_names()
        } else {
            empty_names()
        };
        for (let code in languages) {
            if (!validate_language_code(code)) {
                return `Invalid return-message language code: ${code}`;
            }
        }
        if (languages.length() < 1 || languages.length() > 4) {
            return "return_message.languages must include between 1 and 4 languages.";
        }

        //# the names here belong to the template, so they are not checked
        //# against a list the installer knows
        let values: map<string, string> = {};
        if (section.keys().includes("fields")) {
            let raw_fields = section.get("fields");
            let declared = as_map(raw_fields) ?? empty_json_map();
            if (as_map(raw_fields) == null) {
                return "return_message.fields must be a mapping.";
            }
            for (let name in declared.keys()) {
                let value = read_text(declared, name, `return_message.fields.${name}`);
                if (value.error != "") {
                    return value.error;
                }
                let _ = values.set(name, value.value);
            }
        }

        let template = read_text(section, "template", "return_message.template");
        if (template.error != "") {
            return template.error;
        }
        let logo = read_text(section, "logo_url", "return_message.logo_url");
        if (logo.error != "") {
            return logo.error;
        }
        config.return_message = ReturnMessageConfig {
            template: template.value,
            languages: languages,
            fields: values,
            logo_url: logo.value,
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
function check_config(shell: root.common.Shell, files: root.common.Files,
                      config: InstallConfig, asset_dir: string) -> string {
    if (config.disk == "") {
        return "disk cannot be empty.";
    }
    if (shell.capture("test", ["-b", config.disk]).exit_code != 0) {
        return `disk must be an existing block device: ${config.disk}`;
    }
    if (!one_of(config.install_mode, ["wipe-all", "keep-homes"])) {
        return "install_mode must be wipe-all or keep-homes.";
    }
    if (!one_of(config.ucode_package, ["intel-ucode", "amd-ucode", "none"])) {
        return "ucode_package must be intel-ucode, amd-ucode, or none.";
    }
    if (!one_of(config.gpu_driver, ["nvidia", "nvidia-open", "nouveau", "none"])) {
        return "gpu_driver must be nvidia, nvidia-open, nouveau, or none.";
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

    //# the package decides which languages exist and which fields are needed
    if let message: ReturnMessageConfig = config.return_message {
        let loaded = resolve_package(shell, files, asset_dir, message.template);
        if (loaded.error != "") {
            return loaded.error;
        }
        let available = package_language_codes(loaded.package);
        for (let code in message.languages) {
            if (!available.includes(code)) {
                return `The template package offers no message in ${code}.`;
            }
        }
        if let missing: string = missing_required_field(loaded.package, message.fields) {
            return `return_message.fields.${missing} is required by the template package.`;
        }
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
        + "login_users:\n"
        + "  - ivan\n"
        + "shared_secret: \"hunter2\"\n"
        + "console_keymap: es\n"
        + "timezone: Europe/Madrid\n"
        + "hostname: oparch\n"
}

/// A filesystem holding the project's package, for tests that validate a
/// configuration against it.
function packaged_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.write("/assets/return-message/manifest.yaml", sample_manifest());
    files.write("/assets/return-message/es.txt", "Hola {{owner_name}}[[, {{phone}}]]");
    files.write("/assets/return-message/ca.txt", "Hola {{owner_name}}");
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
    assert.equal(parsed.config.login_users, ["ivan"]);
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
        + "dotfiles:\n  repository_url: https://example.invalid/dotfiles.git\n"
        + "return_message:\n  languages:\n    - es\n  fields:\n    phone: \"666 555 666\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    if let dotfiles: DotfilesConfig = parsed.config.dotfiles {
        assert.equal(dotfiles.repository_url, "https://example.invalid/dotfiles.git")
    }
    if let message: ReturnMessageConfig = parsed.config.return_message {
        assert.equal(message.languages, ["es"]);
        assert.equal(message.fields.get("phone"), "666 555 666")
    }
}

test "a value YAML would read as a number must be quoted" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - es\n  fields:\n    phone: +34666555666\n";

    assert.equal(parse_config_file(text).error,
                 "return_message.fields.phone must be quoted: YAML read it as a number, not as text."
                     + " Wrap the value in double quotes.")
}

test "quoting keeps the value exactly as written" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - es\n  fields:\n    phone: \"+34666555666\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    if let message: ReturnMessageConfig = parsed.config.return_message {
        assert.equal(message.fields.get("phone"), "+34666555666")
    }
}

test "the rule applies to every text value, not only to message fields" {
    assert.equal(parse_config_file("disk: /dev/sda\nlogin_users:\n  - ivan\nhostname: 12345\n").error,
                 "hostname must be quoted: YAML read it as a number, not as text."
                     + " Wrap the value in double quotes.")
}

test "field names are the template's, so they are not refused" {
    let text = full_config_text()
        + "return_message:\n  languages:\n    - ca\n  fields:\n"
        + "    police_contact: Policia d'Andorra\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    if let message: ReturnMessageConfig = parsed.config.return_message {
        assert.equal(message.fields.get("police_contact"), "Policia d'Andorra")
    }
}

test "an unknown key is refused, at the top level and inside a section" {
    assert.equal(parse_config_file("disk: /dev/sda\nwat: 1\n").error,
                 "Unknown key in config file: wat");
    assert.equal(
        parse_config_file("disk: /dev/sda\nlogin_users:\n  - ivan\nswap:\n  wat: 1\n").error,
        "Unknown key in config file: swap.wat")
}

test "invalid YAML is reported as such" {
    assert.is_true(parse_config_file("disk: [unclosed\n").error.starts_with("Invalid YAML"))
}

test "a bad value is reported with the key that carries it" {
    assert.equal(
        parse_config_file("disk: /dev/sda\nlogin_users:\n  - ivan\nswap:\n  zram_gb: lots\n").error,
        "swap.zram_gb must be a non-negative integer.");
    assert.equal(parse_config_file("disk: /dev/sda\nlogin_users:\n  - Ivan\n").error,
                 "Invalid username: Ivan")
}

test "a return message must name between one and four languages" {
    let text = full_config_text() + "return_message:\n  fields: {}\n";
    assert.equal(parse_config_file(text).error,
                 "return_message.languages must include between 1 and 4 languages.")
}

test "check_config accepts a configuration this machine can install" {
    let shell = checking_shell();
    let parsed = parse_config_file(full_config_text());

    assert.equal(check_config(shell, packaged_files(), parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes("test -b /dev/sda"))
}

test "check_config rejects a disk that is not a block device" {
    let shell = checking_shell();
    let _ = shell.exit_codes.set("test -b /dev/sda", 1);
    let parsed = parse_config_file(full_config_text());

    assert.equal(check_config(shell, packaged_files(), parsed.config, "/assets"),
                 "disk must be an existing block device: /dev/sda")
}

test "check_config rejects a timezone that is not in the canonical list" {
    let parsed = parse_config_file(full_config_text());
    parsed.config.timezone = "Mars/Olympus";

    assert.equal(check_config(checking_shell(), packaged_files(), parsed.config, "/assets"),
                 "Invalid timezone: Mars/Olympus")
}

test "a template named by URL is fetched before it is read" {
    let shell = checking_shell();
    let _ = shell.replies.set(
        "tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\nes.txt\nca.txt\n");
    let files = root.common.recording_files();
    files.write("/tmp/oparch/template-package/manifest.yaml", sample_manifest());
    files.write("/tmp/oparch/template-package/es.txt", "Hola {{owner_name}}");
    files.write("/tmp/oparch/template-package/ca.txt", "Hola {{owner_name}}");

    let text = full_config_text()
        + "return_message:\n  template: \"https://example.invalid/pkg.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(parsed.error, "");
    assert.equal(check_config(shell, files, parsed.config, "/assets"), "");
    assert.is_true(shell.commands.includes("tar -tf /tmp/oparch/template-package.tar"))
}

test "a package fetched from a URL that tries to escape is refused" {
    let shell = checking_shell();
    let _ = shell.replies.set(
        "tar -tf /tmp/oparch/template-package.tar", "manifest.yaml\n../../etc/passwd\n");

    let text = full_config_text()
        + "return_message:\n  template: \"https://example.invalid/pkg.tar\"\n"
        + "  languages:\n    - \"es\"\n  fields:\n    owner_name: \"Ivan\"\n";
    let parsed = parse_config_file(text);

    assert.equal(check_config(shell, root.common.recording_files(), parsed.config, "/assets"),
                 "The template package holds an entry that would be written outside it: ../../etc/passwd");
    assert.is_true(!shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/template-package"))
}
