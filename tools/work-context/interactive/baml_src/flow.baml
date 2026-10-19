// The screens of oparch-work-context-interactive, in order, and what each takes
// as an answer. Creating and removing a work context are the work context
// library's: this shows the contexts, collects what an operation is called
// with, and shows how it ended.

/// How a run ended, for the terminal once the screens have handed it back.
class Ended {
    /// 0 when the operation was carried out, 1 when it was not.
    exit_code: int,
    /// What the run ended saying.
    message: string,
}

/// The first screen, which shows the work contexts and asks what to do.
function menu_screen() -> string {
    "Work contexts"
}

/// What the first screen offers, in order.
function operations() -> string[] {
    ["Create a work context", "Remove a work context"]
}

/// The screens of creating a work context, in order. The last asks nothing: it
/// is the creation, and the screen the run ends on.
function creation_screens() -> string[] {
    [menu_screen(), "Name", "Creation"]
}

/// The screens of removing a work context, in order. The last asks nothing: it
/// is the removal, and the screen the run ends on.
function removal_screens() -> string[] {
    [menu_screen(), "Work context", "Home data", "Snapshots", "Confirmation", "Removal"]
}

/// Ends the run on a screen saying how it ended.
function end_on(screens: Screens, title: string, lines: string[], failed: bool) -> Ended {
    screens.finish(title, lines, failed);
    let code = if (failed) { 1 } else { 0 };
    Ended { exit_code: code, message: lines.join("\n") }
}

/// Shows the work contexts, asks for an operation and what it is called with,
/// carries it out through the work context library, and ends on what it said.
///
/// Going back from a screen returns to the one before it; the first has nothing
/// before it and is asked again. An answer that is not taken is said on the
/// screen it was given on, which is asked again.
function manage_work_contexts(shell: root.common.Shell, files: root.common.Files,
                              lock: root.snapshot.SnapshotLock, screens: Screens) -> Ended {
    let result = Ended { exit_code: 1, message: "" };
    let running = true;
    let operation = 0;
    while (running) {
        screens.outline([menu_screen()]);
        let contexts = root.work_context.list_work_contexts(shell);
        if (contexts.error != "") {
            return end_on(screens, menu_screen(), [contexts.error], true);
        }
        screens.step(menu_screen());
        let prompt = `The work contexts of this machine: ${contexts.names.join(", ")}.`;
        let chosen = screens.choose(menu_screen(), prompt, operations(), operation);
        if let index: int = chosen {
            operation = index;
            if (index == 0) {
                if let done: Ended = creation(shell, files, screens) {
                    result = done;
                    running = false;
                }
            } else {
                if let done: Ended = removal(shell, files, lock, screens, contexts.names) {
                    result = done;
                    running = false;
                }
            }
        }
    }
    result
}

/// The screens of creating a work context, and the creation. Null when the
/// operator went back to the first screen.
function creation(shell: root.common.Shell, files: root.common.Files, screens: Screens) -> Ended? {
    screens.outline(creation_screens());
    let name = "";
    let asking = true;
    while (asking) {
        screens.step("Name");
        let answer = screens.text("Name", "The name of the new work context, which is also the name of its account.", name);
        if let given: string = answer {
            name = given;
            //# refused here by the same check the library makes, so the
            //# operator is told on the screen the name was given on
            let problem = root.common.work_context_name_error(given);
            if (problem != "") {
                screens.error(problem);
            } else {
                asking = false;
            }
        } else {
            return null;
        }
    }

    screens.step("Creation");
    screens.action(`Creating the work context ${name}`);
    let failure = root.work_context.create_work_context(shell, files, name);
    if (failure != "") {
        return end_on(screens, "Creation", root.common.nonempty_lines(failure), true);
    }
    end_on(screens, "Creation", [`The work context ${name} was created.`], false)
}

/// What the confirmation says is about to happen.
function confirmation_prompt(removal: root.work_context.Removal) -> string {
    let home = if (removal.preserve_home == "") {
        "its home is not kept"
    } else {
        `its home is copied into the home of ${removal.preserve_home}`
    };
    let snapshots = if (removal.preserve_snapshots) {
        "the snapshots of its home are kept"
    } else {
        "the snapshots of its home are removed"
    };
    `The work context ${removal.name} is removed, ${home}, and ${snapshots}. This cannot be undone.`
}

/// The screens of removing a work context, and the removal. Null when the
/// operator went back to the first screen.
function removal(shell: root.common.Shell, files: root.common.Files, lock: root.snapshot.SnapshotLock,
                 screens: Screens, names: string[]) -> Ended? {
    screens.outline(removal_screens());
    let removal = root.work_context.Removal { name: "", preserve_home: "", preserve_snapshots: false };
    let at = 1;
    let context_index = 0;
    let home_index = 0;
    let snapshots_index = 0;
    while (at < 5) {
        if (at == 1) {
            screens.step("Work context");
            let answer = screens.choose("Work context", "The work context to remove.", names, context_index);
            if let index: int = answer {
                context_index = index;
                let name = names.at(index) ?? "";
                //# refused here by the same check the library makes
                let problem = root.work_context.removal_problem(names, root.work_context.Removal {
                    name: name, preserve_home: "", preserve_snapshots: false,
                });
                if (problem != "") {
                    screens.error(problem);
                } else {
                    if (name != removal.name) {
                        home_index = 0;
                        removal.preserve_home = "";
                    }
                    removal.name = name;
                    at = 2;
                }
            } else {
                return null;
            }
        } else if (at == 2) {
            screens.step("Home data");
            let others: string[] = [];
            let options = ["Do not keep it"];
            for (let other in names) {
                if (other != removal.name) {
                    others.push(other);
                    options.push(`Keep it in the home of ${other}`);
                }
            }
            let answer = screens.choose("Home data",
                `Whether the home of ${removal.name} is copied into the home of another work context before it is removed.`,
                options, home_index);
            if let index: int = answer {
                home_index = index;
                if (index == 0) {
                    removal.preserve_home = "";
                } else {
                    removal.preserve_home = others.at(index - 1) ?? "";
                }
                at = 3;
            } else {
                at = 1;
            }
        } else if (at == 3) {
            screens.step("Snapshots");
            let answer = screens.choose("Snapshots",
                `Whether the snapshots of the home of ${removal.name} are removed with it.`,
                ["Remove them", "Keep them"], snapshots_index);
            if let index: int = answer {
                snapshots_index = index;
                removal.preserve_snapshots = index == 1;
                at = 4;
            } else {
                at = 2;
            }
        } else {
            screens.step("Confirmation");
            let answer = screens.choose("Confirmation", confirmation_prompt(removal), [`Remove ${removal.name}`], 0);
            if (answer == null) {
                at = 3;
            } else {
                at = 5;
            }
        }
    }

    screens.step("Removal");
    screens.action(`Removing the work context ${removal.name}`);
    let removed = root.work_context.remove_work_context(shell, files, lock, removal);
    let lines: string[] = [];
    let failed = removed.error != "";
    if (failed) {
        lines = lines.concat(root.common.nonempty_lines(removed.error));
    } else {
        lines.push(`The work context ${removal.name} was removed.`);
    }
    if (removed.copy != "") {
        lines.push(`Its home was copied to ${removed.copy}.`);
    }
    end_on(screens, "Removal", lines, failed)
}

// -------------------------------------------------------------------- tests

test "a work context is created from the name given, through the library" {
    let shell = root.work_context.creating_shell();
    let screens = scripted(["Create a work context", "project"]);

    let ended = manage_work_contexts(shell, root.work_context.machine_files(), root.snapshot.recording_lock(shell),
                                     screens);

    assert.equal(screens.asked, ["Work contexts", "Name"]);
    assert.equal(screens.steps, creation_screens());
    assert.is_true(shell.commands.includes(
        "useradd -M -d /home/project -G wheel,dotfiles,work-contexts -s /bin/bash project"));
    assert.equal(screens.finished, ["The work context project was created."]);
    assert.is_true(!screens.failed);
    assert.equal(ended.exit_code, 0)
}

test "the first screen shows the work contexts of the machine" {
    let shell = root.work_context.creating_shell();
    let screens = scripted(["Create a work context", "project"]);

    let _ = manage_work_contexts(shell, root.work_context.machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.prompts.at(0), "The work contexts of this machine: personal, work.")
}

test "a name that cannot be a work context's is said on its own screen, and asked again" {
    let shell = root.work_context.creating_shell();
    let screens = scripted(["Create a work context", "Project", "project"]);

    let ended = manage_work_contexts(shell, root.work_context.machine_files(), root.snapshot.recording_lock(shell),
                                     screens);

    assert.equal(screens.errors, ["Invalid work context name: Project"]);
    assert.equal(screens.asked, ["Work contexts", "Name", "Name"]);
    assert.equal(ended.exit_code, 0)
}

test "the first screen has nothing behind it, and going back from the name returns to it" {
    let shell = root.work_context.creating_shell();
    let screens = scripted(["<back>", "Create a work context", "<back>", "Create a work context", "project"]);

    let _ = manage_work_contexts(shell, root.work_context.machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, ["Work contexts", "Work contexts", "Name", "Work contexts", "Name"])
}

test "a work context is removed with what was chosen for its home and its snapshots" {
    let shell = root.work_context.removing_shell();
    let files = root.work_context.removing_files();
    let screens = scripted([
        "Remove a work context", "project", "Keep it in the home of personal", "Keep them", "Remove project",
    ]);

    let ended = manage_work_contexts(shell, files, root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.steps, removal_screens());
    assert.is_true(shell.commands.includes("cp -a /home/project/. /home/personal/other-contexts-home-data/project"));
    assert.is_true(shell.commands.includes("userdel project"));
    assert.is_true(!shell.commands.join("\n").includes("/snapshots"));
    assert.equal(screens.finished, [
        "The work context project was removed.",
        "Its home was copied to /home/personal/other-contexts-home-data/project.",
    ]);
    assert.equal(ended.exit_code, 0)
}

test "the home can be given only to another work context, and the confirmation says what will happen" {
    let shell = root.work_context.removing_shell();
    let screens = scripted(["Remove a work context", "project", "Do not keep it", "Remove them", "Remove project"]);

    let _ = manage_work_contexts(shell, root.work_context.removing_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.options.at(2), "Do not keep it, Keep it in the home of personal");
    assert.equal(screens.prompts.at(4),
                 "The work context project is removed, its home is not kept, and the snapshots of its home are removed. This cannot be undone.")
}

test "the last work context is refused on the screen it was chosen on" {
    let shell = root.work_context.removing_shell();
    let _ = shell.replies.set("getent group work-contexts", "work-contexts:x:1002:project\n");
    let screens = scripted(["Remove a work context", "project", "<back>", "Create a work context", "work"]);

    let _ = manage_work_contexts(shell, root.work_context.removing_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.errors, ["'project' is the last work context of this machine"]);
    assert.equal(screens.asked, ["Work contexts", "Work context", "Work context", "Work contexts", "Name"]);
    assert.is_true(!shell.commands.includes("userdel project"))
}

test "going back walks the removal screens backwards" {
    let shell = root.work_context.removing_shell();
    let screens = scripted([
        "Remove a work context", "project", "Do not keep it", "<back>", "Keep it in the home of personal",
        "Remove them", "<back>", "Remove them", "Remove project",
    ]);

    let _ = manage_work_contexts(shell, root.work_context.removing_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, [
        "Work contexts", "Work context", "Home data", "Snapshots", "Home data", "Snapshots", "Confirmation",
        "Snapshots", "Confirmation",
    ]);
    assert.is_true(shell.commands.includes("cp -a /home/project/. /home/personal/other-contexts-home-data/project"))
}

test "a removal that fails ends on what failed" {
    let shell = root.work_context.removing_shell();
    let _ = shell.exit_codes.set("umount /home/project", 32);
    let screens = scripted(["Remove a work context", "project", "Do not keep it", "Remove them", "Remove project"]);

    let ended = manage_work_contexts(shell, root.work_context.removing_files(), root.snapshot.recording_lock(shell),
                                     screens);

    assert.equal(screens.finished, ["unmounting the home of project failed with exit code 32."]);
    assert.is_true(screens.failed);
    assert.equal(ended.exit_code, 1)
}
