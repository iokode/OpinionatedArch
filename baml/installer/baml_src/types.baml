// Installer data model.

/// A disk the installer can target, as reported by lsblk.
class DiskTarget {
    path: string,
    size: string,
    model: string,
}

/// What the installer collected and did. Grows as phases are ported.
class InstallSummary {
    disk: string,
    exit_code: int,
}
