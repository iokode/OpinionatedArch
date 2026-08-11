// What each question says about itself, read from the assets.
//
// A note beside a question is a decision, so it does not live in the host that
// draws it. It does not live in this file either: it is prose, it is read by
// whoever is installing, and it changes far more often than the code around it.
// It lives in `installer-tips.yaml`, beside the other assets, and is read once
// when the form starts.
//
// Nothing depends on it. A key that is not there is a question asked without a
// note, and a file that cannot be read is every question asked without one.

class Tips {
    notes: map<string, string[]>,
}

function no_tips() -> Tips {
    Tips { notes: {} }
}

/// Where the notes live, beside the packages and the Plymouth theme.
function tips_path(asset_dir: string) -> string {
    root.common.in_directory(asset_dir, "installer-tips.yaml")
}

/// Reads the notes. A file that is missing, unreadable or not a mapping leaves
/// the installer without notes rather than without an installer: an explanation
/// that cannot be found is not a reason to refuse to install a system.
function load_tips(files: root.common.Files, ui: Ui, asset_dir: string) -> Tips {
    let path = tips_path(asset_dir);
    let text = files.read(path);
    if (text == null) {
        ui.warn(`No notes file at ${path}: every question is asked without one.`);
        return no_tips();
    }

    let document = baml.yaml.parse(text)
        catch (e) {
            _ => {
                ui.warn(`The notes file is not valid YAML, so every question is asked`
                    + ` without a note: ${path}: ${e.message}`);
                return no_tips();
            }
        };
    let top = root.common.as_map(document) ?? root.common.empty_json_map();
    if (root.common.as_map(document) == null) {
        ui.warn(`The notes file is not a mapping, so every question is asked without`
            + ` a note: ${path}`);
        return no_tips();
    }

    let notes: map<string, string[]> = {};
    for (let key in top.keys()) {
        if let lines: string[] = root.common.text_list(top.get(key)) {
            let _ = notes.set(key, lines);
        } else {
            //# one bad entry loses one note, and says which
            ui.warn(`The note for ${key} is not a list of text and was left out: ${path}`);
        }
    }
    Tips { notes: notes }
}

/// The note for a question, or nothing at all.
function tip_for(tips: Tips, key: string) -> string[] {
    tips.notes.get(key) ?? root.common.empty_names()
}

// -------------------------------------------------------------------- tests

function silent() -> ScriptedUi {
    ScriptedUi {
        answers: [], asked: [], steps: [], actions: [], errors: [], outline: [], warnings: [], tips: [],
        limits: [],
    }
}

function sample_tips_file() -> string {
    "gpu:\n"
        + "  - \"nvidia: the proprietary driver.\"\n"
        + "  - \"none: for AMD and Intel graphics.\"\n"
        + "hostname:\n"
        + "  - \"The name this machine answers to on a network.\"\n"
}

test "the notes are read from the assets, one entry per question" {
    let files = root.common.recording_files();
    files.write("/assets/installer-tips.yaml", sample_tips_file());

    let tips = load_tips(files, silent(), "/assets");

    assert.equal(tip_for(tips, "gpu"),
                 ["nvidia: the proprietary driver.", "none: for AMD and Intel graphics."]);
    assert.equal(tip_for(tips, "hostname").length(), 1)
}

test "a question with no note is asked without one" {
    let files = root.common.recording_files();
    files.write("/assets/installer-tips.yaml", sample_tips_file());

    assert.equal(tip_for(load_tips(files, silent(), "/assets"), "swapfile"), [])
}

test "a file that is not there leaves every question without a note, and says so" {
    //# an explanation that cannot be found is not a reason to refuse to install,
    //# but it is a reason to write a line in the log
    let ui = silent();
    assert.equal(tip_for(load_tips(root.common.recording_files(), ui, "/assets"), "gpu"), []);
    assert.equal(ui.warnings,
                 ["No notes file at /assets/installer-tips.yaml:"
                      + " every question is asked without one."])
}

test "a file that is not a mapping is refused as a whole, and reported" {
    let files = root.common.recording_files();
    files.write("/assets/installer-tips.yaml", "- just\n- a list\n");
    let ui = silent();

    assert.equal(tip_for(load_tips(files, ui, "/assets"), "gpu"), []);
    assert.is_true((ui.warnings.at(0) ?? "").starts_with("The notes file is not a mapping"))
}

test "a file that is not YAML at all is reported with what the reader said" {
    let files = root.common.recording_files();
    files.write("/assets/installer-tips.yaml", "gpu:\n  - \"unterminated\n");
    let ui = silent();

    assert.equal(tip_for(load_tips(files, ui, "/assets"), "gpu"), []);
    assert.is_true((ui.warnings.at(0) ?? "").starts_with("The notes file is not valid YAML"))
}

test "an entry that is not a list of text is left out, named, and the rest is kept" {
    let files = root.common.recording_files();
    files.write("/assets/installer-tips.yaml", sample_tips_file() + "zram: 8\n");
    let ui = silent();

    let tips = load_tips(files, ui, "/assets");
    assert.equal(tip_for(tips, "zram"), []);
    assert.equal(tip_for(tips, "hostname").length(), 1);
    assert.equal(ui.warnings,
                 ["The note for zram is not a list of text and was left out:"
                      + " /assets/installer-tips.yaml"])
}

test "a file that reads cleanly says nothing at all" {
    let files = root.common.recording_files();
    files.write("/assets/installer-tips.yaml", sample_tips_file());
    let ui = silent();

    let _ = load_tips(files, ui, "/assets");
    assert.equal(ui.warnings, [])
}
