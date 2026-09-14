// Everything the installer collects before it touches the disk.
//
// The shape mirrors the configuration file defined in
// `docs/tools/installer/unattended/001-config-file-format.md`, so that there is one
// vocabulary rather than a model and a translation layer between it and the
// file.

class SwapConfig {
    zram_gb: int,
    swapfile_gb: int,
}

// the dotfiles package is content held elsewhere, like the template package
// and the theme, so it is named the same way: an origin and a location

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

/// The encrypted secret store an installation is given, for a dotfiles map
/// that declares secrets. One file and the passphrase that opens it.
///
/// The passphrase is here because the values it protects have to reach the
/// machine before its first boot, and there is no other moment at which anyone
/// is present to give it. It is never written anywhere the installation leaves
/// behind, and never shown.
class SecretStoreInput {
    archive: Source,
    passphrase: string,
}

class InstallConfig {
    disk: string,
    install_mode: string,
    /// True when this installation draws its packages from the repository the
    /// medium carries instead of from the network. It is an answer and never
    /// an outcome: nothing sets it because a synchronisation failed.
    offline: bool,
    preserved_work_contexts: string[],
    ucode_package: string,
    gpu_driver: string,
    swap: SwapConfig,
    work_contexts: string[],
    shared_secret: string,
    console_keymap: string,
    timezone: string,
    hostname: string,
    /// Absent when no dotfiles package is taken.
    dotfiles: Source?,
    /// Absent when the dotfiles map needs no secrets, and absent whenever the
    /// package is.
    secret_store: SecretStoreInput?,
    /// Absent when there is no pre-boot return message.
    return_message: ReturnMessageInput?,
    /// Read from the disk once it is partitioned; not part of the file.
    root_part_uuid: string,
}

function empty_config() -> InstallConfig {
    InstallConfig {
        disk: "",
        install_mode: "",
        offline: false,
        preserved_work_contexts: [],
        ucode_package: "",
        gpu_driver: "",
        swap: SwapConfig { zram_gb: 0, swapfile_gb: 0 },
        work_contexts: [],
        shared_secret: "",
        console_keymap: "",
        timezone: "",
        hostname: "",
        dotfiles: null,
        secret_store: null,
        return_message: null,
        root_part_uuid: "",
    }
}
