// Mounting removable media from inside the installer.
//
// A live system shows only what is mounted, so a package on a USB stick is
// unreachable to the pickers until somebody mounts it. F5 does that from any
// screen, as decided in `docs/tools/oparch-installer/003-input-sources.md`.
//
// The widget that draws this runs nothing. Every command it causes is decided
// here and every line it reads is read here, which is the line
// `docs/development/004-host-bridge.md` draws: the host owns the terminal and the
// running of processes, and nothing else.

/// A command, for a caller that runs commands but decides none.
class Argv {
    program: string,
    args: string[],
}

/// A partition the operator may mount.
class MountableDevice {
    path: string,
    size: string,
    filesystem: string,
    label: string,
}

/// Where mounted media live. Not under `/mnt`, which is the root of the system
/// being built.
function media_directory() -> string {
    "/run/oparch/media"
}

/// The last segment of a path, which for `/dev/sdb1` is what names its mount
/// point. Two devices cannot share a name, so two mounts cannot collide.
function device_name(path: string) -> string {
    let parts = path.split("/");
    parts.at(parts.length() - 1) ?? path
}

function mount_point_for(path: string) -> string {
    root.common.in_directory(media_directory(), device_name(path))
}

/// What is asked of `lsblk`. Raw output is asked for because it keeps empty
/// fields in place, which is what tells "no filesystem" from "no label".
function mountable_listing_argv() -> Argv {
    Argv { program: "lsblk", args: ["-pnro", "NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINT"] }
}

/// What `lsblk` reports under `FSTYPE` that is not a filesystem: a container,
/// or a member of one. Mounting any of them cannot work.
///
/// The disk this installer has just written is the reason this list exists: its
/// second partition is a LUKS container, so it reads as having a filesystem
/// while having nothing that can be mounted. What is inside it is reached
/// through `/dev/mapper`, and during an installation it is already mounted at
/// the target root anyway.
function unmountable_types() -> string[] {
    ["crypto_LUKS", "LVM2_member", "linux_raid_member", "swap"]
}

/// The partitions worth offering: a filesystem to mount, and not mounted yet.
///
/// A device with no filesystem is left out because mounting it cannot work, and
/// one already mounted because it is already reachable — including the media
/// this widget mounted, which is why pressing F5 twice does not offer the same
/// stick again.
function parse_mountable(listing: string) -> MountableDevice[] {
    let devices: MountableDevice[] = [];
    for (let line in root.common.nonempty_lines(listing)) {
        let field = line.split(" ");
        let kind = field.at(1) ?? "";
        let filesystem = field.at(3) ?? "";
        let mounted = field.at(5) ?? "";
        if (kind != "part" && kind != "rom") {
            continue;
        }
        if (filesystem == "" || mounted != "" || unmountable_types().includes(filesystem)) {
            continue;
        }
        //# raw output writes a space as `\x20`, so a label is put back together
        //# before anybody reads it
        devices.push(MountableDevice {
            path: field.at(0) ?? "",
            size: field.at(2) ?? "",
            filesystem: filesystem,
            label: (field.at(4) ?? "").replace_all("\\x20", " "),
        });
    }
    devices
}

/// How a device is named in the list.
function mountable_label(device: MountableDevice) -> string {
    let named = if (device.label == "") { "" } else { ` "${device.label}"` };
    `${device.path}${named} (${device.size}, ${device.filesystem})`
}

/// The labels of every device, in the order they were read.
function mountable_labels(devices: MountableDevice[]) -> string[] {
    let labels: string[] = [];
    for (let device in devices) {
        labels.push(mountable_label(device));
    }
    labels
}

function mount_argv(path: string, at: string) -> Argv {
    Argv { program: "mount", args: [path, at] }
}

/// Media are unmounted when the installation starts, so nothing the operator
/// browsed is still attached when the disk is written to. `-l` detaches a
/// filesystem that something is still looking at rather than refusing.
function unmount_argv(at: string) -> Argv {
    Argv { program: "umount", args: ["-l", at] }
}

function mount_failed(path: string, exit_code: int) -> string {
    `Mounting ${path} failed with exit code ${exit_code}.`
}

function nothing_to_mount() -> string {
    "No unmounted partition with a filesystem was found."
}

// -------------------------------------------------------------------- tests

function sample_listing() -> string {
    "/dev/sda disk 476.9G  \n"
        + "/dev/sda1 part 512M vfat  /boot\n"
        + "/dev/sda2 part 476.4G crypto_LUKS  \n"
        + "/dev/sdb disk 28.9G  \n"
        + "/dev/sdb1 part 28.9G exfat ANDORRA\\x20USB \n"
        + "/dev/sdc1 part 1G   \n"
}

test "the partitions offered are the ones that can be mounted and are not" {
    let devices = parse_mountable(sample_listing());

    //# sda1 is mounted, sda2 is a container rather than a filesystem, sdc1 has
    //# no filesystem at all, and neither disk is a partition
    assert.equal(mountable_labels(devices), ["/dev/sdb1 \"ANDORRA USB\" (28.9G, exfat)"])
}

test "the disk the installer just wrote offers nothing to mount" {
    //# what a machine looks like once the installation has finished: the ESP
    //# and every subvolume are mounted under the target, and what is left is a
    //# LUKS container, which is not something `mount` can be pointed at
    let devices = parse_mountable(
        "/dev/sda disk 476.9G  \n"
            + "/dev/sda1 part 1G vfat  /mnt/boot\n"
            + "/dev/sda2 part 475.9G crypto_LUKS  \n"
            + "/dev/mapper/cryptroot crypt 475.9G btrfs  /mnt\n"
            + "/dev/sdb1 part 28.9G exfat ANDORRA\\x20USB \n");

    assert.equal(mountable_labels(devices), ["/dev/sdb1 \"ANDORRA USB\" (28.9G, exfat)"])
}

test "a container is not a filesystem, whatever lsblk calls it" {
    for (let kind in unmountable_types()) {
        assert.equal(parse_mountable(`/dev/sda2 part 100G ${kind}  ` + "\n"), []);
    }
    //# and what is a filesystem is still offered
    assert.equal(parse_mountable("/dev/sda2 part 100G ext4  \n").length(), 1)
}

test "a label written the way raw output escapes it is put back together" {
    let devices = parse_mountable("/dev/sdb1 part 28.9G exfat ANDORRA\\x20USB \n");
    assert.equal((devices.at(0))?.label, "ANDORRA USB")
}

test "an empty listing offers nothing rather than a device with no name" {
    assert.equal(parse_mountable(""), []);
    assert.equal(parse_mountable("\n\n"), [])
}

test "a mount point is named after the device, and never under the target root" {
    assert.equal(mount_point_for("/dev/sdb1"), "/run/oparch/media/sdb1");
    assert.is_true(!mount_point_for("/dev/sdb1").starts_with("/mnt"))
}

test "the commands are the ones the host is to run, program and all" {
    assert.equal(mountable_listing_argv().program, "lsblk");
    assert.equal(mount_argv("/dev/sdb1", "/run/oparch/media/sdb1").args,
                 ["/dev/sdb1", "/run/oparch/media/sdb1"]);
    assert.equal(unmount_argv("/run/oparch/media/sdb1").args, ["-l", "/run/oparch/media/sdb1"])
}
