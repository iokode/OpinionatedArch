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

class DotfilesConfig {
    repository_url: string,
}

/// What the installer collected for the pre-boot return message: the values
/// themselves, and where the package and the theme that render them come from.
///
/// The values are the renderer's own format, and it reads them from the file
/// the installation leaves behind. The two origins are not in that format and
/// never reach it: the renderer is handed directories, and resolving an origin
/// into one is the installer's job.
class ReturnMessageInput {
    /// Where the template package comes from. Empty means the project's own.
    template: string,
    /// Where the theme comes from. Empty means the project's own.
    theme: string,
    values: root.return_message.ReturnMessageConfig,
}

function empty_return_message_input() -> ReturnMessageInput {
    ReturnMessageInput {
        template: "", theme: "", values: root.return_message.empty_return_message(),
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
    /// Absent when no dotfiles repository is cloned.
    dotfiles: DotfilesConfig?,
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

    if let dotfiles: DotfilesConfig = config.dotfiles {
        lines.push(`dotfiles repository: ${dotfiles.repository_url}`);
    } else {
        lines.push("dotfiles repository: none");
    }

    if let message: ReturnMessageInput = config.return_message {
        let values = message.values;
        lines.push(`return message: ${values.languages.join(", ")}`);
        for (let name in values.fields.keys().sort_by_key((k) -> { k })) {
            lines.push(`  ${name}: ${values.fields.get(name) ?? ""}`);
        }
        if (values.logo_url != "") {
            lines.push(`  logo: ${values.logo_url}`);
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
    assert.is_true(lines.includes("dotfiles repository: none"));
    assert.is_true(lines.includes("return message: none"))
}

test "summary_lines lists the return message fields it was given" {
    let config = empty_config();
    config.return_message = ReturnMessageInput {
        template: "",
        theme: "",
        values: root.return_message.ReturnMessageConfig {
            languages: ["es", "ca"],
            fields: { "phone": "666 555 666", "owner_name": "Ivan" },
            logo_url: "",
        },
    };
    let lines = summary_lines(config);

    assert.is_true(lines.includes("return message: es, ca"));
    assert.is_true(lines.includes("  owner_name: Ivan"));
    assert.is_true(lines.includes("  phone: 666 555 666"));
    assert.is_true(!lines.join("\n").includes("logo:"))
}
