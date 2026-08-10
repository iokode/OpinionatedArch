// The values that fill a return message, as defined in
// `docs/tools/oparch-return-message-render/002-values-format.md`.
//
// The same shape appears twice: as the `return_message` section of the
// installer's configuration file, and as the whole of
// `/etc/opinionatedarch/return-message.yaml`, which the renderer reads. It is
// read here once, so the two cannot drift. `prefix` is what names the section
// in an error message: `return_message.` inside the installer's file, nothing
// inside the renderer's.
//
// What is not here is where the template package and the theme come from. The
// renderer is handed both as directories and resolves neither, so naming them
// is the caller's business: the installer's section adds those keys, and passes
// them through `extra_keys`.

class ReturnMessageConfig {
    languages: string[],
    /// Values for the fields the template declares. The names are the
    /// template's, so no tool knows them in advance.
    fields: map<string, string>,
    /// Empty when the message carries no logo.
    logo_url: string,
}

/// Values, or the first thing wrong with them.
class ReturnMessageParse {
    message: ReturnMessageConfig,
    error: string,
}

function empty_return_message() -> ReturnMessageConfig {
    ReturnMessageConfig { languages: [], fields: {}, logo_url: "" }
}

function allowed_keys() -> string[] {
    ["languages", "fields", "logo_url"]
}

/// Two lowercase ASCII letters.
function validate_language_code(code: string) -> bool {
    code.length() == 2 && code.is_ascii_lowercase()
}

/// `extra_keys` are keys the caller reads for itself and this format does not
/// define. The installer's section carries the origins of the template package
/// and the theme that way, and they are not refused here as unknown.
function parse_return_message(section: map<string, baml.json.json>, prefix: string,
                              extra_keys: string[]) -> ReturnMessageParse {
    let allowed = allowed_keys();
    for (let key in extra_keys) {
        allowed.push(key);
    }
    if let unknown: string = root.common.unknown_key(section, allowed) {
        return ReturnMessageParse {
            message: empty_return_message(),
            error: `Unknown key in config file: ${prefix}${unknown}`,
        };
    }

    let languages: string[] = if (section.keys().includes("languages")) {
        root.common.text_list(section.get("languages")) ?? root.common.empty_names()
    } else {
        root.common.empty_names()
    };
    for (let code in languages) {
        if (!validate_language_code(code)) {
            return ReturnMessageParse {
                message: empty_return_message(),
                error: `Invalid return-message language code: ${code}`,
            };
        }
    }
    if (languages.length() < 1) {
        return ReturnMessageParse {
            message: empty_return_message(),
            error: `${prefix}languages must name at least one language.`,
        };
    }

    //# the names here belong to the template, so they are not checked against
    //# a list any tool knows; the package is what checks them, in check_values
    let values: map<string, string> = {};
    if (section.keys().includes("fields")) {
        let raw_fields = section.get("fields");
        let declared = root.common.as_map(raw_fields) ?? root.common.empty_json_map();
        if (root.common.as_map(raw_fields) == null) {
            return ReturnMessageParse {
                message: empty_return_message(),
                error: `${prefix}fields must be a mapping.`,
            };
        }
        for (let name in declared.keys()) {
            let value = root.common.read_text(declared, name, `${prefix}fields.${name}`);
            if (value.error != "") {
                return ReturnMessageParse { message: empty_return_message(), error: value.error };
            }
            let _ = values.set(name, value.value);
        }
    }

    let logo = root.common.read_text(section, "logo_url", `${prefix}logo_url`);
    if (logo.error != "") {
        return ReturnMessageParse { message: empty_return_message(), error: logo.error };
    }

    ReturnMessageParse {
        message: ReturnMessageConfig {
            languages: languages,
            fields: values,
            logo_url: logo.value,
        },
        error: "",
    }
}

/// The whole of a values file, for the tool that reads nothing else.
function parse_values_file(text: string) -> ReturnMessageParse {
    let document = baml.yaml.parse(text)
        catch (e) {
            _ => {
                return ReturnMessageParse {
                    message: empty_return_message(),
                    error: `Invalid YAML: ${e.message}`,
                };
            }
        };

    let top = root.common.as_map(document) ?? root.common.empty_json_map();
    if (root.common.as_map(document) == null) {
        return ReturnMessageParse {
            message: empty_return_message(),
            error: "The configuration must be a mapping.",
        };
    }
    parse_return_message(top, "", [])
}

// ------------------------------------------------------------ writing it out

/// A text value as this format writes it. The language has no YAML writer, so
/// the quoting rule of the format is honoured here: every text value is
/// quoted, which is what keeps `+34 666 555 666` the text it was written as
/// instead of the number YAML would otherwise read.
function quote_value(value: string) -> string {
    let escaped = value.replace_all("\\", "\\\\").replace_all("\"", "\\\"").replace_all("\n", "\\n");
    `"${escaped}"`
}

/// Composes a values file from the values themselves, so that a message
/// collected once can be rebuilt later from the file it was written to.
///
/// A key whose value is empty is left out rather than written empty: absence is
/// how this format says "no logo", and a key saying the same thing a second way
/// is a key that can disagree with itself.
function render_values_file(message: ReturnMessageConfig) -> string {
    let out = "languages:" + "\n";
    for (let code in message.languages) {
        out = out + `  - ${quote_value(code)}` + "\n";
    }

    //# the names are the package's, and a map has no order of its own
    let names = message.fields.keys().sort_by_key((name) -> { name });
    if (names.length() == 0) {
        out = out + "fields: {}" + "\n";
    } else {
        out = out + "fields:" + "\n";
        for (let name in names) {
            out = out + `  ${name}: ${quote_value(message.fields.get(name) ?? "")}` + "\n";
        }
    }

    if (message.logo_url != "") {
        out = out + `logo_url: ${quote_value(message.logo_url)}` + "\n";
    }
    out
}

/// What the values file cannot decide on its own, because only the package
/// knows it: which languages exist, and which fields mean something.
function check_values(package: TemplatePackage, message: ReturnMessageConfig, prefix: string) -> string {
    let available = package_language_codes(package);
    for (let code in message.languages) {
        if (!available.includes(code)) {
            return `The template package offers no message in ${code}.`;
        }
    }

    //# a value that is typed and then dropped looks like it was used
    let declared: string[] = [];
    for (let field in package.fields) {
        declared.push(field.name);
    }
    for (let name in message.fields.keys().sort_by_key((k) -> { k })) {
        if (!declared.includes(name)) {
            return `${prefix}fields.${name} is not a field the template package declares.`;
        }
    }

    if let missing: string = missing_required_field(package, message.fields) {
        return `${prefix}fields.${missing} is required by the template package.`;
    }
    ""
}

test "parse_values_file reads a whole values file" {
    let parsed = parse_values_file(
        "languages:\n  - \"ca\"\n  - \"es\"\n"
            + "fields:\n  owner_name: \"Ivan\"\n  phone: \"+34 666 555 666\"\n"
            + "logo_url: \"https://example.invalid/logo.png\"\n");

    assert.equal(parsed.error, "");
    assert.equal(parsed.message.languages, ["ca", "es"]);
    assert.equal(parsed.message.fields.get("phone"), "+34 666 555 666");
    assert.equal(parsed.message.logo_url, "https://example.invalid/logo.png")
}

test "the renderer names a key without a section prefix, the installer with one" {
    let text = "languages:\n  - \"es\"\nfields:\n  phone: +34666\n";
    assert.equal(parse_values_file(text).error,
                 "fields.phone must be quoted: YAML read it as a number, not as text."
                     + " Wrap the value in double quotes.");

    let top = root.common.as_map(baml.yaml.parse(text)) ?? root.common.empty_json_map();
    assert.equal(parse_return_message(top, "return_message.", []).error,
                 "return_message.fields.phone must be quoted: YAML read it as a number, not as text."
                     + " Wrap the value in double quotes.")
}

test "a values file with no language is refused, and how many is the theme's" {
    assert.equal(parse_values_file("fields:\n  owner_name: \"Ivan\"\n").error,
                 "languages must name at least one language.");
    //# five is not refused here; the theme is what says whether it lays out five
    assert.equal(
        parse_values_file("languages:\n  - \"ca\"\n  - \"es\"\n  - \"en\"\n  - \"fr\"\n  - \"de\"\n").error,
        "")
}

test "a key outside the format is refused" {
    assert.equal(parse_values_file("languages:\n  - \"es\"\nwat: \"x\"\n").error,
                 "Unknown key in config file: wat")
}

test "the keys the caller reads for itself are not refused as unknown" {
    let text = "template:\n  origin: default\nlanguages:\n  - \"es\"\nfields: {}\n";
    let top = root.common.as_map(baml.yaml.parse(text)) ?? root.common.empty_json_map();

    //# the renderer's own file has no such key, and refuses it
    assert.equal(parse_values_file(text).error, "Unknown key in config file: template");
    //# the installer's section carries it, and reads it itself
    assert.equal(parse_return_message(top, "return_message.", ["template", "theme"]).error, "")
}

test "render_values_file writes the file the format defines" {
    let message = empty_return_message();
    message.languages = ["ca", "es"];
    let _ = message.fields.set("phone", "+34 666 555 666");
    let _ = message.fields.set("owner_name", "Ivan");
    message.logo_url = "https://example.invalid/logo.png";

    assert.equal(render_values_file(message),
                 "languages:\n  - \"ca\"\n  - \"es\"\n"
                     + "fields:\n  owner_name: \"Ivan\"\n  phone: \"+34 666 555 666\"\n"
                     + "logo_url: \"https://example.invalid/logo.png\"\n")
}

test "render_values_file names no package and no theme, whatever was installed" {
    let message = empty_return_message();
    message.languages = ["es"];
    let _ = message.fields.set("owner_name", "Ivan");

    //# where they came from is the caller's, and the renderer is handed them
    let written = render_values_file(message);
    assert.equal(written, "languages:\n  - \"es\"\nfields:\n  owner_name: \"Ivan\"\n");
    assert.is_true(!written.includes("template:"));
    assert.is_true(!written.includes("theme:"))
}

test "what render_values_file writes is what parse_values_file reads back" {
    let message = empty_return_message();
    message.languages = ["ca", "es"];
    let _ = message.fields.set("owner_name", "Ivan \"the finder\" \\ Montilla");
    let _ = message.fields.set("phone", "+34666555666");
    let _ = message.fields.set("address", "Carrer de la Unió\nAndorra");
    message.logo_url = "https://example.invalid/logo.png";

    let read_back = parse_values_file(render_values_file(message));

    assert.equal(read_back.error, "");
    assert.equal(read_back.message.languages, ["ca", "es"]);
    //# the `+` is still there: it is a quoted value, so YAML reads it as text
    assert.equal(read_back.message.fields.get("phone"), "+34666555666");
    assert.equal(read_back.message.fields.get("owner_name"), "Ivan \"the finder\" \\ Montilla");
    assert.equal(read_back.message.fields.get("address"), "Carrer de la Unió\nAndorra");
    assert.equal(read_back.message.logo_url, message.logo_url)
}

test "an empty field set is written as an empty mapping, not as nothing" {
    let message = empty_return_message();
    message.languages = ["es"];

    assert.equal(render_values_file(message), "languages:\n  - \"es\"\nfields: {}\n");
    assert.equal(parse_values_file(render_values_file(message)).error, "")
}

test "check_values refuses a language the package does not offer" {
    let package = parse_manifest(sample_manifest()).package;
    let message = empty_return_message();
    message.languages = ["de"];
    let _ = message.fields.set("owner_name", "Ivan");

    assert.equal(check_values(package, message, ""),
                 "The template package offers no message in de.")
}

test "check_values refuses a field the package does not declare" {
    let package = parse_manifest(sample_manifest()).package;
    let message = empty_return_message();
    message.languages = ["es"];
    let _ = message.fields.set("owner_name", "Ivan");
    let _ = message.fields.set("fax", "1234");

    assert.equal(check_values(package, message, "return_message."),
                 "return_message.fields.fax is not a field the template package declares.")
}

test "check_values requires what the package marks required" {
    let package = parse_manifest(sample_manifest()).package;
    let message = empty_return_message();
    message.languages = ["es"];
    let _ = message.fields.set("phone", "666");

    assert.equal(check_values(package, message, ""),
                 "fields.owner_name is required by the template package.");

    let _ = message.fields.set("owner_name", "Ivan");
    assert.equal(check_values(package, message, ""), "")
}

/// How many languages may be shown is the theme's, since the theme is what has
/// an arrangement for each number, as decided in
/// `docs/decisions/017-return-message-themes.md`.
function check_language_count(theme: Theme, message: ReturnMessageConfig) -> string {
    if (arrangement_for(theme, message.languages.length()) != null) {
        return "";
    }
    let counts: string[] = [];
    for (let count in accepted_counts(theme)) {
        counts.push(`${count}`);
    }
    let listed = if (counts.length() == 1) {
        counts.join("")
    } else {
        counts.slice(0, counts.length() - 1).join(", ") + " or " + (counts.at(counts.length() - 1) ?? "")
    };
    `The theme lays out ${listed} languages, and ${message.languages.length()} were selected.`
}

test "the theme is what says how many languages may be shown" {
    let theme = parse_theme(sample_theme(), "/theme").theme;
    let message = empty_return_message();

    message.languages = ["es", "ca"];
    assert.equal(check_language_count(theme, message), "");

    message.languages = ["es", "ca", "en"];
    assert.equal(check_language_count(theme, message),
                 "The theme lays out 1, 2 or 4 languages, and 3 were selected.")
}

test "a values file names neither its template nor its theme" {
    assert.equal(
        parse_values_file("theme: \"/theme\"\nlanguages:\n  - \"es\"\nfields: {}\n").error,
        "Unknown key in config file: theme")
}
