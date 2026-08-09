// Reading pacman/pacstrap output. The host streams the bytes; the meaning is
// decided here, so it is testable without running anything.

class Progress {
    current: int,
    total: int,
    action: string,
    package: string,
}

class Downloading {
    file: string,
}

class PhaseMarker {
    name: string,
}

class Unknown {
}

type PacmanEvent = Progress | Downloading | PhaseMarker | Unknown;

function parse_int(text: string) -> int? {
    baml.Int.parse(text) catch (e) {
        baml.errors.ParseError => null
    }
}

/// Turns one line of pacman output into a typed event.
function parse_pacman_line(raw: string) -> PacmanEvent {
    let line = raw.trim();
    //# ":: Retrieving packages..." and friends
    if (line.starts_with("::")) {
        return PhaseMarker { name: line.substring(2, line.length()).trim() };
    }
    //# "downloading linux-6.9.1.arch1-1-x86_64.pkg.tar.zst"
    if (line.starts_with("downloading ")) {
        return Downloading { file: line.substring(12, line.length()).trim() };
    }
    //# "( 12/345) installing linux"
    if (line.starts_with("(")) {
        if let close: int = line.index_of(")") {
            let parts = line.substring(1, close).split("/");
            if (parts.length() == 2) {
                let current = parse_int((parts.at(0) ?? "").trim());
                let total = parse_int((parts.at(1) ?? "").trim());
                if let c: int = current {
                    if let t: int = total {
                        let rest = line.substring(close + 1, line.length()).trim();
                        let words = root.common.split_fields(rest);
                        return Progress {
                            current: c,
                            total: t,
                            action: words.at(0) ?? "",
                            package: words.slice(1, words.length()).join(" "),
                        };
                    }
                }
            }
        }
    }

    Unknown {  }
}

/// Linear estimate of the milliseconds left. `elapsed_ms` is passed in so the
/// function stays pure and the test stays deterministic.
function eta_ms(current: int, total: int, elapsed_ms: int) -> int? {
    if (current <= 0 || total <= 0 || current >= total) {
        return null;
    }
    let per_item = (elapsed_ms * 1.0) / (current * 1.0);
    (per_item * ((total - current) * 1.0)).iround() catch (e) {
        baml.errors.InvalidArgument => null
    }
}

test "parse_pacman_line reads a phase marker" {
    match (parse_pacman_line(":: Retrieving packages...")) {
        let m: PhaseMarker => assert.equal(m.name, "Retrieving packages..."),
        _ => assert.is_true(false),
    }
}

test "parse_pacman_line reads a download" {
    match (parse_pacman_line("downloading linux-6.9.1.arch1-1-x86_64.pkg.tar.zst")) {
        let d: Downloading => assert.equal(d.file, "linux-6.9.1.arch1-1-x86_64.pkg.tar.zst"),
        _ => assert.is_true(false),
    }
}

test "parse_pacman_line reads progress with padding" {
    match (parse_pacman_line("( 12/345) installing linux")) {
        let p: Progress => {
            assert.equal(p.current, 12);
            assert.equal(p.total, 345);
            assert.equal(p.action, "installing");
            assert.equal(p.package, "linux")
        },
        _ => assert.is_true(false),
    }
}

test "parse_pacman_line ignores noise" {
    assert.is_true(parse_pacman_line("warning: /etc/foo installed as /etc/foo.pacnew") is Unknown);
    assert.is_true(parse_pacman_line("") is Unknown)
}

test "eta_ms is linear and undefined at the edges" {
    assert.equal(eta_ms(10, 100, 5000), 45000);
    assert.is_true(eta_ms(0, 100, 5000) == null);
    assert.is_true(eta_ms(100, 100, 5000) == null)
}
