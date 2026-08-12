// The parsed shape of a `.dfmap` file. One class per declaration kind; every
// declaration carries the selectors that guard it and the location it came
// from.

/// A `for` (include) or `except` (exclude) condition on one dimension.
class Selector {
    negate: bool,
    dimension: "user" | "host",
    values: string[],
    loc: SourceLoc,

    function label(self) -> string {
        let keyword = if (self.negate) {
            "except"
        } else {
            "for"
        };
        `${keyword} ${self.dimension} ${self.values.join(",")}`
    }
}

enum OperationKind {
    Link,
    Copy,
    Render,
}

/// One `link`, `copy` or `render` rule from a `[dotfiles.<category>]` section.
class Operation {
    kind: OperationKind,
    category: string,
    sources: string[],
    target: string,
    mode: string?,
    root_ownership: bool,
    selectors: Selector[],
    loc: SourceLoc,
}

/// One entry of `[packages]` or `[aur-packages]`.
class PackageDecl {
    name: string,
    aur: bool,
    selectors: Selector[],
    loc: SourceLoc,
}

/// One `key = 'value'` line of a `[values.<category>]` section.
class ValueDef {
    category: string,
    key: string,
    value: string,
    selectors: Selector[],
    loc: SourceLoc,

    function full_name(self) -> string {
        `${self.category}.${self.key}`
    }
}

/// One key line of a `[secrets.<category>]` section. Never holds a value.
class SecretDecl {
    category: string,
    key: string,
    scope: "global" | "user",
    selectors: Selector[],
    loc: SourceLoc,

    function full_name(self) -> string {
        `${self.category}.${self.key}`
    }
}

/// One top-level `include` entry.
class IncludeDecl {
    path: string,
    selectors: Selector[],
    loc: SourceLoc,
}

/// The declared map format revision, as `<major>.<minor>`.
class MapVersion {
    major: int,
    minor: int,

    function label(self) -> string {
        `${self.major}.${self.minor}`
    }
}

/// A single parsed file, before include expansion.
class MapFile {
    path: string,
    version: MapVersion,
    includes: IncludeDecl[],
    packages: PackageDecl[],
    values: ValueDef[],
    secrets: SecretDecl[],
    operations: Operation[],
}

/// The whole include graph, assembled into one logical map.
class MapDocument {
    version: MapVersion,
    files: string[],
    packages: PackageDecl[],
    values: ValueDef[],
    secrets: SecretDecl[],
    operations: Operation[],
}
