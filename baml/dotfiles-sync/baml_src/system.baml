// The machine facts synchronization depends on, and the thin wrappers used to
// obtain them.

/// A member of the `dotfiles` group, for whom user targets are expanded.
class DotfilesUser {
    name: string,
    home: string,
    group: string,
}

/// The current machine: the hostname host selectors are evaluated against and
/// the login users user targets expand over.
class Machine {
    hostname: string,
    users: DotfilesUser[],
}

// Running commands and touching files is `root.common`'s, and so are the tests
// that hold it up. Both arrive as ports, carried down from the entry point:
// nothing here reaches for the machine on its own, which is what lets the whole
// tool be run against doubles.
//
// This tool has no host and no log: the message it prints is the only place an
// operator learns why something failed, which is why a failure is never left
// as an exit code.

/// The login users of the `dotfiles` group, with their home directory and
/// their own primary group.
function read_dotfiles_users(shell: root.common.Shell, diag: Diagnostics) -> DotfilesUser[] {
    let group = shell.capture("getent", ["group", "dotfiles"]);
    if (!group.ok()) {
        diag.report("the 'dotfiles' group does not exist on this machine");
        return [];
    }
    let members = (group.stdout.trim().split(":").at(3) ?? "")
        .split(",")
        .filter(
            (name) -> {
                name != ""
            },
        );

    let users: DotfilesUser[] = [];
    for (let name in members) {
        let passwd = shell.capture("getent", ["passwd", name]);
        let home = passwd.stdout.trim().split(":").at(5) ?? "";
        let primary_group = shell.capture("id", ["-gn", name]).stdout.trim();
        if (!passwd.ok() || home == "") {
            diag.report(`cannot resolve the home directory of login user '${name}'`);
        }
        if (primary_group == "") {
            diag.report(`cannot resolve the primary group of login user '${name}'`);
        }
        users.push(DotfilesUser { name: name, home: home, group: primary_group });
    }
    users
}

function detect_machine(shell: root.common.Shell, files: root.common.Files,
                        diag: Diagnostics) -> Machine {
    //# host selectors are evaluated against /etc/hostname
    let hostname = (files.read("/etc/hostname") ?? "").trim();
    if (hostname == "") {
        diag.report("cannot read the hostname from /etc/hostname");
    }
    Machine { hostname: hostname, users: read_dotfiles_users(shell, diag) }
}
