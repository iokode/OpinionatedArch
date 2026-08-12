// Include expansion. Includes only assemble one logical map: they carry no
// override or precedence semantics, they only inherit selectors downwards.

/// The map format major this tool implements.
function tool_major() -> int {
    0
}

/// The highest minor this tool implements for `tool_major()`.
function tool_max_minor() -> int {
    1
}

/// A map is accepted only when the tool implements its major and its minor is
/// not higher than the highest minor implemented for that major.
function check_map_version(version: MapVersion, diag: Diagnostics) -> null {
    if (version.major != tool_major()) {
        diag.report(
            `map format major ${version.major} is not implemented by this tool (implemented: ${tool_major()})`,
        );
    } else if (version.minor > tool_max_minor()) {
        diag.report(
            `map format version ${version.label()} is newer than this tool implements (highest: ${tool_major()}.${tool_max_minor()})`,
        );
    }
    null
}

/// Reads and parses one map file.
function load_map_file(path: string, diag: Diagnostics) -> MapFile? {
    if let text: string = read_text_file(path) {
        parse_map_text(text, path, diag)
    } else {
        diag.report(`cannot read map file '${path}'`);
        null
    }
}

/// Merges one parsed file into the assembled document, then expands its
/// includes depth-first. `inherited` are the selectors every entry of this
/// file carries from the include entries that led here.
function merge_map_file(
    file: MapFile,
    inherited: Selector[],
    document: MapDocument,
    source_root: string,
    stack: string[],
    diag: Diagnostics,
) -> null {
    let _ = document.files.push(file.path);

    if (file.version.major != document.version.major) {
        diag.report(
            `${file.path}: declares major ${file.version.major}, but the include graph declares major ${document.version.major}`,
        );
    }
    if (file.version.minor > document.version.minor) {
        //# the assembled map requires the highest minor any file declares
        document.version.minor = file.version.minor;
    }

    for (let entry in file.packages) {
        entry.selectors = inherited.concat(entry.selectors);
        let _ = document.packages.push(entry);
    }
    for (let entry in file.values) {
        entry.selectors = inherited.concat(entry.selectors);
        let _ = document.values.push(entry);
    }
    for (let entry in file.secrets) {
        entry.selectors = inherited.concat(entry.selectors);
        let _ = document.secrets.push(entry);
    }
    for (let entry in file.operations) {
        entry.selectors = inherited.concat(entry.selectors);
        let _ = document.operations.push(entry);
    }
    //# include paths are relative to the file that contains them
    let base = path_dirname(file.path);
    for (let include in file.includes) {
        if (path_is_absolute(include.path)) {
            diag.at(include.loc, `absolute include path '${include.path}' is invalid`);
        } else {
            let resolved = path_normalize(path_join(base, include.path));
            if (!path_within(source_root, resolved)) {
                diag.at(
                    include.loc,
                    `include path '${include.path}' escapes the dotfiles source directory '${source_root}'`,
                );
            } else if (stack.includes(resolved)) {
                diag.at(include.loc, `include cycle: '${resolved}' is already being included`);
            } else if (!file_exists(resolved)) {
                diag.at(include.loc, `included file '${resolved}' does not exist`);
            } else {
                if let included: MapFile = load_map_file(resolved, diag) {
                    merge_map_file(
                        included,
                        inherited.concat(include.selectors),
                        document,
                        source_root,
                        stack.concat([resolved]),
                        diag,
                    );
                }
            }
        }
    }
    null
}

/// Parses the top-level map and expands its complete include graph.
function load_map_document(
    map_path: string,
    source_root: string,
    diag: Diagnostics,
) -> MapDocument? {
    let root_file = load_map_file(map_path, diag);
    if (root_file == null) {
        return null;
    }
    let document = MapDocument {
        version: MapVersion { major: root_file.version.major, minor: root_file.version.minor },
        files: [],
        packages: [],
        values: [],
        secrets: [],
        operations: [],
    };
    merge_map_file(root_file, [], document, source_root, [path_normalize(map_path)], diag);
    check_map_version(document.version, diag);
    document
}
