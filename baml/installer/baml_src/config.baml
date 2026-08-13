// Everything the installer collects before it touches the disk.
//
// The shape mirrors the configuration file defined in
// `docs/tools/oparch-installer/001-config-file-format.md`, so that there is one
// vocabulary rather than a model and a translation layer between it and the
// file.

class SwapConfig {
    zram_gb: int,
    swapfile_gb: int,
}

//# the dotfiles package is content held elsewhere, like the template package
//# and the theme, so it is named the same way: an origin and a location

/// What the installer collected for the pre-boot return message: the values
/// themselves, and where the package and the theme that render them come from.
///
/// The values are the renderer's own format, and it reads them from the file
/// the installation leaves behind. The two origins are not in that format and
/// never reach it: the renderer is handed directories, and resolving an origin
/// into one is the installer's job.
class ReturnMessageInput {
    template: Source,
    theme: Source,
    values: root.return_message.ReturnMessageConfig,
    /// Where the logo was taken from, when there is one. It rides here rather
    /// than in the values the renderer reads, because choosing between a URL
    /// and a file on this machine is a question this installer asks and the
    /// renderer is handed the answer to.
    logo: Source?,
}

function empty_return_message_input() -> ReturnMessageInput {
    ReturnMessageInput {
        template: default_source(),
        theme: default_source(),
        values: root.return_message.empty_return_message(),
    }
}

class InstallConfig {
    disk: string,
    install_mode: string,
    preserved_home_users: string[],
    ucode_package: string,
    gpu_driver: string,
    swap: SwapConfig,
    login_users: string[],
    shared_secret: string,
    console_keymap: string,
    timezone: string,
    hostname: string,
    /// Absent when no dotfiles package is taken.
    dotfiles: Source?,
    /// Absent when there is no pre-boot return message.
    return_message: ReturnMessageInput?,
    /// Read from the disk once it is partitioned; not part of the file.
    root_part_uuid: string,
}

function empty_config() -> InstallConfig {
    InstallConfig {
        disk: "",
        install_mode: "",
        preserved_home_users: [],
        ucode_package: "",
        gpu_driver: "",
        swap: SwapConfig { zram_gb: 0, swapfile_gb: 0 },
        login_users: [],
        shared_secret: "",
        console_keymap: "",
        timezone: "",
        hostname: "",
        dotfiles: null,
        return_message: null,
        root_part_uuid: "",
    }
}

/// A source as the review screen shows it: what was chosen, and from where.
function describe_source(source: Source) -> string {
    if (is_default_source(source)) {
        return "the project's own";
    }
    `${source.origin}: ${source.location}`
}

/// One setting on the review screen. The label and the value are kept apart
/// because the screen draws them apart: aligned in two columns, and in two
/// colours. Joining them here would also have to be undone there, and a value
/// like `git: https://…` carries a colon of its own to be undone wrongly by.
class SummaryRow {
    label: string,
    value: string,
    /// True for a row that belongs to the one above it.
    nested: bool,
}

function row(label: string, value: string) -> SummaryRow {
    SummaryRow { label: label, value: value, nested: false }
}

function nested_row(label: string, value: string) -> SummaryRow {
    SummaryRow { label: label, value: value, nested: true }
}

/// The review screen, one row per setting.
function summary_rows(config: InstallConfig) -> SummaryRow[] {
    let rows = [
        row("target disk", config.disk),
        row("install mode", config.install_mode),
        row("preserved home users", config.preserved_home_users.join(", ")),
        row("ucode package", config.ucode_package),
        row("gpu driver", config.gpu_driver),
        row("zram size (GB)", `${config.swap.zram_gb}`),
        row("disk swapfile size (GB)", `${config.swap.swapfile_gb}`),
        row("login users", config.login_users.join(", ")),
        row("keymap", config.console_keymap),
        row("timezone", config.timezone),
        row("hostname", config.hostname),
    ];

    if let dotfiles: Source = config.dotfiles {
        rows.push(row("dotfiles package", describe_source(dotfiles)));
    } else {
        rows.push(row("dotfiles package", "none"));
    }

    if let message: ReturnMessageInput = config.return_message {
        let values = message.values;
        rows.push(row("return message", values.languages.join(", ")));
        rows.push(nested_row("template package", describe_source(message.template)));
        rows.push(nested_row("theme", describe_source(message.theme)));
        for (let name in values.fields.keys().sort_by_key((k) -> { k })) {
            rows.push(nested_row(name, values.fields.get(name) ?? ""));
        }
        if let logo: Source = message.logo {
            rows.push(nested_row("logo", describe_source(logo)));
        }
    } else {
        rows.push(row("return message", "none"));
    }
    rows
}

/// What a row reads as, for a test that cares about the whole of it rather than
/// about the two halves.
function summary_line(at: SummaryRow) -> string {
    let indent = if (at.nested) { "  " } else { "" };
    `${indent}${at.label}: ${at.value}`
}

function summary_lines(config: InstallConfig) -> string[] {
    let lines: string[] = [];
    for (let at in summary_rows(config)) {
        lines.push(summary_line(at));
    }
    lines
}

test "summary_lines describes an installation without optional sections" {
    let config = empty_config();
    config.disk = "/dev/sda";
    let lines = summary_lines(config);

    assert.is_true(lines.includes("target disk: /dev/sda"));
    assert.is_true(lines.includes("dotfiles package: none"));
    assert.is_true(lines.includes("return message: none"))
}

test "summary_lines says where each source comes from" {
    let config = empty_config();
    config.dotfiles = source_at("git", "https://example.invalid/dotfiles.git");
    config.return_message = empty_return_message_input();

    let lines = summary_lines(config);

    assert.is_true(lines.includes("dotfiles package: git: https://example.invalid/dotfiles.git"));
    //# the project's own is named as such, not as an empty location
    assert.is_true(lines.includes("  template package: the project's own"));
    assert.is_true(lines.includes("  theme: the project's own"))
}

test "summary_lines lists the return message fields it was given" {
    let config = empty_config();
    config.return_message = ReturnMessageInput {
        template: default_source(),
        theme: default_source(),
        values: root.return_message.ReturnMessageConfig {
            languages: ["es", "ca"],
            fields: { "phone": "+376 000 000", "owner_name": "Ivan" },
        },
    };
    let lines = summary_lines(config);

    assert.is_true(lines.includes("return message: es, ca"));
    assert.is_true(lines.includes("  owner_name: Ivan"));
    assert.is_true(lines.includes("  phone: +376 000 000"));
    assert.is_true(!lines.join("\n").includes("logo:"))
}
