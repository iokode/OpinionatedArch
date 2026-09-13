// Where the packages an installation installs come from: the repository this
// project publishes, and the one the medium carries when it carries one.

/// Where this project publishes its packages. The network screen asks whether
/// it is reached and the bootstrap writes it into the installed system, and
/// both say it from here so that they cannot come to name different servers.
function package_repository() -> string {
    "https://packages.oparch.iokode.dev"
}

/// Where the medium keeps the pacman configuration that resolves against the
/// repository it carries, written beside that repository when the image was
/// built. It names the medium's repository and no other, so an installation
/// using it reaches for nothing.
function medium_pacman_conf() -> string {
    "/usr/share/oparch/medium.conf"
}

/// Whether this live environment can install with no network at all.
///
/// The medium is asked rather than assumed, because the installer also runs
/// from the official Arch image and from whatever `install.sh` was fetched
/// onto: those carry no repository of their own, and on them an installation
/// without a network is not a slower installation but no installation.
function medium_carries_packages(files: root.common.Files) -> bool {
    files.exists(medium_pacman_conf())
}

test "a medium carries packages when it carries the configuration for them" {
    let bare = root.common.recording_files();
    assert.equal(medium_carries_packages(bare), false);

    let medium = root.common.recording_files();
    medium.write(medium_pacman_conf(), "[options]\n");
    assert.equal(medium_carries_packages(medium), true)
}
