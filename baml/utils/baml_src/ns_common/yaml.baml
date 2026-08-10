// Reading YAML documents.
//
// Every OpinionatedArch tool that takes a configuration file reads it as YAML
// and has to distinguish "absent" from "present but not what was meant". The
// helpers that do that live here rather than in whichever tool needed them
// first.

/// A scalar as text. Only a YAML string counts: a value YAML read as a number
/// comes back in its canonical form, which is not what was written. `+34600...`
/// would lose its `+`, and `1.10` its trailing zero, without anything failing.
function as_text(value: baml.json.json) -> string? {
    match (value) {
        let s: string => s,
        _ => null,
    }
}

/// A text value read from a mapping. Distinguishes absent from present-but-not
/// text, so a number cannot quietly become an empty string.
class TextRead {
    value: string,
    error: string,
}

/// What YAML made of a value, for an error message. The value itself is never
/// echoed back: what arrives is already the canonical form of whatever YAML
/// decided, so repeating it would suggest the very value that was lost.
function json_kind(value: baml.json.json) -> string {
    match (value) {
        let b: bool => "a boolean",
        let i: int => "a number",
        let f: float => "a number",
        let s: string => "text",
        let items: baml.json.json[] => "a list",
        let entries: map<string, baml.json.json> => "a mapping",
        _ => "nothing",
    }
}

function read_text(entries: map<string, baml.json.json>, key: string, path: string) -> TextRead {
    if (!entries.keys().includes(key)) {
        return TextRead { value: "", error: "" };
    }
    let value = entries.get(key);
    if let text: string = as_text(value) {
        return TextRead { value: text, error: "" };
    }
    TextRead {
        value: "",
        error: `${path} must be quoted: YAML read it as ${json_kind(value)}, not as text.`
            + " Wrap the value in double quotes.",
    }
}

function as_int(value: baml.json.json) -> int? {
    match (value) {
        let i: int => i,
        _ => null,
    }
}

/// A number, whether YAML read it as whole or fractional. `1` and `1.0` are
/// the same quantity, and a format that wants a fraction should accept both.
function as_float(value: baml.json.json) -> float? {
    match (value) {
        let f: float => f,
        let i: int => i * 1.0,
        _ => null,
    }
}

function as_map(value: baml.json.json) -> map<string, baml.json.json>? {
    match (value) {
        let entries: map<string, baml.json.json> => entries,
        _ => null,
    }
}

function as_list(value: baml.json.json) -> baml.json.json[]? {
    match (value) {
        let items: baml.json.json[] => items,
        _ => null,
    }
}

function empty_names() -> string[] {
    let empty: string[] = [];
    empty
}

function empty_json_map() -> map<string, baml.json.json> {
    let empty: map<string, baml.json.json> = {};
    empty
}

/// The first name in `entries` that is not in `allowed`, if any.
function unknown_key(entries: map<string, baml.json.json>, allowed: string[]) -> string? {
    for (let key in entries.keys()) {
        if (!allowed.includes(key)) {
            return key;
        }
    }
    null
}

/// Reads a list of names, refusing anything that is not a scalar.
function text_list(value: baml.json.json) -> string[]? {
    match (value) {
        let items: baml.json.json[] => {
            let names: string[] = [];
            for (let item in items) {
                if let text: string = as_text(item) {
                    names.push(text);
                } else {
                    return null;
                }
            }
            names
        },
        _ => null,
    }
}

/// A number written as text, or null when it is not one.
function parse_int(text: string) -> int? {
    baml.Int.parse(text) catch (e) {
        baml.errors.ParseError => null
    }
}

test "read_text tells absent from present-but-not-text" {
    let entries = baml.yaml.parse("name: \"Ivan\"\nphone: +34666\n");
    let top = as_map(entries) ?? empty_json_map();

    assert.equal(read_text(top, "name", "name").value, "Ivan");
    assert.equal(read_text(top, "missing", "missing").value, "");
    assert.equal(read_text(top, "missing", "missing").error, "");
    assert.is_true(read_text(top, "phone", "phone").error.starts_with("phone must be quoted:"))
}

test "unknown_key names the first key outside the list" {
    let top = as_map(baml.yaml.parse("a: 1\nwat: 2\n")) ?? empty_json_map();

    assert.equal(unknown_key(top, ["a", "wat"]), null);
    assert.equal(unknown_key(top, ["a"]), "wat")
}

test "text_list refuses a list holding something that is not text" {
    let top = as_map(baml.yaml.parse("ok:\n  - \"es\"\n  - \"ca\"\nbad:\n  - 1\n")) ?? empty_json_map();

    assert.equal(text_list(top.get("ok")), ["es", "ca"]);
    assert.equal(text_list(top.get("bad")), null)
}

test "parse_int reads a number and refuses what is not one" {
    assert.equal(parse_int("42"), 42);
    assert.equal(parse_int("4x"), null);
    assert.equal(parse_int(""), null)
}

/// A float as a whole number. BAML's `round` answers with a float, and its
/// text form carries a fractional part `int.parse` will not take, so the two
/// have to be joined by hand.
function round_to_int(value: float) -> int {
    let text = value.round().to_string();
    parse_int((text.split(".").at(0)) ?? "0") ?? 0
}

test "round_to_int rounds to the nearest whole number" {
    assert.equal(round_to_int(79.6), 80);
    assert.equal(round_to_int(79.4), 79);
    assert.equal(round_to_int(0.0), 0)
}
