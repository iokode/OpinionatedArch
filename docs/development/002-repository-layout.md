# Repository Layout

Where the sources live, where the tests live, why the two answers are not the same, and where what is neither of them goes.

The repository holds the source of every tool under `src/`, the end-to-end harness under `tests/`, the assets the tools ship or read under `assets/`, the packages the project publishes and what it takes to sign them under `packages/`, the profile the installation image is built from under `archiso/`, the workflows that build, publish and deploy all of it under `.github/`, what the project runs at the edge of its own domain under `.cloudflare/`, and the documentation under `docs/`. Those are the directories, and there is no other. Beside them sits `install.sh`, the other way an installation is started, which belongs at the top level rather than inside any of them.

More than one tool is written in BAML, and they have code in common — running external commands, reading command output, and the test doubles that go with those.

BAML has no dependency mechanism between projects. A project is a `baml.toml` plus a `baml_src/` directory, and it cannot reference another one: `[dependencies]` is answered with `warning: ignoring unrecognized top-level key 'dependencies' in baml.toml`, and an extra sources key with `warning: ignoring unrecognized key 'sources' in [package]`. Sharing therefore has to happen at the filesystem level.

What BAML does have is namespaces: a directory named `ns_<name>/` under `baml_src/` puts its files in namespace `<name>`, reachable from elsewhere in the project as `root.<name>.<symbol>`, with no imports.

## One project per tool, sharing by symlinked namespace

One BAML project per tool under `src/`, plus a project of generic code under `src/utils/`. A namespace directory is symlinked into every tool that uses it, whether it belongs to `utils/` or to another tool:

```
src/
├── utils/                          generic code; not built on its own
│   ├── baml.toml
│   └── baml_src/
│       └── ns_common/              → root.common
└── <tool>/
    ├── baml.toml                   declares this tool's generator, if it has a host
    ├── baml_src/
    │   ├── ns_common -> ../../utils/baml_src/ns_common
    │   ├── ns_<name>/              → root.<name>, owned here, linked by others
    │   └── *.baml                  the tool itself, and its tests, in the root namespace
    ├── tests/                      what those tests read, if they read anything
    └── host/                       host program, if the tool needs one
```

A tool is added by creating its directory with a `baml.toml`, symlinking the shared namespaces it uses, and referring to their symbols by absolute path: `root.common.Shell`.

### What goes in `utils/` and what does not

`src/utils/` holds what is generic: code that would read the same if the tool it was first written for did not exist. Running commands, touching files, reading YAML, splitting text.

Code that exists because of one tool belongs to that tool, in a namespace of its own inside its project, even when another tool needs it. Another tool then symlinks that namespace exactly as it symlinks a shared one.

The return-message template package and its values format are the case: they exist because `oparch-return-message-render` renders them, and they are specified under that tool in `docs/`. They live in `src/return-message-render/baml_src/ns_return_message/`, and the installer links them from there, because it asks for the fields a package declares and validates the same values in its own configuration file.

A tool with no host declares no generator and has no `host/`. It ships as what `baml pack` makes of its entry point, and its `baml.toml` is the `[package]` name alone. Which tools have a host, and why, is decided in [Host Bridge](001-host-bridge.md).

## Where the tests are, and why they are in two places

The unit tests are in `src/`, beside the code they test. The end-to-end harness is in `tests/`. That is not a preference; it is what the language allows.

A BAML test is a `test` block, written in a `.baml` file inside the project's `baml_src/`. It is source, compiled with everything around it, and there is nowhere else to put it: a directory outside the project is not part of the project, and the project cannot reference one. So the tests of a tool are in the files of that tool — most of them at the foot of the file whose functions they exercise, and `dotfiles-sync`'s in a `tests.baml` of its own because they cross most of it.

What a test reads goes in `tests/` **inside the project**, as `src/dotfiles-sync/tests/fixtures/` does. Relative paths in a test resolve against the project directory rather than against the working directory — `baml --directory src/dotfiles-sync test` finds them from anywhere — so a fixture is addressed the same way whoever runs the suite is standing.

The harness is the opposite case and gets the opposite answer. It boots a virtual machine on an image the project has built, it belongs to no project, and it tests all of them at once. `tests/e2e/` is where it lives: the wiring, the command that runs it, and a directory per case holding what that case hands the guest, as [End-to-End Testing](006-end-to-end-testing.md) lays out.

## Why

- One project per tool is chosen because each tool ships separately and declares its own generator; if all tools share a project, every generated SDK carries every tool's code and any change to one tool rebuilds the others.
- Code with more than one caller has exactly one home, wherever that home is; if it is copied into each caller, the copies drift.
- Only generic code lives there, because a directory named for what code *is not* — not specific to anyone — collects whatever has two callers, and ends up holding the domain of every tool with none of their names on it. A format that describes what one tool produces is that tool's, however many tools read it.
- Code tied to a tool stays in that tool even when another one needs it, because where code lives is what says who owns it. If it moves out on its second caller, ownership follows use, and the answer to "who decides what this format means" changes every time something new reads it.
- The shared code is reached by symlinking its namespace directory because BAML offers no other way to pull sources in from outside a project; if the files are duplicated instead, whichever project owns them stops being the source of truth it exists to be.
- `src/utils/` declares no generator because it produces no artifact of its own; it exists to be included and to hold the tests for what it provides.
- A tool with no host declares no generator either, for the same reason: a generator exists to hand BAML's symbols to another language, and there is no other language to hand them to.
- `install.sh` is at the top level rather than inside anything because it is fetched by its address and run, so where it sits is part of how it is published: a directory around it lengthens the command every reader of [Installation Script](../decisions/017-installation-script.md) types, and buys nothing.
- `packages/` and `archiso/` are at the top level because nothing already there could hold them: `src/` is one BAML project per tool and a `PKGBUILD` is not one, `assets/` is what the tools ship or read and neither a package definition nor an image profile is read by any tool, and `tests/` is the harness. What the two have in common is that they describe what leaves this repository rather than what is in it, and that is not what any of the others is for.
- `packages/` also holds what generates the key those packages are signed with, because a key whose only purpose is to sign them is not a subject apart from them, and a directory of its own for one script is a place nothing else would ever go.
- `.cloudflare/` holds what is deployed rather than installed, and it is in the repository at all so that what answers on the project's own addresses can be read by whoever wonders what answered. Its name is not imposed by anything; it is the one the other project of this author already uses for the same thing, and a second convention for one purpose is a convention nobody remembers.
- `.github/` is where it is because GitHub requires that name and that place. There is nothing decided about a path this project does not get to choose, and it is named here only so that the list above is the whole list.
- The unit tests are not gathered under `tests/` with the harness because a `test` block is source and a project cannot compile source from outside itself. Moving them would mean either a second project that duplicates what it tests, or fixtures addressed by a path that climbs out of the project it belongs to — and a suite that is hard to point at is a suite that stops being run.

## Considerations

- Running `baml test` inside a tool project also runs the tests of every namespace symlinked into it. That is wanted: shared code is verified in the context of each tool that depends on it.
- Generated SDKs and BAML caches exclude themselves from version control — the generator writes a `.gitignore` into the SDK directory, and `.baml/` carries its own. Neither needs an entry in the repository's `.gitignore`.
- A packed executable excludes itself from nothing, so the tool that produces one carries a `.gitignore` naming it.
- What a `PKGBUILD` is given to package — the built binaries, the runtime library, the archive of assets — is put beside it when a package is built and is no part of this repository. The definition is committed; what it packages is produced.
- Git stores the symlink itself, so a clone reproduces the layout with no setup step.
- Do not add a shared namespace to a tool that does not use it. The symlink is what declares the dependency, and it should mean something.
- A namespace owned by a tool is a directory two projects read, so renaming or removing that tool breaks whoever links it. The symlink is what makes that visible: it names the owner in the path.
- A tool's `tests/` holds what its tests read and no test of its own. A `.baml` file there would not be compiled, and would look like a suite nobody runs.

