// Rotating the shared secret: the passphrase of the encrypted container and
// the password of every work context, which
// `docs/decisions/000-work-contexts-and-accounts.md` makes one secret.
//
// Running commands is `root.common`'s, and the shell arrives from whichever
// interface asked for the rotation: nothing here reaches for the machine on its
// own, which is what lets the whole operation run against the recording
// doubles.

/// The encrypted container, by the name the installation gives its partition,
/// `OpinionatedArch`, as `docs/decisions/001-disk-layout.md` labels it.
function container_device() -> string {
    "/dev/disk/by-partlabel/OpinionatedArch"
}

/// The group that marks the accounts that are work contexts.
function work_contexts_group() -> string {
    "work-contexts"
}

/// How a rotation ended.
class Rotation {
    /// What failed, or "" when the secret was rotated.
    failure: string,
    /// What the command that failed wrote to standard error, empty when nothing
    /// failed or when it said nothing. An interface with somewhere to show it
    /// shows it there; one whose only channel is the message it prints puts it
    /// in the message.
    stderr: string,

    function ok(self) -> bool {
        self.failure == ""
    }
}

/// The members of the group, read from what `getent group` prints for it:
/// `name:password:id:member,member`.
function work_context_names(group_entry: string) -> string[] {
    (group_entry.trim().split(":").at(3) ?? "")
        .split(",")
        .filter(
            (name) -> {
                name != ""
            },
        )
}

/// What `cryptsetup luksChangeKey` is given on standard input: the existing
/// passphrase on the first line and the replacement on the second. With no
/// `--key-file`, and an input that is not a terminal, `cryptsetup` reads each
/// passphrase of a LUKS container up to the end of its line.
function change_key_input(old_password: string, new_password: string) -> string {
    old_password + "\n" + new_password + "\n"
}

/// What `chpasswd` is given on standard input for one account.
function password_line(name: string, password: string) -> string {
    name + ":" + password + "\n"
}

/// Why a pair of secrets is refused, or "" when it is not.
///
/// An empty replacement would leave every work context with no password. And
/// both `cryptsetup` and `chpasswd` read a secret up to the end of its line, so
/// a secret holding a line break would reach them cut in two.
function secrets_problem(old_password: string, new_password: string) -> string {
    if (new_password == "") {
        return "the new secret cannot be empty.";
    }
    if (old_password.includes("\n")) {
        return "the existing secret cannot contain a line break.";
    }
    if (new_password.includes("\n")) {
        return "the new secret cannot contain a line break.";
    }
    ""
}

/// Changes the passphrase of the encrypted container from the existing secret
/// to the replacement, and sets the replacement as the password of every
/// member of `work-contexts`. A pair of secrets `secrets_problem` refuses is
/// refused before anything runs, and the rotation stops at the first command
/// that fails.
///
/// Both secrets reach the commands on standard input and never as arguments,
/// where any user of the machine could read them from the process list.
function rotate_shared_secret(shell: root.common.Shell, old_password: string,
                              new_password: string) -> Rotation {
    let refused = secrets_problem(old_password, new_password);
    if (refused != "") {
        return Rotation { failure: refused, stderr: "" };
    }

    let group = shell.capture("getent", ["group", work_contexts_group()]);
    let read = root.common.must(group, `reading the members of ${work_contexts_group()}`);
    if (read != "") {
        return Rotation { failure: read, stderr: group.stderr };
    }

    //# the existing secret is checked here and nowhere else: root sets an
    //# account's password without being told the one it replaces
    let changed = shell.feed("cryptsetup", ["luksChangeKey", container_device()],
                             change_key_input(old_password, new_password));
    let container = root.common.must(changed, "changing the passphrase of the encrypted container");
    if (container != "") {
        return Rotation { failure: container, stderr: changed.stderr };
    }

    for (let name in work_context_names(group.stdout)) {
        let set = shell.feed("chpasswd", [], password_line(name, new_password));
        let password = root.common.must(set, `setting the password of ${name}`);
        if (password != "") {
            //# nothing is rolled back: the operator is told where the secret
            //# stands, and running again with the new secret as both finishes it
            return Rotation {
                failure: password + " The encrypted container already has the new secret.",
                stderr: set.stderr,
            };
        }
    }
    Rotation { failure: "", stderr: "" }
}

// -------------------------------------------------------------------- tests

function machine_with_two_contexts() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "getent group work-contexts": "work-contexts:x:1002:personal,work\n" },
    }
}

test "the container takes the new passphrase and every work context the new password" {
    let shell = machine_with_two_contexts();

    let rotation = rotate_shared_secret(shell, "old secret", "new secret");

    assert.is_true(rotation.ok());
    assert.equal(shell.commands, [
        "getent group work-contexts",
        "cryptsetup luksChangeKey /dev/disk/by-partlabel/OpinionatedArch",
        "chpasswd",
        "chpasswd",
    ]);
    assert.equal(shell.fed, [
        "cryptsetup luksChangeKey /dev/disk/by-partlabel/OpinionatedArch",
        "chpasswd",
        "chpasswd",
    ])
}

test "neither secret is ever on a command line" {
    let shell = machine_with_two_contexts();

    let _ = rotate_shared_secret(shell, "old secret", "new secret");

    assert.is_true(!shell.commands.join(" ").includes("old secret"));
    assert.is_true(!shell.commands.join(" ").includes("new secret"))
}

test "cryptsetup reads the existing passphrase first and its replacement after it" {
    assert.equal(change_key_input("old secret", "new secret"), "old secret\nnew secret\n");
    assert.equal(password_line("work", "new secret"), "work:new secret\n")
}

test "the members are read from the group entry, and a group with none has none" {
    assert.equal(work_context_names("work-contexts:x:1002:personal,work\n"), ["personal", "work"]);
    assert.equal(work_context_names("work-contexts:x:1002:\n"), [])
}

test "a group that cannot be read stops the rotation before anything is changed" {
    let shell = machine_with_two_contexts();
    let _ = shell.exit_codes.set("getent group work-contexts", 2);

    let rotation = rotate_shared_secret(shell, "old secret", "new secret");

    assert.equal(rotation.failure, "reading the members of work-contexts failed with exit code 2.");
    assert.equal(shell.fed, [])
}

test "a container that does not take the existing secret stops the rotation before any account" {
    let shell = machine_with_two_contexts();
    let _ = shell.exit_codes.set("cryptsetup luksChangeKey /dev/disk/by-partlabel/OpinionatedArch", 2);

    let rotation = rotate_shared_secret(shell, "wrong secret", "new secret");

    assert.equal(rotation.failure,
                 "changing the passphrase of the encrypted container failed with exit code 2.");
    assert.is_true(!shell.commands.includes("chpasswd"))
}

test "a password that cannot be set says whose it was, and stops there" {
    let shell = machine_with_two_contexts();
    let _ = shell.exit_codes.set("chpasswd", 1);

    let rotation = rotate_shared_secret(shell, "old secret", "new secret");

    //# the container has already taken the change, and the message says so
    assert.equal(rotation.failure,
                 "setting the password of personal failed with exit code 1."
                     + " The encrypted container already has the new secret.");
    assert.equal(shell.fed, [
        "cryptsetup luksChangeKey /dev/disk/by-partlabel/OpinionatedArch",
        "chpasswd",
    ])
}

test "an empty new secret is refused before anything runs" {
    let shell = machine_with_two_contexts();

    let rotation = rotate_shared_secret(shell, "old secret", "");

    assert.equal(rotation.failure, "the new secret cannot be empty.");
    assert.equal(shell.commands, [])
}

test "a secret holding a line break is refused before anything runs, old or new" {
    let shell = machine_with_two_contexts();

    let old_broken = rotate_shared_secret(shell, "old\nsecret", "new secret");
    let new_broken = rotate_shared_secret(shell, "old secret", "new\nsecret");

    assert.equal(old_broken.failure, "the existing secret cannot contain a line break.");
    assert.equal(new_broken.failure, "the new secret cannot contain a line break.");
    assert.equal(shell.commands, [])
}

test "a pair of secrets with nothing wrong with it is not refused" {
    assert.equal(secrets_problem("old secret", "new secret"), "");
    //# the new secret given as both is how a rotation that stopped is finished
    assert.equal(secrets_problem("new secret", "new secret"), "")
}
