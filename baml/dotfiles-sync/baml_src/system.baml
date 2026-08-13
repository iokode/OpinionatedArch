// The machine facts synchronization depends on: the hostname its host selectors
// are evaluated against, and the members of the `dotfiles` group its user
// targets expand over.

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

/// A login user described by name alone. Its home directory and its primary
/// group follow from the name, as `docs/decisions/000-user-model-and-account-types.md`
/// decides they do, which is what makes one name enough to name a user.
function described_user(name: string) -> DotfilesUser {
    DotfilesUser { name: name, home: `/home/${name}`, group: name }
}

/// The machine the plan is built for: the one this is running on, or the one it
/// was told about.
///
/// Each half is answered from arguments or from the system, never from both:
/// a hostname read here beside users named there is a machine that is neither,
/// and nothing said about it afterwards would say which half was wrong.
function detect_machine(shell: root.common.Shell, files: root.common.Files,
                        given_hostname: string?, given_users: string[],
                        diag: Diagnostics) -> Machine {
    //# host selectors are evaluated against /etc/hostname, unless told otherwise
    let hostname = given_hostname ?? "";
    if (given_hostname == null) {
        hostname = (files.read("/etc/hostname") ?? "").trim();
        if (hostname == "") {
            diag.report("cannot read the hostname from /etc/hostname");
        }
    }

    let users: DotfilesUser[] = [];
    if (given_users.length() == 0) {
        users = read_dotfiles_users(shell, diag);
    } else {
        for (let name in given_users) {
            users.push(described_user(name));
        }
    }

    Machine { hostname: hostname, users: users }
}

test "a machine named in arguments is not read from the system at all" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let files = root.common.recording_files();
    files.write("/etc/hostname", "the-live-medium\n");
    let diag = new_diagnostics();

    let machine = detect_machine(shell, files, "oparch", ["ivan", "work"], diag);

    assert.equal(machine.hostname, "oparch");
    assert.equal(machine.users.map((member) -> { member.name }), ["ivan", "work"]);
    assert.equal(machine.users.map((member) -> { member.home }), ["/home/ivan", "/home/work"]);
    assert.equal(machine.users.map((member) -> { member.group }), ["ivan", "work"]);
    //# the group was never asked for, which is the point of having been told
    assert.equal(shell.commands, []);
    assert.is_true(!diag.has_errors())
}

test "half a description still reads the other half from the machine" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "getent group dotfiles": "dotfiles:x:1001:ivan\n",
                   "getent passwd ivan": "ivan:x:1000:1000::/home/ivan:/bin/bash\n",
                   "id -gn ivan": "ivan\n" },
    };
    let files = root.common.recording_files();
    files.write("/etc/hostname", "desktop\n");

    let named = detect_machine(shell, files, "oparch", [], new_diagnostics());
    assert.equal(named.hostname, "oparch");
    assert.equal(named.users.map((member) -> { member.name }), ["ivan"]);

    let read = detect_machine(shell, files, null, ["work"], new_diagnostics());
    assert.equal(read.hostname, "desktop");
    assert.equal(read.users.map((member) -> { member.name }), ["work"])
}
