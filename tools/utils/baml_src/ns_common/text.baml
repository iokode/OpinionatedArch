// Small text helpers used when reading command output.

/// Splits on runs of whitespace, dropping empty fields.
function split_fields(line: string) -> string[] {
    line.split(" ").map((f) -> { f.trim() }).filter((f) -> { f != "" })
}

test "split_fields collapses runs of whitespace" {
    assert.equal(split_fields("/dev/sda    disk"), ["/dev/sda", "disk"]);
    assert.equal(split_fields("  spaced   out  "), ["spaced", "out"]);
    assert.equal(split_fields(""), [])
}

/// The non-empty, trimmed lines of a command's output.
function nonempty_lines(output: string) -> string[] {
    output.lines().map((l) -> { l.trim() }).filter((l) -> { l != "" })
}

test "nonempty_lines drops blanks and trims" {
    assert.equal(nonempty_lines("es\n\n  us  \n"), ["es", "us"]);
    assert.equal(nonempty_lines(""), [])
}
