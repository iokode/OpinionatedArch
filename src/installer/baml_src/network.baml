// Reaching a network from the live environment, and what the screen that asks
// about it reads to do its work.
//
// The wireless side is `iwd`, because that is what the live medium carries:
// `networkmanager` is not among its packages, so `iwctl` is not a preference
// here but the only client there is.

/// Where the name of a network sits in what `iwctl` prints, as character
/// offsets into a line with its colouring removed.
///
/// The table is iwd's own and its widths are fixed: two characters of margin,
/// two for the marker it puts against the network it is connected to, two more
/// of separation, and then the name in a field of thirty-two.
///
/// A name never overruns that field. iwd wraps a value too wide for its column
/// onto a second line, which would make this unreadable — but 802.11 caps an
/// SSID at thirty-two octets, and thirty-two is the width iwd chose for it.
function name_field_start() -> int { 6 }
function name_field_end() -> int { 38 }

/// The text of a line with any ANSI colouring taken out.
///
/// iwd colours the marker in front of the network it is connected to, and
/// those escapes sit before the columns, so a line that is read by position
/// has to have them removed first. A sequence starts at the one control
/// character a line of output has in it — the escape — and ends at the first
/// letter after it, which is the shape of every sequence iwd emits.
function without_colour(line: string) -> string {
    let plain = "";
    let skipping = false;
    for (let ch in line.chars()) {
        if (skipping) {
            if (ch.is_alphabetic()) {
                skipping = false;
            }
        } else if (ch.is_control()) {
            skipping = true;
        } else {
            plain = `${plain}${ch}`;
        }
    }
    plain
}

// What this leaves alone is tested; what it removes is not, and cannot be
// from here. A BAML string literal has no escape for a code point — `"\x1b"`
// is four characters and `"\u{1b}"` is six — and the language offers nothing
// that turns a number into a character, so an escape can only reach a test by
// being written into this file as the byte it is. That is a character no
// reader of the source can see, in a project whose sources are meant to be
// read, and it is not worth one assertion.
//
// So the removal is exercised the first time this runs against iwd, and this
// note is what says so rather than a passing suite implying otherwise.
test "without_colour leaves a line that has no colouring in it alone" {
    assert.equal(without_colour("  Home                            psk"),
                 "  Home                            psk");
    assert.equal(without_colour(""), "")
}

/// True of the rules iwd draws above and below a table, which are a run of
/// dashes and nothing else.
function is_rule(line: string) -> bool {
    let trimmed = line.trim();
    trimmed != "" && trimmed.replace_all("-", "") == ""
}

test "is_rule knows a rule from a row" {
    assert.equal(is_rule("--------"), true);
    assert.equal(is_rule("  ----  "), true);
    assert.equal(is_rule(""), false);
    assert.equal(is_rule("  Home    psk"), false)
}

/// The network names in what `iwctl station <device> get-networks` printed.
///
/// The rows are found by counting rules rather than by recognising the
/// heading: a table is a title, a rule, the column names, a rule, the rows,
/// and a rule under them. Everything before the second rule is furniture, and
/// the next rule ends the rows. Nothing here has to know what a column is
/// called, so a network named after one is still read as a network.
///
/// A row is indented by iwd's margin, and what it says when it has no rows to
/// print is not: that is what tells a network from the sentence saying there
/// are none.
function network_names(output: string) -> string[] {
    let names: string[] = [];
    let rules = 0;
    for (let line in output.lines()) {
        let plain = without_colour(line);
        if (is_rule(plain)) {
            rules = rules + 1;
        } else if (rules == 2 && plain.starts_with("  ")) {
            let name = plain.slice(name_field_start(), name_field_end()).trim();
            if (name != "") {
                names.push(name);
            }
        }
    }
    names
}

test "network_names reads the rows and nothing else" {
    let table = #"
                               Available networks
--------------------------------------------------------------------------------
      Network name                      Security            Signal
--------------------------------------------------------------------------------
  >   Home                              psk                   ****
      Guest of the House                open                  ***
      Network name                      psk                   **
--------------------------------------------------------------------------------
"#;
    assert.equal(network_names(table),
                 ["Home", "Guest of the House", "Network name"])
}

test "network_names is empty when iwd found nothing" {
    let table = #"
                               Available networks
--------------------------------------------------------------------------------
      Network name                      Security            Signal
--------------------------------------------------------------------------------
No networks available
--------------------------------------------------------------------------------
"#;
    assert.equal(network_names(table), [])
}

/// The wireless interfaces this machine has, as the kernel names them.
///
/// `ip` is read rather than `iwctl station list`, because `ip -o` prints one
/// line per interface in a format that has not moved in decades, where the
/// other is a decorated table. Wireless devices are named `wl…` under the
/// naming systemd applies, which is what a live medium boots with.
function wireless_devices(shell: root.common.Shell) -> string[] {
    let devices: string[] = [];
    for (let line in root.common.nonempty_lines(
            shell.capture("ip", ["-o", "link", "show"]).stdout)) {
        let name = (root.common.split_fields(line).at(1) ?? "").replace(":", "");
        if (name.starts_with("wl")) {
            devices.push(name);
        }
    }
    devices
}

/// Whether the scan iwd was asked for has finished.
///
/// iwd is asked, rather than a length of time being waited out, because how
/// long a scan takes is a property of the radio and of the air around it and
/// not a number anyone here could pick. A station that says nothing about
/// scanning has finished as far as this is concerned: the question is whether
/// there is anything left to wait for, and silence is not.
function scan_finished(shell: root.common.Shell, device: string) -> bool {
    let scanning = false;
    for (let line in shell.capture("iwctl", ["station", device, "show"]).stdout.lines()) {
        let plain = without_colour(line);
        if (plain.includes("Scanning") && plain.includes("yes")) {
            scanning = true;
        }
    }
    !scanning
}

test "scan_finished reads what the station says about itself" {
    let scanning = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {},
        replies: { "iwctl station wlan0 show": "  Scanning              yes\n" },
    };
    assert.equal(scan_finished(scanning, "wlan0"), false);

    let settled = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {},
        replies: { "iwctl station wlan0 show": "  State  connected\n  Scanning  no\n" },
    };
    assert.equal(scan_finished(settled, "wlan0"), true)
}

test "a station that says nothing about scanning is not waited for" {
    let quiet = root.common.RecordingShell {
        commands: [], fed: [], streamed: [], exit_codes: {}, replies: {},
    };
    assert.equal(scan_finished(quiet, "wlan0"), true)
}

/// How long to wait for a scan, in seconds. Long enough for a slow radio in a
/// crowded band, short enough that one which never answers does not hold the
/// screen for ever.
function scan_patience() -> int { 20 }

/// Holds while iwd is scanning, so that the list is read when there is
/// something in it. False when patience ran out first, which is the difference
/// between a band with nothing in it and a scan that never came back.
function await_scan(shell: root.common.Shell, device: string) -> bool {
    let waited = 0;
    let finished = scan_finished(shell, device);
    while (!finished && waited < scan_patience()) {
        let _ = baml.sys.sleep(baml.time.Duration.from_seconds(1)) catch (e) {
            baml.errors.Io => null
        };
        waited = waited + 1;
        finished = scan_finished(shell, device);
    }
    finished
}

/// Whether this machine reaches the repository the installation installs from.
///
/// It is the repository that is asked, and not a route or a name server,
/// because reaching it is what the installation actually needs: a machine
/// behind a captive portal has both of those and none of what it is about to
/// download.
function reaches_repository(shell: root.common.Shell) -> bool {
    shell.capture("curl", ["-fsS", "--max-time", "8", "-o", "/dev/null",
                           repository_probe()]).exit_code == 0
}

/// What is asked. The database rather than the bare host, because a name that
/// resolves and a server that answers are different things, and the second is
/// the one that matters.
function repository_probe() -> string {
    "https://packages.oparch.iokode.dev/oparch.db"
}
