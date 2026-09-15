// Listing the snapshots of a machine, narrowed by scope, work context and the
// moment they were taken, as `docs/tools/snapshot/list/000-command.md`
// specifies.

/// What narrows a listing. An empty scope is every scope, an empty work context
/// every work context, and a moment that is null no bound on that side.
class SnapshotFilter {
    scope: string,
    work_context: string,
    since: int?,
    until: int?,
}

/// A snapshot that was listed: the work context whose home it is, empty for the
/// system, and the path it is reached at.
class ListedSnapshot {
    work_context: string,
    path: string,
}

/// The snapshots listed, or what stopped them from being listed.
class Listing {
    snapshots: ListedSnapshot[],
    error: string,
}

/// A moment written as a date and time in UTC, in seconds since the Unix epoch,
/// or what is wrong with how it was written.
class UtcRead {
    seconds: int,
    error: string,
}

function is_leap_year(year: int) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

function days_in_month(year: int, month: int) -> int {
    if (month == 2) {
        return if (is_leap_year(year)) { 29 } else { 28 };
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
        return 30;
    }
    31
}

/// The days from 1970-01-01 to a date of the proleptic Gregorian calendar.
function days_from_civil(year: int, month: int, day: int) -> int {
    let shifted = if (month <= 2) { year - 1 } else { year };
    let era = (if (shifted >= 0) { shifted } else { shifted - 399 }) / 400;
    let year_of_era = shifted - era * 400;
    let month_from_march = (month + 9) % 12;
    let day_of_year = (153 * month_from_march + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146097 + day_of_era - 719468
}

/// Reads a date and time written `YYYY-MM-DDTHH:MM:SS`, as UTC. Anything else is
/// refused: a zone, `Z` or an offset, a fraction of a second, a missing part,
/// and a date or a time the calendar does not have.
function read_utc_date_time(text: string) -> UtcRead {
    let wrong = UtcRead {
        seconds: 0,
        error: `'${text}' is not a date and time in UTC written YYYY-MM-DDTHH:MM:SS, with no zone`,
    };
    if (text.length() != 19) {
        return wrong;
    }
    if (text.slice(4, 5) != "-" || text.slice(7, 8) != "-" || text.slice(10, 11) != "T"
            || text.slice(13, 14) != ":" || text.slice(16, 17) != ":") {
        return wrong;
    }
    let parts = [text.slice(0, 4), text.slice(5, 7), text.slice(8, 10),
                 text.slice(11, 13), text.slice(14, 16), text.slice(17, 19)];
    for (let part in parts) {
        if (!only_digits(part)) {
            return wrong;
        }
    }
    let year = root.common.parse_int(text.slice(0, 4)) ?? 0;
    let month = root.common.parse_int(text.slice(5, 7)) ?? 0;
    let day = root.common.parse_int(text.slice(8, 10)) ?? 0;
    let hour = root.common.parse_int(text.slice(11, 13)) ?? 0;
    let minute = root.common.parse_int(text.slice(14, 16)) ?? 0;
    let second = root.common.parse_int(text.slice(17, 19)) ?? 0;
    if (month < 1 || month > 12 || day < 1 || day > days_in_month(year, month)
            || hour > 23 || minute > 59 || second > 59) {
        return wrong;
    }
    UtcRead {
        seconds: days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second,
        error: "",
    }
}

test "a date and time with no zone is read as UTC" {
    //# each worked out apart from this code, with `date -u`
    assert.equal(read_utc_date_time("2026-09-14T10:00:00").seconds, 1789380000);
    assert.equal(read_utc_date_time("2000-02-29T23:59:59").seconds, 951868799);
    assert.equal(read_utc_date_time("1970-01-01T00:00:00").seconds, 0);
    assert.equal(read_utc_date_time("2026-09-14T10:00:00").error, "")
}

test "a date and time carrying a zone, or written any other way, is refused" {
    let refused = [
        "2026-09-14T10:00:00Z", "2026-09-14T10:00:00+02:00", "2026-09-14T10:00:00.5",
        "2026-09-14 10:00:00", "2026-09-14T10:00", "2026-09-14", "20260914T100000",
        "2026-02-29T00:00:00", "2026-13-01T00:00:00", "2026-09-14T24:00:00", "2026-09-14T1a:00:00",
    ];
    for (let text in refused) {
        assert.equal(read_utc_date_time(text).error,
                     `'${text}' is not a date and time in UTC written YYYY-MM-DDTHH:MM:SS, with no zone`);
    }
}

/// Whether a moment is inside the bounds a filter sets, both of them included.
function within_moments(moment: int, filter: SnapshotFilter) -> bool {
    if let since: int = filter.since {
        if (moment < since) {
            return false;
        }
    }
    if let until: int = filter.until {
        if (moment > until) {
            return false;
        }
    }
    true
}

/// The work contexts whose homes a filter keeps, by name, with "" standing for
/// the system, or what stopped them from being listed.
function listed_scopes(files: root.common.Files, filter: SnapshotFilter) -> Listed {
    let scopes: string[] = [];
    if (filter.scope == "" || filter.scope == "system") {
        scopes.push("");
    }
    if (filter.scope == "" || filter.scope == "home") {
        if (filter.work_context != "") {
            scopes.push(filter.work_context);
        } else {
            let homes = in_snapshots("home");
            if (files.exists(homes)) {
                let listed = files.read_dir(homes);
                if (listed == null) {
                    return Listed { names: [], error: `cannot list ${homes}` };
                }
                let empty: root.common.DirEntry[] = [];
                for (let entry in listed ?? empty) {
                    if (entry.is_dir) {
                        scopes.push(entry.name);
                    }
                }
            }
        }
    }
    Listed { names: scopes, error: "" }
}

/// A moment written at a fixed width, so that sorting the text sorts the moments.
function moment_sort_key(moment: int) -> string {
    let text = `${moment}`;
    while (text.length() < 20) {
        text = "0" + text;
    }
    text
}

/// The snapshots a filter keeps, as the paths they are reached at, earliest
/// first by the moment in their names and, within one second, by path. A
/// directory of a scope that is not there holds none; one that is there and
/// cannot be listed is an error.
function list_snapshots(files: root.common.Files, filter: SnapshotFilter) -> Listing {
    let scopes = listed_scopes(files, filter);
    if (scopes.error != "") {
        return Listing { snapshots: [], error: scopes.error };
    }
    //# each snapshot as its sort key, its path and its work context, kept
    //# together by tabs so that sorting the text sorts by moment and then path
    let keyed: string[] = [];
    for (let work_context in scopes.names) {
        let scope = if (work_context == "") { "system" } else { `home/${work_context}` };
        for (let kind in [automatic_kind(), manual_kind()]) {
            let directory = in_snapshots(`${scope}/${kind}`);
            if (!files.exists(directory)) {
                continue;
            }
            let listed = files.read_dir(directory);
            if (listed == null) {
                return Listing { snapshots: [], error: `cannot list ${directory}` };
            }
            let empty: root.common.DirEntry[] = [];
            for (let entry in listed ?? empty) {
                let moment = moment_of(entry.name) ?? 0;
                if (within_moments(moment, filter)) {
                    keyed.push(moment_sort_key(moment) + "\t" + `${directory}/${entry.name}` + "\t" + work_context);
                }
            }
        }
    }
    let snapshots: ListedSnapshot[] = [];
    for (let line in keyed.sort()) {
        let fields = line.split("\t");
        snapshots.push(ListedSnapshot { work_context: fields.at(2) ?? "", path: fields.at(1) ?? "" });
    }
    Listing { snapshots: snapshots, error: "" }
}

/// The paths of what was listed, in order.
function listed_paths(listing: Listing) -> string[] {
    let paths: string[] = [];
    for (let snapshot in listing.snapshots) {
        paths.push(snapshot.path);
    }
    paths
}

/// A machine with snapshots in every scope.
function listed_files() -> root.common.RecordingFiles {
    let files = root.common.recording_files();
    files.mkdir("/snapshots/system/automatic/@1778761200");
    files.mkdir("/snapshots/system/manual/@1778764800");
    files.mkdir("/snapshots/system/automatic/@1778764800");
    files.mkdir("/snapshots/home/work/automatic/@1778761500");
    files.mkdir("/snapshots/home/work/manual/@1778765100");
    files.mkdir("/snapshots/home/personal/automatic/@999999999");
    files.mkdir("/snapshots/system");
    files.mkdir("/snapshots/system/automatic");
    files.mkdir("/snapshots/system/manual");
    files.mkdir("/snapshots/home");
    files.mkdir("/snapshots/home/work");
    files.mkdir("/snapshots/home/work/automatic");
    files.mkdir("/snapshots/home/work/manual");
    files.mkdir("/snapshots/home/personal");
    files.mkdir("/snapshots/home/personal/automatic");
    files.mkdir("/snapshots/home/personal/manual");
    files
}

function no_filter() -> SnapshotFilter {
    SnapshotFilter { scope: "", work_context: "", since: null, until: null }
}

test "every snapshot is listed, earliest first" {
    let listing = list_snapshots(listed_files(), no_filter());

    //# @999999999 is the earliest though it sorts last as text, and the two
    //# taken in the same second are ordered by path
    assert.equal(listing.error, "");
    assert.equal(listed_paths(listing), [
        "/snapshots/home/personal/automatic/@999999999",
        "/snapshots/system/automatic/@1778761200",
        "/snapshots/home/work/automatic/@1778761500",
        "/snapshots/system/automatic/@1778764800",
        "/snapshots/system/manual/@1778764800",
        "/snapshots/home/work/manual/@1778765100",
    ])
}

test "each snapshot is listed with the work context whose home it is, or none for the system" {
    let contexts: string[] = [];
    for (let snapshot in list_snapshots(listed_files(), no_filter()).snapshots) {
        contexts.push(snapshot.work_context);
    }

    assert.equal(contexts, ["personal", "", "work", "", "", "work"])
}

test "a scope narrows the list to it" {
    let filter = no_filter();
    filter.scope = "system";

    assert.equal(listed_paths(list_snapshots(listed_files(), filter)), [
        "/snapshots/system/automatic/@1778761200",
        "/snapshots/system/automatic/@1778764800",
        "/snapshots/system/manual/@1778764800",
    ])
}

test "a work context narrows the home scope to its home" {
    let filter = no_filter();
    filter.scope = "home";
    filter.work_context = "work";

    assert.equal(listed_paths(list_snapshots(listed_files(), filter)), [
        "/snapshots/home/work/automatic/@1778761500",
        "/snapshots/home/work/manual/@1778765100",
    ])
}

test "the bounds of a moment are both included" {
    let filter = no_filter();
    filter.since = 1778761500;
    filter.until = 1778764800;

    assert.equal(listed_paths(list_snapshots(listed_files(), filter)), [
        "/snapshots/home/work/automatic/@1778761500",
        "/snapshots/system/automatic/@1778764800",
        "/snapshots/system/manual/@1778764800",
    ])
}

test "a machine with no snapshot directories lists nothing" {
    let listing = list_snapshots(root.common.recording_files(), no_filter());

    assert.equal(listing.error, "");
    assert.equal(listed_paths(listing), [])
}

test "a work context with no snapshots lists nothing" {
    let filter = no_filter();
    filter.scope = "home";
    filter.work_context = "client-project";

    assert.equal(listed_paths(list_snapshots(listed_files(), filter)), [])
}
