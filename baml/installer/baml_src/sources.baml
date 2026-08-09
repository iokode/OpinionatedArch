// Option lists the form offers, read from the live system.

function list_keymaps(shell: root.common.Shell) -> string[] {
    root.common.nonempty_lines(shell.capture("localectl", ["list-keymaps"]).stdout)
}

/// The timezones the user may choose. `timedatectl` is the canonical list:
/// walking /usr/share/zoneinfo instead also yields the `posix/` and `right/`
/// duplicate databases and files that are not timezones at all, such as
/// `leapseconds` and `zone.tab`. It comes out sorted, so nothing here reorders
/// it.
function list_timezones(shell: root.common.Shell) -> string[] {
    root.common.nonempty_lines(shell.capture("timedatectl", ["list-timezones"]).stdout)
}

/// The labels shown in the disk selector, in the same order as `disks`.
function disk_labels(disks: DiskTarget[]) -> string[] {
    let labels: string[] = [];
    for (let disk in disks) {
        labels.push(format_disk_label(disk));
    }
    labels
}

test "disk_labels formats every disk in order" {
    let disks = [
        DiskTarget { path: "/dev/sda", size: "476,9G", model: "Samsung SSD 860" },
        DiskTarget { path: "/dev/nvme0n1", size: "931,5G", model: "" },
    ];
    assert
        .equal(disk_labels(disks), ["/dev/sda (476,9G, Samsung SSD 860)", "/dev/nvme0n1 (931,5G)"])
}

test "list_timezones keeps the order the canonical list comes in" {
    let shell = root.common.RecordingShell {
        commands: [],
        fed: [],
        streamed: [],
        exit_codes: {},
        replies: { "timedatectl list-timezones": "Africa/Abidjan\nEurope/Madrid\nUTC\n" },
    };
    assert.equal(list_timezones(shell), ["Africa/Abidjan", "Europe/Madrid", "UTC"]);
    assert.equal(shell.commands, ["timedatectl list-timezones"])
}
