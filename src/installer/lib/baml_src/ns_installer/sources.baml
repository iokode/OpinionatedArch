// What the live system offers to be chosen from: its disks, and the keymaps and
// timezones it knows.

/// Reads the selectable disks, filling in size and model per device.
function list_disks(shell: root.common.Shell) -> DiskTarget[] {
    let out = shell.capture("lsblk", ["-dpno", "NAME,TYPE"]);
    let disks: DiskTarget[] = [];
    for (let path in parse_disk_paths(out.stdout)) {
        disks
            .push(
                DiskTarget {
                    path: path,
                    size: parse_lsblk_field(shell.capture("lsblk", ["-dno", "SIZE", path]).stdout),
                    model: parse_lsblk_field(shell.capture("lsblk", ["-dno", "MODEL", path]).stdout),
                },
            );
    }
    disks
}

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
