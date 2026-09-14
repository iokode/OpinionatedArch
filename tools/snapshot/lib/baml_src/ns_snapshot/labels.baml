// The justification of each manual snapshot, kept in one file at the top of
// `@snapshots`, as `docs/tools/snapshot/system-create/001-labels-file-format.md`
// defines it.

/// The labels file, inside `@snapshots`.
function labels_path() -> string {
    "labels.json"
}

/// What the labels file holds: the path of each manual snapshot inside
/// `@snapshots`, and its justification.
class Labels {
    entries: map<string, string>,
    error: string,
}

/// Reads the labels file. A file that is not there holds no labels; a file
/// that is there and cannot be read or is not a labels file is an error, and
/// never read as holding none, because the next label written would replace
/// every one it held.
function read_labels(files: root.common.Files) -> Labels {
    let path = in_snapshots(labels_path());
    let none: map<string, string> = {};
    if (!files.exists(path)) {
        return Labels { entries: none, error: "" };
    }
    let text = files.read(path);
    if (text == null) {
        return Labels { entries: none, error: `cannot read ${path}` };
    }
    let entries = baml.json.from_string<map<string, string>>(text ?? "") catch_all (e) {
        _ => {
            return Labels { entries: none, error: `${path} is not a labels file` };
        }
    };
    Labels { entries: entries, error: "" }
}

/// Pairs a manual snapshot with its justification, keeping every label the file
/// already holds.
function write_label(files: root.common.Files, snapshot: string, justification: string) -> string {
    let labels = read_labels(files);
    if (labels.error != "") {
        return labels.error;
    }
    let _ = labels.entries.set(snapshot, justification);
    files.write(in_snapshots(labels_path()), baml.json.to_string(labels.entries) + "\n");
    files.failure() ?? ""
}

test "a label is added to the ones the file holds" {
    let files = root.common.recording_files();
    files.write("/snapshots/labels.json", "{\"home/work/manual/@1778765100\":\"before the client project import\"}\n");

    assert.equal(write_label(files, "system/manual/@1778764800", "before a kernel upgrade"), "");

    let labels = read_labels(files);
    assert.equal(labels.error, "");
    assert.equal(labels.entries.get("home/work/manual/@1778765100"), "before the client project import");
    assert.equal(labels.entries.get("system/manual/@1778764800"), "before a kernel upgrade")
}

test "a justification keeps every character it was given" {
    let files = root.common.recording_files();
    let justification = "antes de «actualizar» el núcleo\nsecond line\twith a tab, a \\ and a \"";

    assert.equal(write_label(files, "system/manual/@1778764800", justification), "");
    assert.equal(read_labels(files).entries.get("system/manual/@1778764800"), justification)
}

test "a file that is not a labels file is never written over" {
    let files = root.common.recording_files();
    files.write("/snapshots/labels.json", "system/manual/@1778764800 before a kernel upgrade\n");

    assert.equal(write_label(files, "system/manual/@1778851200", "a clean base install"),
                 "/snapshots/labels.json is not a labels file");
    assert.equal(files.written.get("/snapshots/labels.json"),
                 "system/manual/@1778764800 before a kernel upgrade\n")
}

/// A justification is what makes a manual snapshot one that can be judged
/// later, so one with nothing readable in it is refused. "" when it is one.
function check_justification(justification: string) -> string {
    if (justification.trim() == "") {
        return "a manual snapshot needs a justification, and this one is empty";
    }
    ""
}

test "an empty justification is refused, and any other is taken" {
    assert.equal(check_justification(""), "a manual snapshot needs a justification, and this one is empty");
    assert.equal(check_justification(" \n"), "a manual snapshot needs a justification, and this one is empty");
    assert.equal(check_justification("before a kernel upgrade"), "")
}
