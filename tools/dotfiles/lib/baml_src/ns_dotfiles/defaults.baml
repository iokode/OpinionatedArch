// Where a dotfiles package is looked for when nothing says otherwise, and what
// its map is called inside it.

/// Where the package of an installed machine lives, as
/// `docs/decisions/014-dotfiles.md` decides.
function default_source_root() -> string {
    "/dotfiles"
}

/// What the map is called inside a source. The default map is this file at the
/// top of whatever `--source` is, so pointing the tool at a package somewhere
/// else needs one option rather than two that have to agree.
function map_file_name() -> string {
    "main.dfmap"
}

function default_map_path() -> string {
    path_join(default_source_root(), map_file_name())
}
