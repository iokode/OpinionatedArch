// Reading a return-message template package, as defined in
// `docs/tools/oparch-return-message-render/001-template-package-format.md`.
//
// Two tools read a package: the installer, to know which values to ask for,
// and `oparch-return-message-render`, to build the message. They read it with
// this code, not with two copies of it.
//
// Parsing is pure: the manifest arrives as text and the bodies arrive as text.
// Fetching them is the caller's business.

class TemplateField {
    name: string,
    label: string,
    kind: string,
    required: bool,
}

class TemplateLanguage {
    code: string,
    name: string,
}

class TemplatePackage {
    version: string,
    name: string,
    /// Shown on the screen where the fields are asked. Empty when the package
    /// has nothing to warn about.
    notice: string,
    fields: TemplateField[],
    languages: TemplateLanguage[],
}

/// A package, or the first thing wrong with it.
class PackageParse {
    package: TemplatePackage,
    error: string,
}

function empty_package() -> TemplatePackage {
    TemplatePackage { version: "", name: "", notice: "", fields: [], languages: [] }
}

/// The revision of the format this project implements.
function supported_major() -> int {
    1
}

function supported_minor() -> int {
    0
}

function field_kinds() -> string[] {
    ["text", "phone", "email", "address", "url"]
}

// -------------------------------------------------------------- the manifest

function parse_manifest(text: string) -> PackageParse {
    let document = baml.yaml.parse(text)
        catch (e) {
            _ => {
                return PackageParse { package: empty_package(), error: `Invalid YAML: ${e.message}` };
            }
        };

    let top = root.common.as_map(document) ?? root.common.empty_json_map();
    if (root.common.as_map(document) == null) {
        return PackageParse { package: empty_package(), error: "The manifest must be a mapping." };
    }

    let package = empty_package();

    let version = root.common.read_text(top, "version", "version");
    if (version.error != "") {
        return PackageParse { package: package, error: version.error };
    }
    let version_problem = check_version(version.value);
    if (version_problem != "") {
        return PackageParse { package: package, error: version_problem };
    }
    package.version = version.value;

    let name = root.common.read_text(top, "name", "name");
    if (name.error != "") {
        return PackageParse { package: package, error: name.error };
    }
    package.name = name.value;

    let notice = root.common.read_text(top, "notice", "notice");
    if (notice.error != "") {
        return PackageParse { package: package, error: notice.error };
    }
    package.notice = notice.value;

    let fields_problem = read_fields(top, package);
    if (fields_problem != "") {
        return PackageParse { package: package, error: fields_problem };
    }

    let languages_problem = read_languages(top, package);
    if (languages_problem != "") {
        return PackageParse { package: package, error: languages_problem };
    }

    PackageParse { package: package, error: "" }
}

/// A revision this project cannot interpret is refused rather than guessed at.
function check_version(version: string) -> string {
    if (version == "") {
        return "version is required.";
    }
    let parts = version.split(".");
    if (parts.length() != 2) {
        return `Invalid version: ${version}`;
    }
    let major = root.common.parse_int(parts.at(0) ?? "");
    let minor = root.common.parse_int(parts.at(1) ?? "");
    if (major == null || minor == null) {
        return `Invalid version: ${version}`;
    }
    if ((major ?? 0) != supported_major()) {
        return `This package needs format version ${major ?? 0}, which is not implemented here.`;
    }
    if ((minor ?? 0) > supported_minor()) {
        return `This package needs format version ${version}, and what is implemented here is up to`
            + ` ${supported_major()}.${supported_minor()}.`;
    }
    ""
}

function read_fields(top: map<string, baml.json.json>, package: TemplatePackage) -> string {
    if (!top.keys().includes("fields")) {
        return "The package declares no field.";
    }
    let entries = root.common.as_list(top.get("fields"));
    if (entries == null) {
        return "fields must be a list.";
    }
    let seen: string[] = [];

    for (let entry in entries) {
        let values = root.common.as_map(entry) ?? root.common.empty_json_map();
        if (root.common.as_map(entry) == null) {
            return "Every field must be a mapping.";
        }

        let name = root.common.read_text(values, "name", "field name");
        if (name.error != "") {
            return name.error;
        }
        if (!validate_field_name(name.value)) {
            return `Invalid field name: ${name.value}`;
        }
        if (seen.includes(name.value)) {
            return `Two fields share the name ${name.value}.`;
        }
        seen.push(name.value);

        let label = root.common.read_text(values, "label", `field ${name.value} label`);
        if (label.error != "") {
            return label.error;
        }
        if (label.value == "") {
            return `The field ${name.value} declares no label.`;
        }

        let kind = root.common.read_text(values, "kind", `field ${name.value} kind`);
        if (kind.error != "") {
            return kind.error;
        }
        let resolved_kind = if (kind.value == "") { "text" } else { kind.value };
        if (!field_kinds().includes(resolved_kind)) {
            return `Invalid kind for the field ${name.value}: ${resolved_kind}`;
        }

        //# a field is required unless it says otherwise
        let required = if (values.keys().includes("required")) {
            match (values.get("required")) {
                let flag: bool => flag,
                _ => true,
            }
        } else {
            true
        };

        package.fields.push(TemplateField {
            name: name.value,
            label: label.value,
            kind: resolved_kind,
            required: required,
        });
    }

    if (package.fields.length() == 0) {
        return "The package declares no field.";
    }
    ""
}

function read_languages(top: map<string, baml.json.json>, package: TemplatePackage) -> string {
    if (!top.keys().includes("languages")) {
        return "The package declares no language.";
    }
    let entries = root.common.as_list(top.get("languages"));
    if (entries == null) {
        return "languages must be a list.";
    }
    let seen: string[] = [];

    for (let entry in entries) {
        let values = root.common.as_map(entry) ?? root.common.empty_json_map();
        if (root.common.as_map(entry) == null) {
            return "Every language must be a mapping.";
        }

        let code = root.common.read_text(values, "code", "language code");
        if (code.error != "") {
            return code.error;
        }
        if (!validate_language_code(code.value)) {
            return `Invalid language code: ${code.value}`;
        }
        if (seen.includes(code.value)) {
            return `Two languages share the code ${code.value}.`;
        }
        seen.push(code.value);

        let name = root.common.read_text(values, "name", `language ${code.value} name`);
        if (name.error != "") {
            return name.error;
        }
        if (name.value == "") {
            return `The language ${code.value} declares no name.`;
        }

        package.languages.push(TemplateLanguage { code: code.value, name: name.value });
    }

    if (package.languages.length() == 0) {
        return "The package declares no language.";
    }
    ""
}

/// Lowercase letters, digits and `_`, starting with a letter.
function validate_field_name(name: string) -> bool {
    if (name.length() == 0) {
        return false;
    }
    if (!(name.at(0) ?? "").is_ascii_lowercase()) {
        return false;
    }
    for (let character in name.chars()) {
        if (!character.is_ascii_lowercase() && !character.is_ascii_numeric() && character != "_") {
            return false;
        }
    }
    true
}

/// The file holding the message for a language.
function body_file_name(code: string) -> string {
    `${code}.txt`
}

// ------------------------------------------------------------- the rendering

/// A body split into the pieces the renderer walks: plain text and optional
/// regions, in the order they appear.
class BodyPiece {
    /// Text of the piece, still holding its `{{field}}` references.
    text: string,
    /// True when the piece is a `[[...]]` region, dropped if a field is empty.
    optional: bool,
}

class BodySplit {
    pieces: BodyPiece[],
    error: string,
}

/// Splits a body on its optional regions. Regions do not nest, and one left
/// open is an error rather than text.
function split_body(body: string) -> BodySplit {
    let pieces: BodyPiece[] = [];
    let rest = body;

    while (true) {
        if let open: int = rest.index_of("[[") {
            let before = rest.slice(0, open);
            let after = rest.slice(open + 2, rest.length());

            if let close: int = after.index_of("]]") {
                let inside = after.slice(0, close);
                if (inside.includes("[[")) {
                    return BodySplit { pieces: [], error: "An optional region is nested inside another." };
                }
                if (before != "") {
                    pieces.push(BodyPiece { text: before, optional: false });
                }
                pieces.push(BodyPiece { text: inside, optional: true });
                rest = after.slice(close + 2, after.length());
            } else {
                return BodySplit { pieces: [], error: "An optional region is opened and never closed." };
            }
        } else {
            if (rest.includes("]]")) {
                return BodySplit { pieces: [], error: "An optional region is closed but never opened." };
            }
            if (rest != "") {
                pieces.push(BodyPiece { text: rest, optional: false });
            }
            return BodySplit { pieces: pieces, error: "" };
        }
    }
    BodySplit { pieces: pieces, error: "" }
}

/// The field names a piece of text refers to.
function referenced_fields(text: string) -> string[] {
    let names: string[] = [];
    let rest = text;

    while (true) {
        if let open: int = rest.index_of("{{") {
            let after = rest.slice(open + 2, rest.length());
            if let close: int = after.index_of("}}") {
                let name = after.slice(0, close).trim();
                if (!names.includes(name)) {
                    names.push(name);
                }
                rest = after.slice(close + 2, after.length());
            } else {
                return names;
            }
        } else {
            return names;
        }
    }
    names
}

/// Replaces every reference in a piece of text with the value given for it.
function substitute(text: string, values: map<string, string>) -> string {
    let out = text;
    for (let name in referenced_fields(text)) {
        out = out.replace_all(`{{${name}}}`, values.get(name) ?? "");
    }
    out
}

/// Builds the message in one language. A region whose fields are not all
/// answered disappears with the words around them.
function render_body(body: string, values: map<string, string>) -> string {
    let split = split_body(body);
    if (split.error != "") {
        return "";
    }
    let out = "";
    for (let piece in split.pieces) {
        if (piece.optional) {
            let complete = true;
            for (let name in referenced_fields(piece.text)) {
                if ((values.get(name) ?? "") == "") {
                    complete = false;
                }
            }
            if (complete) {
                out = out + substitute(piece.text, values);
            }
        } else {
            out = out + substitute(piece.text, values);
        }
    }
    out
}

/// Checks a body against the package that declares its fields.
function check_body(package: TemplatePackage, code: string, body: string) -> string {
    let split = split_body(body);
    if (split.error != "") {
        return `${code}.txt: ${split.error}`;
    }
    let declared: string[] = [];
    for (let field in package.fields) {
        declared.push(field.name);
    }
    for (let piece in split.pieces) {
        for (let name in referenced_fields(piece.text)) {
            if (!declared.includes(name)) {
                return `${code}.txt refers to a field the manifest does not declare: ${name}`;
            }
        }
    }
    ""
}

// -------------------------------------------------------------------- tests

function sample_manifest() -> string {
    "version: \"1.0\"\n"
        + "name: \"Default OpinionatedArch message\"\n"
        + "notice: \"Every contact field is optional.\"\n"
        + "fields:\n"
        + "  - name: \"owner_name\"\n    label: \"Owner name\"\n    required: true\n"
        + "  - name: \"phone\"\n    label: \"Phone number\"\n    kind: \"phone\"\n    required: false\n"
        + "languages:\n"
        + "  - code: \"es\"\n    name: \"Español\"\n"
        + "  - code: \"ca\"\n    name: \"Català\"\n"
}

test "parse_manifest reads a package" {
    let parsed = parse_manifest(sample_manifest());

    assert.equal(parsed.error, "");
    assert.equal(parsed.package.name, "Default OpinionatedArch message");
    assert.equal(parsed.package.notice, "Every contact field is optional.");
    assert.equal(parsed.package.fields.length(), 2);
    assert.equal((parsed.package.fields.at(1))?.label, "Phone number");
    assert.equal((parsed.package.fields.at(1))?.kind, "phone");
    assert.is_true(!((parsed.package.fields.at(1))?.required ?? true));
    assert.equal((parsed.package.languages.at(0))?.name, "Español")
}

test "a field is required and text unless it says otherwise" {
    let parsed = parse_manifest(sample_manifest());
    assert.is_true((parsed.package.fields.at(0))?.required ?? false);
    assert.equal((parsed.package.fields.at(0))?.kind, "text")
}

test "a package for a version that is not implemented is refused" {
    let text = sample_manifest().replace("version: \"1.0\"", "version: \"2.0\"");
    assert.equal(parse_manifest(text).error,
                 "This package needs format version 2, which is not implemented here.");

    let newer = sample_manifest().replace("version: \"1.0\"", "version: \"1.7\"");
    assert.is_true(parse_manifest(newer).error.starts_with("This package needs format version 1.7"))
}

test "a manifest is refused when it is malformed" {
    assert.equal(parse_manifest(sample_manifest().replace("kind: \"phone\"", "kind: \"colour\"")).error,
                 "Invalid kind for the field phone: colour");
    assert.equal(parse_manifest(sample_manifest().replace("name: \"phone\"", "name: \"owner_name\"")).error,
                 "Two fields share the name owner_name.");
    assert.equal(parse_manifest("version: \"1.0\"\nname: \"x\"\nlanguages:\n  - code: \"es\"\n    name: \"E\"\n").error,
                 "The package declares no field.")
}

test "split_body separates plain text from optional regions" {
    let split = split_body("call {{phone}}[[ or write to {{email}}]] please");

    assert.equal(split.error, "");
    assert.equal(split.pieces.length(), 3);
    assert.is_true(!((split.pieces.at(0))?.optional ?? true));
    assert.is_true((split.pieces.at(1))?.optional ?? false);
    assert.equal((split.pieces.at(1))?.text, " or write to {{email}}")
}

test "an unbalanced region is an error, not text" {
    assert.equal(split_body("call {{phone}}[[ or write").error,
                 "An optional region is opened and never closed.");
    assert.equal(split_body("call {{phone}} or write]]").error,
                 "An optional region is closed but never opened.");
    assert.equal(split_body("a [[b [[c]] d]]").error,
                 "An optional region is nested inside another.")
}

test "render_body keeps a region when its fields are answered" {
    let values: map<string, string> = { "phone": "+376 000 000", "email": "a@b.invalid" };
    assert.equal(render_body("Call {{phone}}[[ or write to {{email}}]].", values),
                 "Call +376 000 000 or write to a@b.invalid.")
}

test "render_body drops a region when a field is missing, with its words" {
    let values: map<string, string> = { "phone": "+376 000 000" };
    assert.equal(render_body("Call {{phone}}[[ or write to {{email}}]].", values),
                 "Call +376 000 000.")
}

test "render_body drops each unanswered channel on its own" {
    let body = "If you find it:[[\ncall {{phone}}]][[\nwrite to {{email}}]][[\nreturn it to {{address}}]]\n";
    let only_address: map<string, string> = { "address": "Carrer de la Unió" };

    assert.equal(render_body(body, only_address), "If you find it:\nreturn it to Carrer de la Unió\n");

    let all: map<string, string> = {
        "phone": "666", "email": "a@b.invalid", "address": "Carrer de la Unió",
    };
    assert.equal(render_body(body, all),
                 "If you find it:\ncall 666\nwrite to a@b.invalid\nreturn it to Carrer de la Unió\n")
}

test "check_body refuses a reference the manifest does not declare" {
    let package = parse_manifest(sample_manifest()).package;

    assert.equal(check_body(package, "es", "Hola {{owner_name}}, {{phone}}"), "");
    assert.equal(check_body(package, "es", "Hola {{owner_name}}, {{fax}}"),
                 "es.txt refers to a field the manifest does not declare: fax");
    assert.equal(check_body(package, "ca", "Hola {{owner_name}}[["),
                 "ca.txt: An optional region is opened and never closed.")
}

// ------------------------------------------------------------- loading a package

class LoadedPackage {
    package: TemplatePackage,
    /// The message of each language, by code.
    bodies: map<string, string>,
    error: string,
}

/// Reads a package from a directory and validates it completely: the manifest,
/// then every message it declares.
function load_package(files: root.common.Files, directory: string) -> LoadedPackage {
    let manifest_path = root.common.in_directory(directory, "manifest.yaml");
    let manifest_text = files.read(manifest_path);
    if (manifest_text == null) {
        return LoadedPackage {
            package: empty_package(),
            bodies: {},
            error: `The template package has no manifest.yaml: ${manifest_path}`,
        };
    }

    let parsed = parse_manifest(manifest_text);
    if (parsed.error != "") {
        return LoadedPackage { package: parsed.package, bodies: {}, error: parsed.error };
    }

    let bodies: map<string, string> = {};
    for (let language in parsed.package.languages) {
        let path = root.common.in_directory(directory, body_file_name(language.code));
        let body = files.read(path);
        if (body == null) {
            return LoadedPackage {
                package: parsed.package,
                bodies: bodies,
                error: `The template package has no message for ${language.code}: ${path}`,
            };
        }
        let problem = check_body(parsed.package, language.code, body);
        if (problem != "") {
            return LoadedPackage { package: parsed.package, bodies: bodies, error: problem };
        }
        let _ = bodies.set(language.code, body);
    }

    LoadedPackage { package: parsed.package, bodies: bodies, error: "" }
}

/// True when a path would land outside the directory it belongs to. A theme
/// names its own font and image files this way, and whoever unpacks an archive
/// checks its entries the same way, so the rule is written once.
function entry_escapes(entry: string) -> bool {
    if (entry.starts_with("/")) {
        return true;
    }
    for (let part in entry.split("/")) {
        if (part == "..") {
            return true;
        }
    }
    false
}

test "entry_escapes catches the ways out of a directory" {
    assert.is_true(!entry_escapes("manifest.yaml"));
    assert.is_true(!entry_escapes("nested/es.txt"));
    assert.is_true(entry_escapes("/etc/passwd"));
    assert.is_true(entry_escapes("../outside.txt"));
    assert.is_true(entry_escapes("nested/../../outside.txt"))
}

/// Where the project's own package lives inside the asset directory.
function default_package_directory(asset_dir: string) -> string {
    root.common.in_directory(asset_dir, "return-message")
}

/// The codes a package offers, in the order it declares them.
function package_language_codes(package: TemplatePackage) -> string[] {
    let codes: string[] = [];
    for (let language in package.languages) {
        codes.push(language.code);
    }
    codes
}

/// The names shown to the operator when choosing languages, in the same order.
function package_language_labels(package: TemplatePackage) -> string[] {
    let labels: string[] = [];
    for (let language in package.languages) {
        labels.push(`${language.name} (${language.code})`);
    }
    labels
}

/// The language's own name, as the package writes it.
function language_name(package: TemplatePackage, code: string) -> string {
    for (let language in package.languages) {
        if (language.code == code) {
            return language.name;
        }
    }
    ""
}

/// The first required field left without a value, if any.
function missing_required_field(package: TemplatePackage, values: map<string, string>) -> string? {
    for (let field in package.fields) {
        if (field.required && (values.get(field.name) ?? "") == "") {
            return field.name;
        }
    }
    null
}

test "load_package reads a manifest and every message it declares" {
    let files = root.common.recording_files();
    files.write("/pkg/manifest.yaml", sample_manifest());
    files.write("/pkg/es.txt", "Hola {{owner_name}}[[, {{phone}}]]");
    files.write("/pkg/ca.txt", "Hola {{owner_name}}");

    let loaded = load_package(files, "/pkg");

    assert.equal(loaded.error, "");
    assert.equal(loaded.package.name, "Default OpinionatedArch message");
    assert.equal(loaded.bodies.get("es"), "Hola {{owner_name}}[[, {{phone}}]]")
}

test "load_package reports a message file that is not there" {
    let files = root.common.recording_files();
    files.write("/pkg/manifest.yaml", sample_manifest());
    files.write("/pkg/es.txt", "Hola {{owner_name}}");

    assert.equal(load_package(files, "/pkg").error,
                 "The template package has no message for ca: /pkg/ca.txt")
}

test "load_package reports a manifest that is not there" {
    assert.equal(load_package(root.common.recording_files(), "/nowhere").error,
                 "The template package has no manifest.yaml: /nowhere/manifest.yaml")
}

test "load_package refuses a message referring to an undeclared field" {
    let files = root.common.recording_files();
    files.write("/pkg/manifest.yaml", sample_manifest());
    files.write("/pkg/es.txt", "Hola {{fax}}");
    files.write("/pkg/ca.txt", "Hola {{owner_name}}");

    assert.equal(load_package(files, "/pkg").error,
                 "es.txt refers to a field the manifest does not declare: fax")
}

test "the project's own package lives beside the other assets" {
    assert.equal(default_package_directory("/assets"), "/assets/return-message")
}

test "language_name answers with the name the package gave the code" {
    let package = parse_manifest(sample_manifest()).package;
    assert.equal(language_name(package, "ca"), "Català");
    assert.equal(language_name(package, "de"), "")
}

test "missing_required_field names the first one left empty" {
    let package = parse_manifest(sample_manifest()).package;
    let only_phone: map<string, string> = { "phone": "666" };

    assert.equal(missing_required_field(package, only_phone), "owner_name");
    assert.is_true(missing_required_field(package, { "owner_name": "Ivan" }) == null)
}

