// Parser for one `.dfmap` file. Declarative only: there is no construct here
// that can execute a command.

/// The fixed first line that identifies the format by content.
function map_file_header() -> string {
    "oparch dotfiles map"
}

/// Selectors and options collected from the trailing clauses of an entry.
class ClauseSet {
    selectors: Selector[],
    mode: string?,
    scope: string?,
    ownership: string?,
}

class SectionHeader {
    kind: string,
    category: string,
    selectors: Selector[],
    loc: SourceLoc,
}

function new_clause_set() -> ClauseSet {
    ClauseSet { selectors: [], mode: null, scope: null, ownership: null }
}

function make_selector(
    negate: bool,
    dimension: string,
    values: string[],
    loc: SourceLoc,
) -> Selector? {
    match (dimension) {
        "user" => Selector { negate: negate, dimension: "user", values: values, loc: loc },
        "host" => Selector { negate: negate, dimension: "host", values: values, loc: loc },
        _ => null,
    }
}

function is_octal_mode(text: string) -> bool {
    let digits = text.chars();
    let length = digits.length();
    if (length < 3 || length > 4) {
        false
    } else {
        digits
            .every(
                (d) -> {
                    d >= "0" && d <= "7"
                },
            )
    }
}

/// Consumes a comma-separated list of quoted values.
function parse_quoted_list(cursor: Cursor, loc: SourceLoc, diag: Diagnostics) -> string[] {
    let values: string[] = [];
    let more = true;
    while (more) {
        more = false;
        if let token: Token = cursor.advance() {
            if (token.kind == "str") {
                let _ = values.push(token.text);
                if let next: Token = cursor.peek() {
                    if (next.kind == "sym" && next.text == ",") {
                        let _ = cursor.advance();
                        more = true;
                    }
                }
            } else {
                diag.at(loc, `expected a quoted value, found '${token.text}'`);
            }
        } else {
            diag.at(loc, "expected a quoted value, found end of line");
        }
    }
    values
}

/// Parses the trailing `for`, `except` and `with` clauses of an entry.
/// One keyword may introduce several groups, as in `for user 'work' host 'desktop'`.
function parse_clauses(cursor: Cursor, loc: SourceLoc, diag: Diagnostics) -> ClauseSet {
    let clauses = new_clause_set();
    let seen: string[] = [];
    let stop = false;
    while (!cursor.at_end() && !stop) {
        let token = cursor.advance();
        let keyword = token?.text ?? "";
        if (keyword == "for" || keyword == "except") {
            //# selector clause: one or more `user`/`host` groups
            let groups = 0;
            let more = true;
            while (more && !cursor.at_end()) {
                let dimension = cursor.peek()?.text ?? "";
                if (dimension == "user" || dimension == "host") {
                    let _ = cursor.advance();
                    let values = parse_quoted_list(cursor, loc, diag);
                    let key = `${keyword} ${dimension}`;
                    if (seen.includes(key)) {
                        diag.at(loc, `duplicate '${key}' selector on one entry`);
                    } else {
                        let _ = seen.push(key);
                    }
                    if let selector: Selector = make_selector(keyword == "except", dimension, values, loc) {
                        let _ = clauses.selectors.push(selector);
                    }
                    groups = groups + 1;
                } else {
                    more = false;
                }
            }
            if (groups == 0) {
                diag.at(loc, `'${keyword}' must be followed by 'user' or 'host'`);
                stop = true;
            }
        } else if (keyword == "with") {
            //# option clause: one or more `name 'value'` groups
            let groups = 0;
            let more = true;
            while (more && !cursor.at_end()) {
                let name = cursor.peek()?.text ?? "";
                if (name == "mode" || name == "scope" || name == "ownership") {
                    let _ = cursor.advance();
                    let value_token = cursor.advance();
                    let value = value_token?.text ?? "";
                    if ((value_token?.kind ?? "") != "str") {
                        diag.at(loc, `option '${name}' requires a quoted value`);
                    } else if (seen.includes(name)) {
                        diag.at(loc, `duplicate '${name}' option on one entry`);
                    } else {
                        let _ = seen.push(name);
                        if (name == "mode") {
                            clauses.mode = value;
                        }
                        if (name == "scope") {
                            clauses.scope = value;
                        }
                        if (name == "ownership") {
                            clauses.ownership = value;
                        }
                    }
                    groups = groups + 1;
                } else {
                    more = false;
                }
            }
            if (groups == 0) {
                diag.at(loc, "'with' must be followed by 'mode', 'scope' or 'ownership'");
                stop = true;
            }
        } else {
            diag.at(loc, `unexpected '${keyword}'`);
            stop = true;
        }
    }
    clauses
}

function reject_options(
    clauses: ClauseSet,
    context: string,
    loc: SourceLoc,
    diag: Diagnostics,
) -> null {
    if (clauses.mode != null) {
        diag.at(loc, `option 'mode' is invalid for ${context}`);
    }
    if (clauses.scope != null) {
        diag.at(loc, `option 'scope' is invalid for ${context}`);
    }
    if (clauses.ownership != null) {
        diag.at(loc, `option 'ownership' is invalid for ${context}`);
    }
    null
}

function expect_quoted(cursor: Cursor, what: string, loc: SourceLoc, diag: Diagnostics) -> string? {
    if let token: Token = cursor.advance() {
        if (token.kind == "str") {
            token.text
        } else {
            diag.at(loc, `expected a quoted ${what}, found '${token.text}'`);
            null
        }
    } else {
        diag.at(loc, `expected a quoted ${what}, found end of line`);
        null
    }
}

function expect_keyword(
    cursor: Cursor,
    keyword: string,
    loc: SourceLoc,
    diag: Diagnostics,
) -> bool {
    if (cursor.take_word(keyword)) {
        true
    } else {
        diag.at(loc, `expected '${keyword}'`);
        false
    }
}

/// Parses `<major>.<minor>`.
function parse_version_text(text: string, loc: SourceLoc, diag: Diagnostics) -> MapVersion? {
    let parts = text.split(".");
    let major = parts.at(0) ?? "";
    let minor = parts.at(1) ?? "";
    if (
        parts.length() != 2
            || !major.is_ascii_numeric()
            || !minor.is_ascii_numeric()
            || major == ""
            || minor == ""
    ) {
        diag.at(loc, `invalid version '${text}', expected '<major>.<minor>'`);
        null
    } else {
        MapVersion { major: baml.Int.parse(major), minor: baml.Int.parse(minor) }
    }
}

/// Parses `[<kind>[.<category>] <clauses>]`.
function parse_section_header(
    tokens: Token[],
    loc: SourceLoc,
    diag: Diagnostics,
) -> SectionHeader? {
    let last = tokens.at(tokens.length() - 1);
    if ((last?.text ?? "") != "]" || (last?.kind ?? "") != "sym") {
        diag.at(loc, "section header must end with ']'");
        return null;
    }
    let name_token = tokens.at(1);
    if ((name_token?.kind ?? "") != "word") {
        diag.at(loc, "section header must name a section");
        return null;
    }
    let name = name_token?.text ?? "";
    let dot = name.index_of(".");
    let kind = if let index: int = dot {
        name.slice(0, index)
    } else {
        name
    };
    let category = if let index: int = dot {
        name.slice(index + 1, name.length())
    } else {
        ""
    };

    if (
        kind != "packages"
            && kind != "aur-packages"
            && kind != "values"
            && kind != "secrets"
            && kind != "dotfiles"
    ) {
        diag.at(loc, `unknown section '${name}'`);
        return null;
    }
    if ((kind == "packages" || kind == "aur-packages") && category != "") {
        diag.at(loc, `section '${kind}' does not take a category`);
    }
    if (kind != "packages" && kind != "aur-packages" && category == "") {
        diag.at(loc, `section '${kind}' requires a category, as in '${kind}.<category>'`);
        return null;
    }

    let cursor = new_cursor(tokens, 2, tokens.length() - 1);
    let clauses = parse_clauses(cursor, loc, diag);
    reject_options(clauses, "a section header", loc, diag);
    SectionHeader { kind: kind, category: category, selectors: clauses.selectors, loc: loc }
}

function parse_package_entry(
    tokens: Token[],
    aur: bool,
    section: SectionHeader,
    loc: SourceLoc,
    diag: Diagnostics,
) -> PackageDecl? {
    let name_token = tokens.at(0);
    if ((name_token?.kind ?? "") != "word") {
        diag.at(loc, "a package entry must start with a package name");
        return null;
    }
    let cursor = new_cursor(tokens, 1, tokens.length());
    let clauses = parse_clauses(cursor, loc, diag);
    reject_options(clauses, "a package entry", loc, diag);
    PackageDecl {
        name: name_token?.text ?? "",
        aur: aur,
        selectors: section.selectors.concat(clauses.selectors),
        loc: loc,
    }
}

function parse_value_entry(
    tokens: Token[],
    section: SectionHeader,
    loc: SourceLoc,
    diag: Diagnostics,
) -> ValueDef? {
    let key_token = tokens.at(0);
    if ((key_token?.kind ?? "") != "word") {
        diag.at(loc, "a value entry must start with a key");
        return null;
    }
    let equals = tokens.at(1);
    if ((equals?.text ?? "") != "=" || (equals?.kind ?? "") != "sym") {
        diag.at(loc, "a value entry must be '<key> = <value>'");
        return null;
    }
    let cursor = new_cursor(tokens, 2, tokens.length());
    let value = expect_quoted(cursor, "value", loc, diag);
    if (value == null) {
        return null;
    }
    let clauses = parse_clauses(cursor, loc, diag);
    reject_options(clauses, "a value entry", loc, diag);
    ValueDef {
        category: section.category,
        key: key_token?.text ?? "",
        value: value,
        selectors: section.selectors.concat(clauses.selectors),
        loc: loc,
    }
}

function parse_secret_entry(
    tokens: Token[],
    section: SectionHeader,
    loc: SourceLoc,
    diag: Diagnostics,
) -> SecretDecl? {
    let key_token = tokens.at(0);
    if ((key_token?.kind ?? "") != "word") {
        diag.at(loc, "a secret entry must start with a key");
        return null;
    }
    let cursor = new_cursor(tokens, 1, tokens.length());
    let clauses = parse_clauses(cursor, loc, diag);
    if (clauses.mode != null) {
        diag.at(loc, "option 'mode' is invalid for a secret entry");
    }
    if (clauses.ownership != null) {
        diag.at(loc, "option 'ownership' is invalid for a secret entry");
    }
    let scope_text = clauses.scope ?? "global";
    let scope = match (scope_text) {
        "global" => "global",
        "user" => "user",
        _ => null,
    };
    if (scope == null) {
        diag.at(loc, `unknown secret scope '${scope_text}', expected 'global' or 'user'`);
        return null;
    }
    SecretDecl {
        category: section.category,
        key: key_token?.text ?? "",
        scope: if (scope_text == "user") {
            "user"
        } else {
            "global"
        },
        selectors: section.selectors.concat(clauses.selectors),
        loc: loc,
    }
}

function parse_operation_entry(
    tokens: Token[],
    section: SectionHeader,
    loc: SourceLoc,
    diag: Diagnostics,
) -> Operation? {
    let operation = tokens.at(0)?.text ?? "";
    let kind = match (operation) {
        "link" => OperationKind.Link,
        "copy" => OperationKind.Copy,
        "render" => OperationKind.Render,
        _ => null,
    };
    if (kind == null) {
        diag.at(loc, `unknown operation '${operation}', expected 'link', 'copy' or 'render'`);
        return null;
    }

    let cursor = new_cursor(tokens, 1, tokens.length());
    let sources: string[] = [];
    let first = expect_quoted(cursor, "source path", loc, diag);
    if (first == null) {
        return null;
    }
    let _ = sources.push(first);
    //# `render 'a' + 'b'` composes several sources into one output
    while (cursor.take_word("+")) {
        if let next: string = expect_quoted(cursor, "source path", loc, diag) {
            let _ = sources.push(next);
        }
    }
    if (sources.length() > 1 && kind != OperationKind.Render) {
        diag.at(loc, `operation '${operation}' accepts exactly one source`);
    }
    if (!expect_keyword(cursor, "to", loc, diag)) {
        return null;
    }
    let target = expect_quoted(cursor, "target path", loc, diag);
    if (target == null) {
        return null;
    }

    let clauses = parse_clauses(cursor, loc, diag);
    if (clauses.scope != null) {
        diag.at(loc, "option 'scope' is invalid for a dotfile rule");
    }
    if (clauses.mode != null && kind == OperationKind.Link) {
        diag.at(
            loc,
            "option 'mode' is invalid for 'link', because a symlink has no independent mode",
        );
    }
    if let mode: string = clauses.mode {
        if (!is_octal_mode(mode)) {
            diag.at(loc, `invalid mode '${mode}', expected an octal mode such as '0640'`);
        }
    }
    if let ownership: string = clauses.ownership {
        if (ownership != "root") {
            diag.at(loc, `invalid ownership '${ownership}', the only value is 'root'`);
        }
    }

    Operation {
        kind: kind,
        category: section.category,
        sources: sources,
        target: target,
        mode: if (kind == OperationKind.Link) {
            null
        } else {
            clauses.mode
        },
        root_ownership: clauses.ownership == "root",
        selectors: section.selectors.concat(clauses.selectors),
        loc: loc,
    }
}

/// Parses one map file from its text. Returns `null` when the file is not a
/// map at all; entry-level problems are reported through `diag`.
function parse_map_text(text: string, path: string, diag: Diagnostics) -> MapFile? {
    let lines = text.lines();
    if ((lines.at(0) ?? "") != map_file_header()) {
        diag.report(`${path}:1: file does not start with the '${map_file_header()}' header`);
        return null;
    }

    let version: MapVersion? = null;
    let includes: IncludeDecl[] = [];
    let packages: PackageDecl[] = [];
    let values: ValueDef[] = [];
    let secrets: SecretDecl[] = [];
    let operations: Operation[] = [];
    let section: SectionHeader? = null;
    let seen_section = false;

    let index = 1;
    while (index < lines.length()) {
        let loc = SourceLoc { file: path, line: index + 1 };
        let tokens = tokenize_line(lines.at(index) ?? "", loc, diag);
        let head = tokens.at(0);
        if (tokens.length() == 0) {
            //# blank line or a whole-line comment
            index = index;
        } else if ((head?.kind ?? "") == "sym" && (head?.text ?? "") == "[") {
            if (version == null) {
                diag.at(loc, "the 'version' entry must come before the first section");
            }
            seen_section = true;
            section = parse_section_header(tokens, loc, diag);
        } else if ((head?.text ?? "") == "version") {
            if (version != null) {
                diag.at(loc, "duplicate 'version' entry");
            } else if (seen_section) {
                diag.at(loc, "the 'version' entry must come before the first section");
            } else {
                let cursor = new_cursor(tokens, 1, tokens.length());
                if let equals: Token = cursor.advance() {
                    if (equals.kind != "sym" || equals.text != "=") {
                        diag.at(loc, "a version entry must be \"version = '<major>.<minor>'\"");
                    }
                }
                if let text_value: string = expect_quoted(cursor, "version", loc, diag) {
                    version = parse_version_text(text_value, loc, diag);
                }
                if (!cursor.at_end()) {
                    diag.at(loc, "a version entry takes no selectors or options");
                }
            }
        } else if (version == null) {
            diag.at(loc, "the 'version' entry must be the first entry of the file");
        } else if ((head?.text ?? "") == "include") {
            if (seen_section) {
                diag.at(loc, "'include' entries must appear before the first section");
            } else {
                let cursor = new_cursor(tokens, 1, tokens.length());
                if let include_path: string = expect_quoted(cursor, "include path", loc, diag) {
                    let clauses = parse_clauses(cursor, loc, diag);
                    reject_options(clauses, "an include entry", loc, diag);
                    let _ = includes
                        .push(
                            IncludeDecl {
                                path: include_path,
                                selectors: clauses.selectors,
                                loc: loc,
                            },
                        );
                }
            }
        } else if let current: SectionHeader = section {
            //# entry inside a section
            if (current.kind == "packages" || current.kind == "aur-packages") {
                if let entry: PackageDecl = parse_package_entry(tokens, current.kind == "aur-packages", current, loc, diag) {
                    let _ = packages.push(entry);
                }
            } else if (current.kind == "values") {
                if let entry: ValueDef = parse_value_entry(tokens, current, loc, diag) {
                    let _ = values.push(entry);
                }
            } else if (current.kind == "secrets") {
                if let entry: SecretDecl = parse_secret_entry(tokens, current, loc, diag) {
                    let _ = secrets.push(entry);
                }
            } else {
                if let entry: Operation = parse_operation_entry(tokens, current, loc, diag) {
                    let _ = operations.push(entry);
                }
            }
        } else {
            diag.at(loc, "entry outside of a section");
        }
        index = index + 1;
    }

    if let declared: MapVersion = version {
        MapFile {
            path: path,
            version: declared,
            includes: includes,
            packages: packages,
            values: values,
            secrets: secrets,
            operations: operations,
        }
    } else {
        diag.report(`${path}: missing mandatory 'version' entry`);
        null
    }
}
