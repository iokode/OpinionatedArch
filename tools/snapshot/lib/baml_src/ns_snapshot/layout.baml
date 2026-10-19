// Where the snapshots of a machine are and what each one is called, as
// `docs/decisions/004-snapshots.md` and `docs/decisions/001-disk-layout.md`
// lay them out.

/// Where `@snapshots` is mounted. Every path this library writes under it is
/// kept relative to it, and joined to it only where something is touched.
function snapshots_root() -> string {
    "/snapshots"
}

/// A path inside `@snapshots`, as it is reached on the machine.
function in_snapshots(relative: string) -> string {
    root.common.in_directory(snapshots_root(), relative)
}

/// A snapshot the operator asked for, which carries a justification and is
/// never purged.
function manual_kind() -> string {
    "manual"
}

/// A snapshot taken at a moment the policy names, with nobody there to take it.
function automatic_kind() -> string {
    "automatic"
}

/// What a snapshot is called: the moment it was taken, in seconds since the
/// Unix epoch. The justification of a manual one is in the labels file, not in
/// its name.
function snapshot_name(seconds: int) -> string {
    `@${seconds}`
}

test "a snapshot is named after the moment it was taken" {
    assert.equal(snapshot_name(1778764800), "@1778764800")
}

/// Where a system snapshot of a kind goes, inside `@snapshots`.
function system_snapshot_path(kind: string, name: string) -> string {
    `system/${kind}/${name}`
}

/// The home a snapshot of a work context's scope is taken of: the subvolume
/// `home/@<work-context>`, mounted at the context's home.
function home_directory(work_context: string) -> string {
    `/home/${work_context}`
}

/// Where a snapshot of a work context's home of a kind goes, inside
/// `@snapshots`.
function home_snapshot_path(work_context: string, kind: string, name: string) -> string {
    `home/${work_context}/${kind}/${name}`
}

test "a snapshot of a home is under that context's directory of its kind" {
    assert.equal(home_directory("work"), "/home/work");
    assert.equal(home_snapshot_path("work", manual_kind(), "@1778765100"), "home/work/manual/@1778765100")
}

test "a system snapshot is under the system directory of its kind" {
    assert.equal(system_snapshot_path(manual_kind(), "@1778764800"), "system/manual/@1778764800");
    assert.equal(in_snapshots("system/manual/@1778764800"), "/snapshots/system/manual/@1778764800")
}

/// What a command that failed is reported as: what was being done, and then
/// what the command said. These tools have no log to put the second part
/// behind, so the message they print is the only place an operator reads it.
function failed(result: root.common.CommandResult, what: string) -> string {
    let problem = root.common.must(result, what);
    if (problem == "") {
        return "";
    }
    let said = root.common.nonempty_lines(result.stderr);
    if (said.length() == 0) {
        return problem;
    }
    problem + "\n" + said.join("\n")
}

test "a failed command is reported with what it said" {
    let refused = root.common.CommandResult {
        exit_code: 1, stdout: "", stderr: "ERROR: Could not statfs: No such file or directory\n",
    };

    assert.equal(failed(refused, "taking the snapshot"),
                 "taking the snapshot failed with exit code 1.\nERROR: Could not statfs: No such file or directory");
    assert.equal(failed(root.common.CommandResult { exit_code: 0, stdout: "", stderr: "" }, "taking the snapshot"), "")
}
