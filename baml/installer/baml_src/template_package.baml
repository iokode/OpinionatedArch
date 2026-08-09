// Reading a return-message template package, as defined in
// `docs/tools/oparch-return-message-render/001-template-package-format.md`.
//
// Everything here is pure: the manifest arrives as text and the bodies arrive
// as text. Fetching them is the caller's business.

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

/// The revision of the format this installer implements.
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

    let top = as_map(document) ?? empty_json_map();
    if (as_map(document) == null) {
        return PackageParse { package: empty_package(), error: "The manifest must be a mapping." };
    }

    let package = empty_package();

    let version = read_text(top, "version", "version");
    if (version.error != "") {
        return PackageParse { package: package, error: version.error };
    }
    let version_problem = check_version(version.value);
    if (version_problem != "") {
        return PackageParse { package: package, error: version_problem };
    }
    package.version = version.value;

    let name = read_text(top, "name", "name");
    if (name.error != "") {
        return PackageParse { package: package, error: name.error };
    }
    package.name = name.value;

    let notice = read_text(top, "notice", "notice");
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

/// A revision this installer cannot interpret is refused rather than guessed at.
function check_version(version: string) -> string {
    if (version == "") {
        return "version is required.";
    }
    let parts = version.split(".");
    if (parts.length() != 2) {
        return `Invalid version: ${version}`;
    }
    let major = parse_int(parts.at(0) ?? "");
    let minor = parse_int(parts.at(1) ?? "");
    if (major == null || minor == null) {
        return `Invalid version: ${version}`;
    }
    if ((major ?? 0) != supported_major()) {
        return `This package needs format version ${major ?? 0}, which this installer does not implement.`;
    }
    if ((minor ?? 0) > supported_minor()) {
        return `This package needs format version ${version}, and this installer implements up to ${supported_major()}.${supported_minor()}.`;
    }
    ""
}

function read_fields(top: map<string, baml.json.json>, package: TemplatePackage) -> string {
    if (!top.keys().includes("fields")) {
        return "The package declares no field.";
    }
    let entries = as_list(top.get("fields"));
    if (entries == null) {
        return "fields must be a list.";
    }
    let seen: string[] = [];

    for (let entry in entries) {
        let values = as_map(entry) ?? empty_json_map();
        if (as_map(entry) == null) {
            return "Every field must be a mapping.";
        }

        let name = read_text(values, "name", "field name");
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

        let label = read_text(values, "label", `field ${name.value} label`);
        if (label.error != "") {
            return label.error;
        }
        if (label.value == "") {
            return `The field ${name.value} declares no label.`;
        }

        let kind = read_text(values, "kind", `field ${name.value} kind`);
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
    let entries = as_list(top.get("languages"));
    if (entries == null) {
        return "languages must be a list.";
    }
    let seen: string[] = [];

    for (let entry in entries) {
        let values = as_map(entry) ?? empty_json_map();
        if (as_map(entry) == null) {
            return "Every language must be a mapping.";
        }

        let code = read_text(values, "code", "language code");
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

        let name = read_text(values, "name", `language ${code.value} name`);
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
    if (!(name.char_at(0)).is_ascii_lowercase()) {
        return false;
    }
    for (let character in name.chars()) {
        if (!character.is_ascii_lowercase() && !character.is_ascii_numeric() && character != "_") {
            return false;
        }
    }
    true
}

function as_list(value: baml.json.json) -> baml.json.json[]? {
    match (value) {
        let items: baml.json.json[] => items,
        _ => null,
    }
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
            let before = rest.substring(0, open);
            let after = rest.substring(open + 2, rest.length());

            if let close: int = after.index_of("]]") {
                let inside = after.substring(0, close);
                if (inside.includes("[[")) {
                    return BodySplit { pieces: [], error: "An optional region is nested inside another." };
                }
                if (before != "") {
                    pieces.push(BodyPiece { text: before, optional: false });
                }
                pieces.push(BodyPiece { text: inside, optional: true });
                rest = after.substring(close + 2, after.length());
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
            let after = rest.substring(open + 2, rest.length());
            if let close: int = after.index_of("}}") {
                let name = after.substring(0, close).trim();
                if (!names.includes(name)) {
                    names.push(name);
                }
                rest = after.substring(close + 2, after.length());
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

test "a package for a version this installer does not implement is refused" {
    let text = sample_manifest().replace("version: \"1.0\"", "version: \"2.0\"");
    assert.equal(parse_manifest(text).error,
                 "This package needs format version 2, which this installer does not implement.");

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
    let values: map<string, string> = { "phone": "+34 666", "email": "a@b.invalid" };
    assert.equal(render_body("Call {{phone}}[[ or write to {{email}}]].", values),
                 "Call +34 666 or write to a@b.invalid.")
}

test "render_body drops a region when a field is missing, with its words" {
    let values: map<string, string> = { "phone": "+34 666" };
    assert.equal(render_body("Call {{phone}}[[ or write to {{email}}]].", values),
                 "Call +34 666.")
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

/// Joins a directory and a name, whether or not the directory ends in a slash.
function in_directory(directory: string, name: string) -> string {
    if (directory.ends_with("/")) {
        `${directory}${name}`
    } else {
        `${directory}/${name}`
    }
}

/// Reads a package from a directory and validates it completely: the manifest,
/// then every message it declares.
function load_package(files: root.common.Files, directory: string) -> LoadedPackage {
    let manifest_path = in_directory(directory, "manifest.yaml");
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
        let path = in_directory(directory, body_file_name(language.code));
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

/// Where the project's own package lives inside the asset directory.
function default_package_directory(asset_dir: string) -> string {
    in_directory(asset_dir, "return-message")
}

/// Where a fetched package is unpacked. The installer chooses this path; the
/// archive never influences it.
function fetched_package_directory() -> string {
    in_directory(live_staging_dir(), "template-package")
}

/// The package a configuration asks for: its own, or the project's. A package
/// named by URL is fetched first, and read from where it was unpacked.
function resolve_package(shell: root.common.Shell, files: root.common.Files,
                         asset_dir: string, template: string) -> LoadedPackage {
    if (template == "") {
        return load_package(files, default_package_directory(asset_dir));
    }
    if (!is_url(template)) {
        return load_package(files, template);
    }
    let destination = fetched_package_directory();
    let problem = fetch_package(shell, files, template, live_staging_dir(), destination);
    if (problem != "") {
        return LoadedPackage { package: empty_package(), bodies: {}, error: problem };
    }
    load_package(files, destination)
}

/// The package a configuration asks for, by directory, when it is not a URL.
function package_directory(asset_dir: string, template: string) -> string {
    if (template == "") {
        default_package_directory(asset_dir)
    } else {
        template
    }
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

test "package_directory prefers the operator's package over the project's" {
    assert.equal(package_directory("/assets", ""), "/assets/return-message");
    assert.equal(package_directory("/assets", "/home/ivan/andorra"), "/home/ivan/andorra")
}

test "missing_required_field names the first one left empty" {
    let package = parse_manifest(sample_manifest()).package;
    let only_phone: map<string, string> = { "phone": "666" };

    assert.equal(missing_required_field(package, only_phone), "owner_name");
    assert.is_true(missing_required_field(package, { "owner_name": "Ivan" }) == null)
}

// ---------------------------------------------------------------- fetching

/// True when an archive entry would be written outside the directory it is
/// extracted into. Checked before extracting rather than trusted to `tar`.
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

/// The first entry of a listing that would escape, if any.
function escaping_entry(listing: string) -> string? {
    for (let entry in root.common.nonempty_lines(listing)) {
        if (entry_escapes(entry)) {
            return entry;
        }
    }
    null
}

/// A package named by URL is downloaded and unpacked into `destination`, which
/// the installer chooses. Nothing else about the archive decides where its
/// contents land.
function fetch_package(shell: root.common.Shell, files: root.common.Files,
                       url: string, staging: string, destination: string) -> string {
    let archive = in_directory(staging, "template-package.tar");
    files.mkdir(staging);

    let downloaded = shell.capture("curl",
        ["-fL", "--retry", "2", "--connect-timeout", "10", "-o", archive, url]);
    if (downloaded.exit_code != 0) {
        return `Downloading the template package failed with exit code ${downloaded.exit_code}: ${url}`;
    }

    //# look before unpacking: an entry that escapes is refused, not extracted
    let listing = shell.capture("tar", ["-tf", archive]);
    if (listing.exit_code != 0) {
        return `The template package is not a readable archive: ${url}`;
    }
    if let entry: string = escaping_entry(listing.stdout) {
        return `The template package holds an entry that would be written outside it: ${entry}`;
    }

    files.mkdir(destination);
    let extracted = shell.capture("tar", ["-xf", archive, "-C", destination]);
    if (extracted.exit_code != 0) {
        return `Unpacking the template package failed with exit code ${extracted.exit_code}.`;
    }
    ""
}

/// True when a template is named by URL rather than by path.
function is_url(template: string) -> bool {
    template.starts_with("http://") || template.starts_with("https://")
}

test "entry_escapes catches the ways out of a directory" {
    assert.is_true(!entry_escapes("manifest.yaml"));
    assert.is_true(!entry_escapes("nested/es.txt"));
    assert.is_true(entry_escapes("/etc/passwd"));
    assert.is_true(entry_escapes("../outside.txt"));
    assert.is_true(entry_escapes("nested/../../outside.txt"))
}

test "escaping_entry names the first bad entry of a listing" {
    assert.is_true(escaping_entry("manifest.yaml\nes.txt\n") == null);
    assert.equal(escaping_entry("manifest.yaml\n../../etc/passwd\nes.txt\n"), "../../etc/passwd")
}

test "fetch_package refuses an archive before unpacking it" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "tar -tf /tmp/oparch/template-package.tar": "manifest.yaml\n../escape.txt\n" },
    };

    assert.equal(
        fetch_package(shell, root.common.recording_files(),
                      "https://example.invalid/pkg.tar", "/tmp/oparch", "/tmp/oparch/package"),
        "The template package holds an entry that would be written outside it: ../escape.txt");
    //# refused means not extracted
    assert.is_true(!shell.commands.includes(
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/package"))
}

test "fetch_package downloads, inspects and unpacks in that order" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {},
        replies: { "tar -tf /tmp/oparch/template-package.tar": "manifest.yaml\nes.txt\n" },
    };

    assert.equal(
        fetch_package(shell, root.common.recording_files(),
                      "https://example.invalid/pkg.tar", "/tmp/oparch", "/tmp/oparch/package"),
        "");
    assert.equal(shell.commands, [
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/template-package.tar"
            + " https://example.invalid/pkg.tar",
        "tar -tf /tmp/oparch/template-package.tar",
        "tar -xf /tmp/oparch/template-package.tar -C /tmp/oparch/package",
    ])
}

test "fetch_package reports a download that failed" {
    let shell = root.common.RecordingShell {
        commands: [], streamed: [], fed: [], exit_codes: {}, replies: {},
    };
    let _ = shell.exit_codes.set(
        "curl -fL --retry 2 --connect-timeout 10 -o /tmp/oparch/template-package.tar"
            + " https://example.invalid/pkg.tar", 22);

    assert.equal(
        fetch_package(shell, root.common.recording_files(),
                      "https://example.invalid/pkg.tar", "/tmp/oparch", "/tmp/oparch/package"),
        "Downloading the template package failed with exit code 22: https://example.invalid/pkg.tar")
}

test "is_url tells a URL from a path" {
    assert.is_true(is_url("https://example.invalid/pkg.tar"));
    assert.is_true(!is_url("/home/ivan/andorra"));
    assert.is_true(!is_url(""))
}
