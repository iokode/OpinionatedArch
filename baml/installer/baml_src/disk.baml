// Disk discovery. Pure functions over command output — no I/O lives here.

/// Parses `lsblk -dpno NAME,TYPE` output, keeping only whole disks.
function parse_disk_paths(lsblk_output: string) -> string[] {
    let paths: string[] = [];
    for (let line in lsblk_output.lines()) {
        let fields = root.common.split_fields(line);
        if (fields.length() == 2 && fields.at(1) == "disk") {
            paths.push(fields.at(0) ?? "");
        }
    }
    paths
}

/// `lsblk -dno <FIELD> <path>` returns one value; take its first line.
function parse_lsblk_field(output: string) -> string {
    (output.lines().at(0) ?? "").trim()
}

/// The label shown in the disk selector.
function format_disk_label(disk: DiskTarget) -> string {
    if (disk.model == "") {
        `${disk.path} (${disk.size})`
    } else {
        `${disk.path} (${disk.size}, ${disk.model})`
    }
}

/// NVMe, eMMC and loop devices name partitions `<disk>p<n>`; everything else
/// uses `<disk><n>`.
function partition_path(disk: string, index: int) -> string {
    if (disk.includes("nvme") || disk.includes("mmcblk") || disk.includes("loop")) {
        `${disk}p${index}`
    } else {
        `${disk}${index}`
    }
}

test "parse_disk_paths keeps disks and drops other device types" {
    let output = "/dev/sda    disk\n/dev/sr0    rom\n/dev/nvme0n1 disk\n";
    assert.equal(parse_disk_paths(output), ["/dev/sda", "/dev/nvme0n1"])
}

test "parse_disk_paths on empty output" {
    assert.equal(parse_disk_paths(""), [])
}

test "parse_lsblk_field trims and takes the first line" {
    assert.equal(parse_lsblk_field("  476,9G  \n"), "476,9G");
    assert.equal(parse_lsblk_field(""), "")
}

test "format_disk_label with and without a model" {
    assert
        .equal(
            format_disk_label(DiskTarget { path: "/dev/sda", size: "476,9G", model: "Samsung SSD 860" }),
            "/dev/sda (476,9G, Samsung SSD 860)",
        );
    assert
        .equal(
            format_disk_label(DiskTarget { path: "/dev/sda", size: "476,9G", model: "" }),
            "/dev/sda (476,9G)",
        )
}

test "partition_path picks the right naming scheme" {
    assert.equal(partition_path("/dev/sda", 1), "/dev/sda1");
    assert.equal(partition_path("/dev/nvme0n1", 2), "/dev/nvme0n1p2");
    assert.equal(partition_path("/dev/mmcblk0", 1), "/dev/mmcblk0p1");
    assert.equal(partition_path("/dev/loop0", 1), "/dev/loop0p1")
}
