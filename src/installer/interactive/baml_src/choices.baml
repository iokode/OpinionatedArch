// How the screens show what the live system offers, and read back what is
// typed into them.

/// The label shown in the disk selector.
function format_disk_label(disk: root.installer.DiskTarget) -> string {
    if (disk.model == "") {
        `${disk.path} (${disk.size})`
    } else {
        `${disk.path} (${disk.size}, ${disk.model})`
    }
}

/// The labels shown in the disk selector, in the same order as `disks`.
function disk_labels(disks: root.installer.DiskTarget[]) -> string[] {
    let labels: string[] = [];
    for (let disk in disks) {
        labels.push(format_disk_label(disk));
    }
    labels
}

/// Swap sizes, as typed: non-negative integers only.
function parse_size_gb(raw: string) -> int? {
    let text = raw.trim();
    if (text == "" || !text.is_ascii_numeric()) {
        return null;
    }
    root.common.parse_int(text)
}

test "format_disk_label with and without a model" {
    assert
        .equal(
            format_disk_label(root.installer.DiskTarget { path: "/dev/sda", size: "476,9G", model: "Samsung SSD 860" }),
            "/dev/sda (476,9G, Samsung SSD 860)",
        );
    assert
        .equal(
            format_disk_label(root.installer.DiskTarget { path: "/dev/sda", size: "476,9G", model: "" }),
            "/dev/sda (476,9G)",
        )
}

test "disk_labels formats every disk in order" {
    let disks = [
        root.installer.DiskTarget { path: "/dev/sda", size: "476,9G", model: "Samsung SSD 860" },
        root.installer.DiskTarget { path: "/dev/nvme0n1", size: "931,5G", model: "" },
    ];
    assert
        .equal(disk_labels(disks), ["/dev/sda (476,9G, Samsung SSD 860)", "/dev/nvme0n1 (931,5G)"])
}

test "parse_size_gb takes non-negative integers only" {
    assert.equal(parse_size_gb("0"), 0);
    assert.equal(parse_size_gb(" 16 "), 16);
    assert.is_true(parse_size_gb("") == null);
    assert.is_true(parse_size_gb("-1") == null);
    assert.is_true(parse_size_gb("1.5") == null);
    assert.is_true(parse_size_gb("many") == null)
}
