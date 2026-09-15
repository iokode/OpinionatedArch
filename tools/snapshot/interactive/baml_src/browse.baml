// The screens of oparch-snapshot-interactive, and what each takes as an
// answer. Listing, taking and removing a snapshot are the snapshot library's:
// this shows what it lists, collects what it is called with, and says how it
// went.

/// What narrows the list of snapshots. The scope, the work context and the two
/// moments are the library's filter; the kind and the text narrow what the
/// library describes.
class Narrowing {
    filter: root.snapshot.SnapshotFilter,
    /// "" for both kinds, or the one kept.
    kind: string,
    /// "" for any justification, or text the justification has to contain,
    /// whatever its case.
    text: string,
}

function no_narrowing() -> Narrowing {
    Narrowing {
        filter: root.snapshot.SnapshotFilter { scope: "", work_context: "", since: null, until: null },
        kind: "",
        text: "",
    }
}

function is_narrowed(narrowing: Narrowing) -> bool {
    narrowing.filter.scope != "" || narrowing.filter.since != null || narrowing.filter.until != null
        || narrowing.kind != "" || narrowing.text != ""
}

/// Whether a snapshot the library described is one the kind and the text keep.
function kept(snapshot: root.snapshot.DescribedSnapshot, narrowing: Narrowing) -> bool {
    if (narrowing.kind == root.snapshot.manual_kind() && !snapshot.is_manual) {
        return false;
    }
    if (narrowing.kind == root.snapshot.automatic_kind() && snapshot.is_manual) {
        return false;
    }
    narrowing.text == "" || snapshot.justification.to_lower_case().includes(narrowing.text.to_lower_case())
}

// ------------------------------------------------------------ how it reads

function padded_text(text: string, width: int) -> string {
    let out = text;
    while (out.length() < width) {
        out = out + " ";
    }
    out
}

/// A justification on one row: its lines, one after the other.
function one_line(text: string) -> string {
    text.split("\n").join(" ")
}

function kind_name(snapshot: root.snapshot.DescribedSnapshot) -> string {
    if (snapshot.is_manual) {
        return root.snapshot.manual_kind();
    }
    root.snapshot.automatic_kind()
}

/// A row for each snapshot, in columns: when it was taken, in UTC, its scope,
/// the work context whose home it is, whether it is automatic or manual, and
/// its justification. The work context column is as wide as the longest name
/// in it, and is not there when no snapshot shown is of a home.
function snapshot_rows(snapshots: root.snapshot.DescribedSnapshot[]) -> string[] {
    let width = 0;
    for (let snapshot in snapshots) {
        if (snapshot.work_context.length() > width) {
            width = snapshot.work_context.length();
        }
    }
    let rows: string[] = [];
    for (let snapshot in snapshots) {
        let scope = if (snapshot.work_context == "") { "system" } else { "home" };
        let columns = [root.snapshot.utc_date_time(snapshot.moment), padded_text(scope, 6)];
        if (width > 0) {
            columns.push(padded_text(snapshot.work_context, width));
        }
        columns.push(padded_text(kind_name(snapshot), 9));
        columns.push(one_line(snapshot.justification));
        rows.push(columns.join("  ").trim());
    }
    rows
}

/// Everything known about a snapshot, for the question that removes it.
function snapshot_lines(snapshot: root.snapshot.DescribedSnapshot) -> string[] {
    let lines: string[] = [];
    if (snapshot.work_context == "") {
        lines.push("Scope: system");
    } else {
        lines.push("Scope: home");
        lines.push(`Work context: ${snapshot.work_context}`);
    }
    lines.push(`Kind: ${kind_name(snapshot)}`);
    lines.push(`Taken: ${root.snapshot.utc_date_time(snapshot.moment)} UTC`);
    if (snapshot.justification != "") {
        let parts = snapshot.justification.split("\n");
        lines.push(`Justification: ${parts.at(0) ?? ""}`);
        lines = lines.concat(parts.slice(1, parts.length()));
    }
    lines.push(`Path: ${snapshot.path}`);
    lines
}

// -------------------------------------------------------- the list itself

function narrow_option() -> string {
    "[ Narrow the list ]"
}

function create_option() -> string {
    "[ Take a manual snapshot ]"
}

/// Shows the snapshots, and carries out what is chosen from them, until the
/// operator leaves.
///
/// The list is read again every time it is shown, so what an operation did is
/// in it. It has nothing behind it: going back from it shows it again.
function browse(shell: root.common.Shell, files: root.common.Files, lock: root.snapshot.SnapshotLock,
                screens: Screens) -> void {
    let narrowing = no_narrowing();
    let left = false;
    while (!left) {
        let described = root.snapshot.describe_snapshots(files, narrowing.filter);
        if (described.error != "") {
            screens.error(described.error);
        }
        let shown: root.snapshot.DescribedSnapshot[] = [];
        for (let snapshot in described.snapshots) {
            if (kept(snapshot, narrowing)) {
                shown.push(snapshot);
            }
        }
        let which = if (is_narrowed(narrowing)) { "The snapshots the list is narrowed to" } else { "Every snapshot" };
        let choice = screens.choose("Snapshots",
                                    `${which}, earliest first, each after the date and time in UTC it was taken. Choosing one removes it, once confirmed.`,
                                    [narrow_option(), create_option()].concat(snapshot_rows(shown)), false);
        left = choice.leave;
        if let index: int = choice.index {
            if (index == 0) {
                left = narrow(files, screens, narrowing);
            } else if (index == 1) {
                left = create(shell, files, lock, screens);
            } else {
                if let snapshot: root.snapshot.DescribedSnapshot = shown.at(index - 2) {
                    remove(shell, files, lock, screens, snapshot);
                }
            }
        }
    }
}

// ------------------------------------------------------------- narrowing

/// What the list can be narrowed by, in the order it is offered: the work
/// context only once the scope is the home.
function criteria(narrowing: Narrowing) -> string[] {
    let names = ["scope"];
    if (narrowing.filter.scope == "home") {
        names.push("work context");
    }
    names.concat(["since", "until", "kind", "text"])
}

/// How a criterion is offered: what it is, and what it narrows to now.
function criterion_option(narrowing: Narrowing, name: string) -> string {
    if (name == "scope") {
        let scope = if (narrowing.filter.scope == "") { "every scope" } else { narrowing.filter.scope };
        return `Scope: ${scope}`;
    }
    if (name == "work context") {
        let work_context = if (narrowing.filter.work_context == "") { "every work context" } else { narrowing.filter.work_context };
        return `Work context: ${work_context}`;
    }
    if (name == "since") {
        if let since: int = narrowing.filter.since {
            return `Taken since: ${root.snapshot.utc_date_time(since)}`;
        }
        return "Taken since: no bound";
    }
    if (name == "until") {
        if let until: int = narrowing.filter.until {
            return `Taken until: ${root.snapshot.utc_date_time(until)}`;
        }
        return "Taken until: no bound";
    }
    if (name == "kind") {
        let kind = if (narrowing.kind == "") { "automatic and manual" } else { narrowing.kind };
        return `Kind: ${kind}`;
    }
    let text = if (narrowing.text == "") { "anything" } else { narrowing.text };
    `Justification contains: ${text}`
}

/// The screen that narrows the list, and the one asking each criterion. What
/// is answered narrows the list at once; going back shows it. True when the
/// operator left.
function narrow(files: root.common.Files, screens: Screens, narrowing: Narrowing) -> bool {
    let done = false;
    let left = false;
    while (!done) {
        let names = criteria(narrowing);
        let options: string[] = [];
        for (let name in names) {
            options.push(criterion_option(narrowing, name));
        }
        let choice = screens.choose("Narrow the list",
                                    "Choose what the list is narrowed by. Going back shows the list, narrowed.",
                                    options, true);
        left = choice.leave;
        done = true;
        if let index: int = choice.index {
            left = narrow_by(files, screens, narrowing, names.at(index) ?? "");
            done = left;
        }
    }
    left
}

function narrow_by(files: root.common.Files, screens: Screens, narrowing: Narrowing, name: string) -> bool {
    if (name == "scope") {
        return narrow_scope(screens, narrowing);
    }
    if (name == "work context") {
        return narrow_work_context(files, screens, narrowing);
    }
    if (name == "since" || name == "until") {
        return narrow_moment(screens, narrowing, name);
    }
    if (name == "kind") {
        return narrow_kind(screens, narrowing);
    }
    narrow_text(screens, narrowing)
}

/// Either scope, or both. A scope that is not the home narrows to no work
/// context.
function narrow_scope(screens: Screens, narrowing: Narrowing) -> bool {
    let scopes = ["", "system", "home"];
    let choice = screens.choose("Scope", "The scope the list is narrowed to.", ["Every scope", "system", "home"], true);
    if let index: int = choice.index {
        narrowing.filter.scope = scopes.at(index) ?? "";
        if (narrowing.filter.scope != "home") {
            narrowing.filter.work_context = "";
        }
    }
    choice.leave
}

/// One work context, or all of them. What is offered is the work contexts
/// whose homes have snapshots, which is what the list can hold.
function narrow_work_context(files: root.common.Files, screens: Screens, narrowing: Narrowing) -> bool {
    let homes = root.snapshot.list_snapshots(files,
        root.snapshot.SnapshotFilter { scope: "home", work_context: "", since: null, until: null });
    if (homes.error != "") {
        screens.error(homes.error);
        return false;
    }
    let found: string[] = [];
    for (let snapshot in homes.snapshots) {
        if (!found.includes(snapshot.work_context)) {
            found.push(snapshot.work_context);
        }
    }
    let contexts = found.sort();
    let choice = screens.choose("Work context", "The work context whose home the list is narrowed to.",
                                ["Every work context"].concat(contexts), true);
    if let index: int = choice.index {
        narrowing.filter.work_context = if (index == 0) { "" } else { contexts.at(index - 1) ?? "" };
    }
    choice.leave
}

/// A bound on the moment a snapshot was taken, included, written as the
/// library reads it. An empty field is no bound, and anything the library does
/// not read as a date and time is said so and asked again, as it was typed.
function narrow_moment(screens: Screens, narrowing: Narrowing, bound: string) -> bool {
    let current = if (bound == "since") { narrowing.filter.since } else { narrowing.filter.until };
    let initial = "";
    if let moment: int = current {
        initial = root.snapshot.utc_date_time(moment);
    }
    let title = if (bound == "since") { "Taken since" } else { "Taken until" };
    let side = if (bound == "since") { "earliest" } else { "latest" };
    let done = false;
    let left = false;
    while (!done) {
        let typed = screens.text(title,
                                 `The ${side} date and time in UTC a snapshot shown was taken at, written YYYY-MM-DDTHH:MM:SS. Empty for no bound.`,
                                 initial);
        left = typed.leave;
        done = true;
        if let given: string = typed.value {
            let read = root.snapshot.read_utc_date_time(given);
            let seconds: int? = if (given == "") { null } else { read.seconds };
            if (given != "" && read.error != "") {
                screens.error(read.error);
                initial = given;
                done = false;
            } else if (bound == "since") {
                narrowing.filter.since = seconds;
            } else {
                narrowing.filter.until = seconds;
            }
        }
    }
    left
}

function narrow_kind(screens: Screens, narrowing: Narrowing) -> bool {
    let kinds = ["", root.snapshot.automatic_kind(), root.snapshot.manual_kind()];
    let choice = screens.choose("Kind", "Whether the list is narrowed to automatic or to manual snapshots.",
                                ["Automatic and manual"].concat(kinds.slice(1, 3)), true);
    if let index: int = choice.index {
        narrowing.kind = kinds.at(index) ?? "";
    }
    choice.leave
}

function narrow_text(screens: Screens, narrowing: Narrowing) -> bool {
    let typed = screens.text("Justification",
                             "Text the justification of a snapshot shown contains, whatever its case. Empty for any.",
                             narrowing.text);
    if let given: string = typed.value {
        narrowing.text = given;
    }
    typed.leave
}

// -------------------------------------------------------------- creating

/// Asks the scope, the work context when the scope is the home, and the
/// justification, then takes the snapshot through the library and says how it
/// went. Going back returns to the screen before, and from the first to the
/// list. True when the operator left.
function create(shell: root.common.Shell, files: root.common.Files, lock: root.snapshot.SnapshotLock,
                screens: Screens) -> bool {
    //# 0 the scope, 1 the work context, 2 the justification; 3 once they are
    //# all answered, and -1 once the operator went back to the list
    let at = 0;
    let is_system = true;
    let work_context = "";
    let justification = "";
    let left = false;
    while (at >= 0 && at < 3 && !left) {
        if (at == 0) {
            let choice = screens.choose("Scope",
                                        "What the manual snapshot is taken of: the system, or the home of a work context.",
                                        ["system", "home"], true);
            left = choice.leave;
            at = -1;
            if let index: int = choice.index {
                is_system = index == 0;
                at = if (is_system) { 2 } else { 1 };
            }
        } else if (at == 1) {
            let contexts = root.work_context.list_work_contexts(shell);
            if (contexts.error != "") {
                screens.error(contexts.error);
                at = 0;
            } else {
                let choice = screens.choose("Work context", "The work context whose home is snapshotted.",
                                            contexts.names, true);
                left = choice.leave;
                at = 0;
                if let index: int = choice.index {
                    work_context = contexts.names.at(index) ?? "";
                    at = 2;
                }
            }
        } else {
            let typed = screens.text("Justification",
                                     "Why the snapshot is taken. It is kept with it, so that whether it is still worth keeping can be judged later.",
                                     justification);
            left = typed.leave;
            if let given: string = typed.value {
                //# refused here by the same check the library makes, so the
                //# operator is told on the screen the answer was given on
                let refused = root.snapshot.check_justification(given);
                if (refused != "") {
                    screens.error(refused);
                } else {
                    justification = given;
                    at = 3;
                }
            } else {
                at = if (is_system) { 0 } else { 1 };
            }
        }
    }
    if (!left && at == 3) {
        screens.action("Taking the snapshot");
        let taken = if (is_system) {
            root.snapshot.take_system_snapshot(shell, files, lock, root.snapshot.manual_kind(), justification)
        } else {
            root.snapshot.take_home_snapshot(shell, files, lock, work_context, root.snapshot.manual_kind(),
                                             justification)
        };
        if (taken.error == "") {
            screens.notice("Snapshot taken", [taken.path]);
        } else {
            screens.notice("Snapshot not taken", taken.error.split("\n"));
        }
    }
    left
}

// -------------------------------------------------------------- removing

/// Asks whether the snapshot chosen is to be removed, showing all of it, and
/// removes it through the library once it is, saying how it went.
function remove(shell: root.common.Shell, files: root.common.Files, lock: root.snapshot.SnapshotLock,
                screens: Screens, snapshot: root.snapshot.DescribedSnapshot) -> void {
    if (screens.confirm("Remove this snapshot?", snapshot_lines(snapshot))) {
        screens.action("Removing the snapshot");
        let removed = root.snapshot.remove_snapshot(shell, files, lock, snapshot.path);
        if (removed == "") {
            screens.notice("Snapshot removed", [snapshot.path]);
        } else {
            screens.notice("Snapshot not removed", removed.split("\n"));
        }
    }
}

// -------------------------------------------------------------------- tests

/// A machine with a snapshot of each kind of each scope, two of them labelled.
function machine_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    for (let directory in ["/snapshots/system", "/snapshots/system/automatic", "/snapshots/system/manual",
                           "/snapshots/home", "/snapshots/home/personal", "/snapshots/home/personal/automatic",
                           "/snapshots/home/work", "/snapshots/home/work/manual",
                           "/snapshots/system/automatic/@1778761200", "/snapshots/system/manual/@1778764800",
                           "/snapshots/home/personal/automatic/@1778761500",
                           "/snapshots/home/work/manual/@1778765100"]) {
        files.mkdir(directory);
    }
    files.write("/snapshots/labels.json",
                "{\"system/manual/@1778764800\":\"before a kernel upgrade\",\"home/work/manual/@1778765100\":\"before the Import\\nof the archive\"}\n");
    files
}

function machine_shell() -> root.common.RecordingShell {
    root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: {
            "getent group work-contexts": "work-contexts:x:1002:personal,work\n",
            "date +%s": "1778800000\n",
        },
    }
}

function rows_shown(screens: ScriptedScreens) -> string[] {
    let options = screens.shown.get("Snapshots") ?? [];
    options.slice(2, options.length())
}

test "every snapshot is shown with its moment, scope, work context, kind and justification" {
    let shell = machine_shell();
    let screens = scripted([]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, ["Snapshots"]);
    assert.equal(screens.backs, [false]);
    assert.equal(screens.shown.get("Snapshots"), [
        "[ Narrow the list ]",
        "[ Take a manual snapshot ]",
        "2026-05-14T12:20:00  system            automatic",
        "2026-05-14T12:25:00  home    personal  automatic",
        "2026-05-14T13:20:00  system            manual     before a kernel upgrade",
        "2026-05-14T13:25:00  home    work      manual     before the Import of the archive",
    ]);
    assert.equal(shell.commands, [])
}

test "the list is narrowed to a scope and then to a work context of it" {
    let shell = machine_shell();
    let screens = scripted([
        "Narrow the list", "Scope:", "home", "Work context:", "work", "<back>",
    ]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, ["Snapshots", "Narrow the list", "Scope", "Narrow the list", "Work context",
                                 "Narrow the list", "Snapshots"]);
    assert.equal(screens.shown.get("Work context"), ["Every work context", "personal", "work"]);
    assert.equal(screens.shown.get("Narrow the list"), [
        "Scope: home", "Work context: work", "Taken since: no bound", "Taken until: no bound",
        "Kind: automatic and manual", "Justification contains: anything",
    ]);
    assert.equal(rows_shown(screens), [
        "2026-05-14T13:25:00  home    work  manual     before the Import of the archive",
    ])
}

test "the system scope offers no work context to narrow to" {
    let shell = machine_shell();
    let screens = scripted(["Narrow the list", "Scope:", "system", "<back>"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.shown.get("Narrow the list"), [
        "Scope: system", "Taken since: no bound", "Taken until: no bound",
        "Kind: automatic and manual", "Justification contains: anything",
    ]);
    assert.equal(rows_shown(screens), [
        "2026-05-14T12:20:00  system  automatic",
        "2026-05-14T13:20:00  system  manual     before a kernel upgrade",
    ])
}

test "the moments the list is narrowed between are both included, and a date written wrong is said so" {
    let shell = machine_shell();
    let screens = scripted([
        "Narrow the list", "Taken since", "2026-05-14 12:25", "2026-05-14T12:25:00",
        "Taken until", "2026-05-14T13:20:00", "<back>",
    ]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.errors, [
        "'2026-05-14 12:25' is not a date and time in UTC written YYYY-MM-DDTHH:MM:SS, with no zone",
    ]);
    //# asked again as it was typed, and the bound offered again as it was set
    assert.equal(screens.initials, ["", "2026-05-14 12:25", ""]);
    assert.equal(rows_shown(screens), [
        "2026-05-14T12:25:00  home    personal  automatic",
        "2026-05-14T13:20:00  system            manual     before a kernel upgrade",
    ])
}

test "an empty bound is no bound" {
    let shell = machine_shell();
    let screens = scripted([
        "Narrow the list", "Taken since", "2026-05-14T13:00:00", "Taken since", "", "<back>",
    ]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.initials, ["", "2026-05-14T13:00:00"]);
    assert.equal(rows_shown(screens).length(), 4)
}

test "the list is narrowed to a kind, and to text in the justification whatever its case" {
    let shell = machine_shell();
    let screens = scripted([
        "Narrow the list", "Kind:", "manual", "Justification contains", "IMPORT", "<back>",
    ]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(rows_shown(screens), [
        "2026-05-14T13:25:00  home    work  manual     before the Import of the archive",
    ])
}

test "an automatic snapshot has no justification for text to be found in" {
    let shell = machine_shell();
    let screens = scripted(["Narrow the list", "Justification contains", "a", "<back>"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(rows_shown(screens), [
        "2026-05-14T13:20:00  system        manual     before a kernel upgrade",
        "2026-05-14T13:25:00  home    work  manual     before the Import of the archive",
    ])
}

test "a manual snapshot of a home is taken through the library, of a member of work-contexts" {
    let shell = machine_shell();
    let files = machine_files();
    let screens = scripted(["Take a manual snapshot", "home", "work", "before a bulk move"]);

    browse(shell, files, root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, ["Snapshots", "Scope", "Work context", "Justification", "Snapshots"]);
    assert.equal(screens.shown.get("Work context"), ["personal", "work"]);
    assert.equal(shell.commands, [
        "getent group work-contexts",
        "lock /snapshots/lock",
        "date +%s",
        "btrfs subvolume snapshot -r /home/work /snapshots/home/work/manual/@1778800000",
        "unlock /snapshots/lock",
    ]);
    assert.equal(screens.actions, ["Taking the snapshot"]);
    assert.equal(screens.noticed, ["Snapshot taken", "/snapshots/home/work/manual/@1778800000"]);
    assert.equal(root.snapshot.read_labels(files).entries.get("home/work/manual/@1778800000"), "before a bulk move")
}

test "an empty justification is refused on its own screen, and going back returns to the screen before" {
    let shell = machine_shell();
    let screens = scripted(["Take a manual snapshot", "system", " ", "<back>", "home", "<back>", "<back>"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.errors, ["a manual snapshot needs a justification, and this one is empty"]);
    //# the system has no work context to ask, so its justification goes back
    //# to the scope
    assert.equal(screens.asked, [
        "Snapshots", "Scope", "Justification", "Justification", "Scope", "Work context", "Scope", "Snapshots",
    ]);
    assert.equal(shell.commands, ["getent group work-contexts"])
}

test "a snapshot chosen from the list is removed through the library once it is confirmed" {
    let shell = machine_shell();
    let files = machine_files();
    let screens = scripted(["before the Import", "yes"]);

    browse(shell, files, root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.confirmed, [
        "Remove this snapshot?", "Scope: home", "Work context: work", "Kind: manual",
        "Taken: 2026-05-14T13:25:00 UTC", "Justification: before the Import", "of the archive",
        "Path: /snapshots/home/work/manual/@1778765100",
    ]);
    assert.equal(shell.commands, [
        "lock /snapshots/lock",
        "btrfs subvolume delete /snapshots/home/work/manual/@1778765100",
        "unlock /snapshots/lock",
    ]);
    assert.equal(screens.actions, ["Removing the snapshot"]);
    assert.equal(screens.noticed, ["Snapshot removed", "/snapshots/home/work/manual/@1778765100"]);
    assert.equal(root.snapshot.read_labels(files).entries.get("home/work/manual/@1778765100"), null)
}

test "a snapshot whose removal is not confirmed is left as it is" {
    let shell = machine_shell();
    let screens = scripted(["before a kernel upgrade", "no"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, ["Snapshots", "Snapshots"]);
    assert.equal(shell.commands, []);
    assert.equal(screens.noticed, [])
}

test "an operation that fails is said with what the library said, and the list is shown again" {
    let shell = machine_shell();
    let _ = shell.exit_codes.set("btrfs subvolume delete /snapshots/system/manual/@1778764800", 1);
    let screens = scripted(["before a kernel upgrade", "yes"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.noticed, [
        "Snapshot not removed", "deleting the snapshot /snapshots/system/manual/@1778764800 failed with exit code 1.",
    ]);
    assert.equal(screens.asked, ["Snapshots", "Snapshots"]);
    assert.equal(rows_shown(screens).length(), 4)
}

test "a work context that cannot be read is said on the screen before" {
    let shell = machine_shell();
    let _ = shell.exit_codes.set("getent group work-contexts", 1);
    let screens = scripted(["Take a manual snapshot", "home", "<back>"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.errors, ["reading the 'work-contexts' group failed with exit code 1."]);
    assert.equal(screens.asked, ["Snapshots", "Scope", "Scope", "Snapshots"])
}

test "leaving from any screen ends the run with nothing done" {
    let shell = machine_shell();
    let screens = scripted(["Take a manual snapshot", "home", "work", "<leave>"]);

    browse(shell, machine_files(), root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.asked, ["Snapshots", "Scope", "Work context", "Justification"]);
    assert.equal(shell.commands, ["getent group work-contexts"])
}

test "a labels file that cannot be read is said on the list" {
    let shell = machine_shell();
    let files = machine_files();
    files.write("/snapshots/labels.json", "not json\n");
    let screens = scripted([]);

    browse(shell, files, root.snapshot.recording_lock(shell), screens);

    assert.equal(screens.errors, ["/snapshots/labels.json is not a labels file"]);
    assert.equal(rows_shown(screens), [])
}
