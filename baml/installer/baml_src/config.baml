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
    template: root.common.Source,
    theme: root.common.Source,
    values: root.return_message.ReturnMessageConfig,
}

function empty_return_message_input() -> ReturnMessageInput {
    ReturnMessageInput {
        template: root.common.default_source(),
        theme: root.common.default_source(),
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
    dotfiles: root.common.Source?,
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
function describe_source(source: root.common.Source) -> string {
    if (root.common.is_default_source(source)) {
        return "the project's own";
    }
    `${source.origin}: ${source.location}`
}

/// The review screen, one line per setting.
function summary_lines(config: InstallConfig) -> string[] {
    let lines = [
        `target disk: ${config.disk}`,
        `install mode: ${config.install_mode}`,
        `preserved home users: ${config.preserved_home_users.join(", ")}`,
        `ucode package: ${config.ucode_package}`,
        `gpu driver: ${config.gpu_driver}`,
        `zram size (GB): ${config.swap.zram_gb}`,
        `disk swapfile size (GB): ${config.swap.swapfile_gb}`,
        `login users: ${config.login_users.join(", ")}`,
        `keymap: ${config.console_keymap}`,
        `timezone: ${config.timezone}`,
        `hostname: ${config.hostname}`,
    ];

    if let dotfiles: root.common.Source = config.dotfiles {
        lines.push(`dotfiles package: ${describe_source(dotfiles)}`);
    } else {
        lines.push("dotfiles package: none");
    }

    if let message: ReturnMessageInput = config.return_message {
        let values = message.values;
        lines.push(`return message: ${values.languages.join(", ")}`);
        lines.push(`  template package: ${describe_source(message.template)}`);
        lines.push(`  theme: ${describe_source(message.theme)}`);
        for (let name in values.fields.keys().sort_by_key((k) -> { k })) {
            lines.push(`  ${name}: ${values.fields.get(name) ?? ""}`);
        }
        if let logo: root.common.Source = values.logo {
            lines.push(`  logo: ${describe_source(logo)}`);
        }
    } else {
        lines.push("return message: none");
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
    config.dotfiles = root.common.source_at("git", "https://example.invalid/dotfiles.git");
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
        template: root.common.default_source(),
        theme: root.common.default_source(),
        values: root.return_message.ReturnMessageConfig {
            languages: ["es", "ca"],
            fields: { "phone": "666 555 666", "owner_name": "Ivan" },
            logo: null,
        },
    };
    let lines = summary_lines(config);

    assert.is_true(lines.includes("return message: es, ca"));
    assert.is_true(lines.includes("  owner_name: Ivan"));
    assert.is_true(lines.includes("  phone: 666 555 666"));
    assert.is_true(!lines.join("\n").includes("logo:"))
}
