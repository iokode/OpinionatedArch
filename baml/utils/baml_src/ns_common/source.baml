// Where content that is not a value comes from.
//
// Some inputs are not answers but content held elsewhere: a package of files,
// or a single file. What they have in common is that the place they come from
// has a kind — a directory, an archive, a repository — and that the kind is
// answered rather than guessed, because a repository and an archive are both
// URLs. See `docs/decisions/018-installer-input-sources.md`.
//
// This is the shape alone. Bringing the content here belongs to whoever asks
// for it: nothing in this file reaches the network or the filesystem.

class Source {
    /// One of `package_origins()` or `file_origins()`, according to what is
    /// being asked for.
    origin: string,
    /// Empty only when the origin needs none, which is `default`.
    location: string,
}

/// A set of files: the dotfiles package, a template package, a theme.
///
/// `local` covers a directory and a `.tar` alike, because the operator picks
/// one entry out of one list and which of the two it is, is a fact of the
/// filesystem rather than of the text.
function package_origins() -> string[] {
    ["default", "local", "tar", "git"]
}

/// The same, without the project's own, for a package the project does not
/// ship: there is no default dotfiles package to fall back to.
function supplied_package_origins() -> string[] {
    ["local", "tar", "git"]
}

/// A single file: the logo. A repository or an archive for one file would be a
/// container around something that needs none.
function file_origins() -> string[] {
    ["url", "local"]
}

/// The project's own, which is the only origin that names no location.
function default_source() -> Source {
    Source { origin: "default", location: "" }
}

function source_at(origin: string, location: string) -> Source {
    Source { origin: origin, location: location }
}

/// True when the content is the project's own and there is nothing to bring.
function is_default_source(source: Source) -> bool {
    source.origin == "default"
}

/// What is wrong with a source, or "" when it can be acted on. `path` is what
/// names it in the message.
function source_problem(source: Source, allowed: string[], path: string) -> string {
    if (!allowed.includes(source.origin)) {
        return `${path}.origin must be one of ${allowed.join(", ")}: ${source.origin}`;
    }
    if (source.origin == "default") {
        if (source.location != "") {
            return `${path}.location is not read when the origin is default.`;
        }
        return "";
    }
    if (source.location == "") {
        return `${path}.location is required when the origin is ${source.origin}.`;
    }
    ""
}

// ------------------------------------------------------------------- as YAML

class SourceRead {
    source: Source,
    error: string,
}

/// Reads a source from the mapping under `key`, when it is there. A key that is
/// absent leaves `present` false, so a caller can tell "no logo" from "a logo
/// described wrongly".
class OptionalSourceRead {
    source: Source,
    present: bool,
    error: string,
}

function source_keys() -> string[] {
    ["origin", "location"]
}

function read_source(entries: map<string, baml.json.json>, key: string, allowed: string[],
                     path: string) -> OptionalSourceRead {
    let absent = OptionalSourceRead { source: default_source(), present: false, error: "" };
    if (!entries.keys().includes(key)) {
        return absent;
    }

    let raw = entries.get(key);
    let fields = as_map(raw) ?? empty_json_map();
    if (as_map(raw) == null) {
        return OptionalSourceRead {
            source: default_source(), present: true, error: `${path} must be a mapping.`,
        };
    }
    if let unknown: string = unknown_key(fields, source_keys()) {
        return OptionalSourceRead {
            source: default_source(),
            present: true,
            error: `Unknown key in config file: ${path}.${unknown}`,
        };
    }

    let origin = read_text(fields, "origin", `${path}.origin`);
    if (origin.error != "") {
        return OptionalSourceRead { source: default_source(), present: true, error: origin.error };
    }
    let location = read_text(fields, "location", `${path}.location`);
    if (location.error != "") {
        return OptionalSourceRead { source: default_source(), present: true, error: location.error };
    }

    let source = source_at(origin.value, location.value);
    OptionalSourceRead {
        source: source, present: true, error: source_problem(source, allowed, path),
    }
}

/// A source written back out, under `key`, indented by `indent` spaces. Text is
/// quoted for the reason the formats give: a value YAML would read as anything
/// but text comes back as something else.
function render_source(key: string, source: Source, indent: string) -> string {
    let pad = `${indent}  `;
    let out = `${indent}${key}:` + "\n" + `${pad}origin: "${source.origin}"` + "\n";
    if (source.location == "") {
        return out;
    }
    let escaped = source.location.replace_all("\\", "\\\\").replace_all("\"", "\\\"");
    out + `${pad}location: "${escaped}"` + "\n"
}

// -------------------------------------------------------------------- tests

test "a package may come from four places, a file from two" {
    assert.equal(package_origins(), ["default", "local", "tar", "git"]);
    assert.equal(file_origins(), ["url", "local"])
}

test "a package the project does not ship is offered the same places but its own" {
    assert.equal(supplied_package_origins(), ["local", "tar", "git"]);
    for (let origin in supplied_package_origins()) {
        assert.is_true(package_origins().includes(origin));
    }
    assert.is_true(!supplied_package_origins().includes("default"))
}

test "an origin outside the list is refused, and named" {
    assert.equal(source_problem(source_at("ftp", "x"), package_origins(), "dotfiles"),
                 "dotfiles.origin must be one of default, local, tar, git: ftp");
    //# a package origin is not a file origin, and the message says which list
    assert.equal(source_problem(source_at("git", "x"), file_origins(), "return_message.logo"),
                 "return_message.logo.origin must be one of url, local: git")
}

test "every origin but the default one needs a location" {
    assert.equal(source_problem(default_source(), package_origins(), "dotfiles"), "");
    assert.equal(source_problem(source_at("git", ""), package_origins(), "dotfiles"),
                 "dotfiles.location is required when the origin is git.");
    assert.equal(source_problem(source_at("local", "/media/pen"), package_origins(), "dotfiles"), "")
}

test "the default origin reads no location, rather than ignoring one" {
    assert.equal(source_problem(source_at("default", "/somewhere"), package_origins(), "theme"),
                 "theme.location is not read when the origin is default.")
}

test "read_source tells an absent source from one described wrongly" {
    let top = as_map(baml.yaml.parse(
        "dotfiles:\n  origin: git\n  location: \"https://example.invalid/d.git\"\n"
            + "theme:\n  origin: nowhere\n")) ?? empty_json_map();

    let absent = read_source(top, "logo", file_origins(), "logo");
    assert.is_true(!absent.present);
    assert.equal(absent.error, "");

    let dotfiles = read_source(top, "dotfiles", package_origins(), "dotfiles");
    assert.is_true(dotfiles.present);
    assert.equal(dotfiles.error, "");
    assert.equal(dotfiles.source.origin, "git");
    assert.equal(dotfiles.source.location, "https://example.invalid/d.git");

    let theme = read_source(top, "theme", package_origins(), "theme");
    assert.is_true(theme.present);
    assert.equal(theme.error, "theme.origin must be one of default, local, tar, git: nowhere")
}

test "read_source refuses a key the shape does not have" {
    let top = as_map(baml.yaml.parse("dotfiles:\n  origin: git\n  url: \"x\"\n"))
        ?? empty_json_map();

    assert.equal(read_source(top, "dotfiles", package_origins(), "dotfiles").error,
                 "Unknown key in config file: dotfiles.url")
}

test "read_source refuses a location YAML did not read as text" {
    let top = as_map(baml.yaml.parse("logo:\n  origin: url\n  location: 42\n")) ?? empty_json_map();

    assert.is_true(read_source(top, "logo", file_origins(), "logo").error
        .starts_with("logo.location must be quoted:"))
}

test "what render_source writes is what read_source reads back" {
    let source = source_at("local", "/media/pen/andorra.tar");
    let written = render_source("template", source, "  ");

    assert.equal(written,
                 "  template:\n    origin: \"local\"\n    location: \"/media/pen/andorra.tar\"\n");

    let top = as_map(baml.yaml.parse(`return_message:` + "\n" + written)) ?? empty_json_map();
    let section = as_map(top.get("return_message")) ?? empty_json_map();
    let read_back = read_source(section, "template", package_origins(), "return_message.template");

    assert.equal(read_back.error, "");
    assert.equal(read_back.source.origin, "local");
    assert.equal(read_back.source.location, "/media/pen/andorra.tar")
}

test "the default source writes no location, having none" {
    assert.equal(render_source("theme", default_source(), ""), "theme:\n  origin: \"default\"\n")
}
