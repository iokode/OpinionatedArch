// Lexical path helpers. Purely textual: nothing here touches the filesystem or
// resolves symlinks, so boundary checks stay statically describable.

function path_is_absolute(p: string) -> bool {
    p.starts_with("/")
}

/// Joins `rest` onto `base`. An absolute `rest` replaces `base`.
function path_join(base: string, rest: string) -> string {
    if (path_is_absolute(rest)) {
        rest
    } else if (base == "") {
        rest
    } else if (base.ends_with("/")) {
        base + rest
    } else {
        base + "/" + rest
    }
}

/// Collapses `.` and `..` segments textually and drops redundant separators.
/// A leading `/` is preserved; `..` above the root is discarded.
function path_normalize(p: string) -> string {
    let absolute = path_is_absolute(p);
    let out: string[] = [];
    for (let seg in p.split("/")) {
        if (seg == "..") {
            let last = out.at(out.length() - 1);
            if (last != null && last != "..") {
                let _ = out.pop();
            } else if (!absolute) {
                let _ = out.push("..");
            }
        } else if (seg != "" && seg != ".") {
            let _ = out.push(seg);
        }
    }
    let joined = out.join("/");
    if (absolute) {
        "/" + joined
    } else if (joined == "") {
        "."
    } else {
        joined
    }
}

/// The directory part of `p`, normalized.
function path_dirname(p: string) -> string {
    let normalized = path_normalize(p);
    let parts = normalized.split("/");
    let _ = parts.pop();
    let head = parts.join("/");
    if (path_is_absolute(normalized) && head == "") {
        "/"
    } else if (head == "") {
        "."
    } else {
        head
    }
}

/// The final component of `p`, normalized.
function path_basename(p: string) -> string {
    let parts = path_normalize(p).split("/");
    parts.at(parts.length() - 1) ?? ""
}

/// True when `p` is `root` itself or lives underneath it. Both sides are
/// normalized first, so `a/../../b` cannot slip past the check.
function path_within(root: string, p: string) -> bool {
    let normalized_root = path_normalize(root);
    let normalized_path = path_normalize(p);
    if (normalized_path == normalized_root) {
        true
    } else if (normalized_root == "/") {
        path_is_absolute(normalized_path)
    } else {
        normalized_path.starts_with(normalized_root + "/")
    }
}

/// The ancestor directories of `p`, outermost first, excluding `/` itself.
function path_ancestors(p: string) -> string[] {
    let normalized = path_normalize(p);
    let out: string[] = [];
    let current = "";
    for (let seg in normalized.split("/")) {
        if (seg != "") {
            current = current + "/" + seg;
            let _ = out.push(current);
        }
    }
    out
}

test "path helpers" {
    assert.equal(path_normalize("/a/b/../c/./d/"), "/a/c/d");
    assert.equal(path_normalize("a/../../b"), "../b");
    assert.equal(path_normalize("/.."), "/");
    assert.equal(path_join("/dotfiles/hosts", "../common.dfmap"), "/dotfiles/hosts/../common.dfmap");
    assert
        .equal(
            path_normalize(path_join("/dotfiles/hosts", "../common.dfmap")),
            "/dotfiles/common.dfmap",
        );
    assert.equal(path_dirname("/dotfiles/main.dfmap"), "/dotfiles");
    assert.equal(path_dirname("/main.dfmap"), "/");
    assert.equal(path_basename("/dotfiles/hypr/keybindings.lua"), "keybindings.lua");
    assert.is_true(path_within("/dotfiles", "/dotfiles/hypr/a.lua"));
    assert.is_true(!path_within("/dotfiles", "/dotfiles-other/a.lua"));
    assert.is_true(!path_within("/dotfiles", "/dotfiles/../etc/passwd"));
    assert.equal(path_ancestors("/a/b/c"), ["/a", "/a/b", "/a/b/c"])
}
