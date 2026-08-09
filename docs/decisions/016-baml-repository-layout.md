# BAML Repository Layout

## Context

More than one tool is written in BAML, and they have code in common — running external commands, reading command output, and the test doubles that go with those.

BAML has no dependency mechanism between projects. A project is a `baml.toml` plus a `baml_src/` directory, and it cannot reference another one: `[dependencies]` is answered with `warning: ignoring unrecognized top-level key 'dependencies' in baml.toml`, and an extra sources key with `warning: ignoring unrecognized key 'sources' in [package]`. Sharing therefore has to happen at the filesystem level.

What BAML does have is namespaces: a directory named `ns_<name>/` under `baml_src/` puts its files in namespace `<name>`, reachable from elsewhere in the project as `root.<name>.<symbol>`, with no imports.

## Decision

One BAML project per tool, plus a shared project under `baml/utils/`, whose namespace directories are symlinked into each tool that uses them:

```
baml/
├── utils/                          shared code; not built on its own
│   ├── baml.toml
│   └── baml_src/
│       └── ns_common/              → root.common
└── <tool>/
    ├── baml.toml                   declares this tool's generator
    ├── baml_src/
    │   ├── ns_common -> ../../utils/baml_src/ns_common
    │   └── *.baml                  the tool itself, in the root namespace
    └── host/                       host program, if the tool needs one
```

A tool is added by creating its directory with a `baml.toml`, symlinking the shared namespaces it uses, and referring to their symbols by absolute path: `root.common.Shell`.

## Why

- One project per tool is chosen because each tool ships separately and declares its own generator; if all tools share a project, every generated SDK carries every tool's code and any change to one tool rebuilds the others.
- Shared code lives in `baml/utils/` because it needs exactly one home; if it is copied into each tool, the copies drift.
- The shared code is reached by symlinking its namespace directory because BAML offers no other way to pull sources in from outside a project; if the files are duplicated instead, `utils/` stops being the source of truth it exists to be.
- `baml/utils/` declares no generator because it produces no artifact of its own; it exists to be included and to hold the tests for what it provides.

## Considerations

- Running `baml test` inside a tool project also runs the tests of every namespace symlinked into it. That is wanted: shared code is verified in the context of each tool that depends on it.
- Generated SDKs and BAML caches exclude themselves from version control — the generator writes a `.gitignore` into the SDK directory, and `.baml/` carries its own. Neither needs an entry in the repository's `.gitignore`.
- Git stores the symlink itself, so a clone reproduces the layout with no setup step.
- Do not add a shared namespace to a tool that does not use it. The symlink is what declares the dependency, and it should mean something.

