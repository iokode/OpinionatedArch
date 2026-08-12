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

// Running commands and reading files is `root.common`'s, and so are the tests
// that hold it up. What is left here are three names in this tool's own words,
// so its callers read as what they do rather than as where the code lives.
//
// This tool has no host and no log: the message it prints is the only place an
// operator learns why a command failed, which is why every caller below reads
// `stderr` off the result instead of leaving it to a pane nobody has.

/// Runs a program without a shell, so no argument is ever re-parsed.
function run_command(program: string, args: string[]) -> root.common.CommandResult {
    root.common.system_shell().capture(program, args)
}

function read_text_file(path: string) -> string? {
    root.common.system_files().read(path)
}

function file_exists(path: string) -> bool {
    root.common.system_files().exists(path)
}

/// The login users of the `dotfiles` group, with their home directory and
/// their own primary group.
function read_dotfiles_users(diag: Diagnostics) -> DotfilesUser[] {
    let group = run_command("getent", ["group", "dotfiles"]);
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

    members
        .map(
            (name) -> {
                let passwd = run_command("getent", ["passwd", name]);
                let home = passwd.stdout.trim().split(":").at(5) ?? "";
                let primary_group = run_command("id", ["-gn", name]).stdout.trim();
                if (!passwd.ok() || home == "") {
                    diag.report(`cannot resolve the home directory of login user '${name}'`);
                }
                if (primary_group == "") {
                    diag.report(`cannot resolve the primary group of login user '${name}'`);
                }
                DotfilesUser { name: name, home: home, group: primary_group }
            },
        )
}

function detect_machine(diag: Diagnostics) -> Machine {
    //# host selectors are evaluated against /etc/hostname
    let hostname = (read_text_file("/etc/hostname") ?? "").trim();
    if (hostname == "") {
        diag.report("cannot read the hostname from /etc/hostname");
    }
    Machine { hostname: hostname, users: read_dotfiles_users(diag) }
}
