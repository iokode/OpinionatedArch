// The screens of oparch-password-rotate-interactive, in order, and what each
// takes as an answer. The rotation itself is the password library's: this
// collects what it is called with, and shows how it ended.

/// The screens, in the order they are asked. The last asks nothing: it is the
/// rotation, and the screen the run ends on.
function screen_names() -> string[] {
    ["Existing secret", "New secret", "Confirmation", "Rotation"]
}

/// How a run ended, for the terminal once the screens have handed it back.
class Ended {
    /// 0 when the secret was rotated, 1 when it was not.
    exit_code: int,
    /// What the run ended saying.
    message: string,
}

/// Asks the existing secret, the new one and its confirmation, then rotates
/// through the password library and ends on what it said.
///
/// Going back from a screen returns to the one before it; the first has
/// nothing before it and is asked again. An answer that is not taken is said
/// on the screen it was given on, which is asked again: a new secret the
/// library refuses, and a confirmation that is not the new secret.
function rotate_interactively(shell: root.common.Shell, screens: Screens) -> Ended {
    screens.outline(screen_names());
    let old_password = "";
    let new_password = "";
    let at = 0;
    while (at < 3) {
        if (at == 0) {
            screens.step("Existing secret");
            let answer = screens.secret("Existing secret",
                                        "The shared secret the disk and every work context have now.");
            if let given: string = answer {
                old_password = given;
                at = 1;
            }
        } else if (at == 1) {
            screens.step("New secret");
            let answer = screens.secret("New secret",
                                        "The shared secret they will have from now on.");
            if let given: string = answer {
                //# refused here by the same check the library makes, so the
                //# operator is told on the screen the answer was given on
                let problem = root.password.secrets_problem(old_password, given);
                if (problem != "") {
                    screens.error(problem);
                } else {
                    new_password = given;
                    at = 2;
                }
            } else {
                at = 0;
            }
        } else {
            screens.step("Confirmation");
            let answer = screens.secret("Confirmation", "The new shared secret, once more.");
            if let given: string = answer {
                if (given != new_password) {
                    screens.error("the confirmation does not match the new secret.");
                } else {
                    at = 3;
                }
            } else {
                at = 1;
            }
        }
    }

    screens.step("Rotation");
    screens.action("Rotating the shared secret");
    let rotation = root.password.rotate_shared_secret(shell, old_password, new_password);
    if (rotation.ok()) {
        screens.finish("Rotation", ["The shared secret was rotated."], false);
        return Ended { exit_code: 0, message: "The shared secret was rotated." };
    }
    let lines = [rotation.failure].concat(root.common.nonempty_lines(rotation.stderr));
    screens.finish("Rotation", lines, true);
    Ended { exit_code: 1, message: lines.join("\n") }
}

// -------------------------------------------------------------------- tests

function machine_with_two_contexts() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "getent group work-contexts": "work-contexts:x:1002:personal,work\n" },
    }
}

test "the three secrets are asked, and the rotation runs through the library" {
    let shell = machine_with_two_contexts();
    let screens = scripted(["old secret", "new secret", "new secret"]);

    let ended = rotate_interactively(shell, screens);

    assert.equal(screens.outline, screen_names());
    assert.equal(screens.steps, screen_names());
    assert.equal(screens.asked, ["Existing secret", "New secret", "Confirmation"]);
    assert.equal(shell.fed, [
        "cryptsetup luksChangeKey /dev/disk/by-partlabel/OpinionatedArch",
        "chpasswd",
        "chpasswd",
    ]);
    assert.equal(screens.finished, ["The shared secret was rotated."]);
    assert.is_true(!screens.failed);
    assert.equal(ended.exit_code, 0)
}

test "no secret reaches a command line" {
    let shell = machine_with_two_contexts();

    let _ = rotate_interactively(shell, scripted(["old secret", "new secret", "new secret"]));

    assert.is_true(!shell.commands.join(" ").includes("old secret"));
    assert.is_true(!shell.commands.join(" ").includes("new secret"))
}

test "a confirmation that is not the new secret is said so, and asked again" {
    let shell = machine_with_two_contexts();
    let screens = scripted(["old secret", "new secret", "other secret", "new secret"]);

    let ended = rotate_interactively(shell, screens);

    assert.equal(screens.errors, ["the confirmation does not match the new secret."]);
    assert.equal(screens.asked, ["Existing secret", "New secret", "Confirmation", "Confirmation"]);
    assert.equal(ended.exit_code, 0)
}

test "an empty new secret is refused on its own screen, before anything runs" {
    let shell = machine_with_two_contexts();
    let screens = scripted(["old secret", "", "new secret", "new secret"]);

    let _ = rotate_interactively(shell, screens);

    assert.equal(screens.errors, ["the new secret cannot be empty."]);
    assert.equal(screens.asked, ["Existing secret", "New secret", "New secret", "Confirmation"]);
    assert.equal(shell.commands.length(), 4)
}

test "going back returns to the screen before" {
    let shell = machine_with_two_contexts();
    let screens = scripted([
        "old secret", "<back>", "other secret", "new secret", "<back>", "new secret", "new secret",
    ]);

    let _ = rotate_interactively(shell, screens);

    assert.equal(screens.asked, [
        "Existing secret", "New secret", "Existing secret", "New secret", "Confirmation",
        "New secret", "Confirmation",
    ])
}

test "the first screen has nothing behind it, and is asked again" {
    let shell = machine_with_two_contexts();
    let screens = scripted(["<back>", "old secret", "new secret", "new secret"]);

    let _ = rotate_interactively(shell, screens);

    assert.equal(screens.asked, ["Existing secret", "Existing secret", "New secret", "Confirmation"])
}

test "a rotation that fails ends on what failed" {
    let shell = machine_with_two_contexts();
    let _ = shell.exit_codes.set("cryptsetup luksChangeKey /dev/disk/by-partlabel/OpinionatedArch", 2);
    let screens = scripted(["wrong secret", "new secret", "new secret"]);

    let ended = rotate_interactively(shell, screens);

    assert.equal(screens.finished,
                 ["changing the passphrase of the encrypted container failed with exit code 2."]);
    assert.is_true(screens.failed);
    assert.equal(ended.exit_code, 1);
    assert.is_true(!shell.commands.includes("chpasswd"))
}
