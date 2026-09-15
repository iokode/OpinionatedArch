# Repository Layout

Where the sources live, where the tests live, why the two answers are not the same, and where what is neither of them goes.

The repository holds the source of every tool under `tools/`, the tests under `tests/`, the scripts that are run from a checkout and belong to none of the other directories under `scripts/`, the assets the tools ship or read under `assets/`, the packages the project publishes and what it takes to sign them under `packages/`, the profiles images are built from under `archiso/`, the workflows that build, publish and deploy all of it under `.github/`, what the project runs at the edge of its own domain under `.cloudflare/`, and the documentation under `docs/`. Those are the directories, and there is no other.

`archiso/` holds a directory for each image: `distrib/` for the installation image the project publishes, and `debug/` for an image carrying the installer built from the working tree, to try it and the tools in before they are published. How that image and the scripts that boot it are used is [Trying a Working Tree](009-trying-a-working-tree.md).

`scripts/` holds `install.sh`, the other way an installation is started, `vm-installer.sh`, which builds the debug image and boots it in a window to try the installer in, `vm.sh`, which installs a machine from that image, puts packages built from the working tree on it, and boots it in a window, and `vm-config.yaml`, the answers `vm.sh` installs that machine with. What they share with the tests is in `scripts/lib/`: `guest.sh`, which starts a guest under QEMU and drives it over its serial line, and which the end-to-end harness runs its cases in. Beside it is `toolchain.sh`, which holds a build to a memory ceiling and finds the BAML runtime library, and which `vm.sh` shares with the debug image's build.

More than one tool is written in BAML, and they have code in common — running external commands, reading command output, and the test doubles that go with those.

BAML has no dependency mechanism between projects. A project is a `baml.toml` plus a `baml_src/` directory, and it cannot reference another one: `[dependencies]` is answered with `warning: ignoring unrecognized top-level key 'dependencies' in baml.toml`, and an extra sources key with `warning: ignoring unrecognized key 'sources' in [package]`. Sharing therefore has to happen at the filesystem level.

What BAML does have is namespaces: a directory named `ns_<name>/` under `baml_src/` puts its files in namespace `<name>`, reachable from elsewhere in the project as `root.<name>.<symbol>`, with no imports.

## One directory per entity, sharing by symlinked namespace

The tools of an entity are interfaces over one library of that entity, as [Oparch Tools](../decisions/015-oparch-tools.md) decides. Each entity has a directory under `tools/` named after it, holding that library as a project in `lib/` and one project per tool, named after what follows the entity in the tool's name: `oparch-snapshot-restore` is `tools/snapshot/restore/`, and `oparch-snapshot-interactive` is `tools/snapshot/interactive/`. Generic code is a project of its own under `tools/utils/`. A namespace directory is symlinked into every project that uses it, whether it belongs to `utils/` or to the library of an entity:

```
tools/
├── utils/                          generic code; not built on its own
│   ├── baml.toml
│   ├── baml_src/
│   │   └── ns_common/              → root.common
│   └── host/                       the Rust crate every host is built on
├── <entity>/
│   ├── lib/                        the entity's library; not built on its own
│   │   ├── baml.toml
│   │   ├── baml_src/
│   │   │   ├── ns_common -> ../../../utils/baml_src/ns_common
│   │   │   ├── ns_<entity>/        → root.<entity>, the domain logic of the entity, linked by its tools
│   │   │   └── *.baml              tests that read what is in tests/, in the root namespace
│   │   └── tests/                  what those tests read, if they read anything
│   └── <action>/                   one project per tool of the entity
│       ├── baml.toml               declares this tool's generator, if it has a host
│       ├── baml_src/
│       │   ├── ns_common -> ../../../utils/baml_src/ns_common
│       │   ├── ns_<entity> -> ../../lib/baml_src/ns_<entity>
│       │   └── *.baml              the tool's interface, and its tests, in the root namespace
│       ├── tests/                  what those tests read, if they read anything
│       └── host/                   host program, if the tool needs one
└── installer/                      the installer, laid out as an entity
```

The namespace of an entity is its name with its hyphens written as underscores: the return message's is `ns_return_message`, reached as `root.return_message`.

The installer is laid out as an entity, `installer`, whose library in `tools/installer/lib/` holds the installation. Its two projects are named after what they are rather than after an action, because `oparch-installer` has no action in its name: `unattended/` is `oparch-installer`, and `interactive/` is `oparch-installer-interactive`.

An interactive tool over a system tool has no library, so the directory of its entity holds that tool's project alone.

An entity is added by creating its directory and its library. A tool is added by creating its project inside the directory of its entity with a `baml.toml`, symlinking the namespaces it uses, and referring to their symbols by absolute path: `root.common.Shell`.

### What goes in `utils/`, in a library, and in a tool

`tools/utils/` holds what is generic: code that would read the same if the tool it was first written for did not exist. Running commands, touching files, reading YAML, splitting text.

What is generic to a host is there too, in `tools/utils/host/`: a Rust crate, `oparch-host`, holding what every host does whichever tool it serves, as [Host Bridge](001-host-bridge.md) describes. It knows no tool and no generated SDK. A tool's host depends on it by path in its `Cargo.toml`, and holds only what is that tool's own.

The domain logic of an entity belongs to its library, whichever of its tools first needed it, and stays there when a project outside the entity needs it too. That project symlinks the namespace exactly as it symlinks a shared one.

The return-message template package and its values format are the case: they belong to the return message, and they are specified under `docs/tools/return-message/render/`. They live in `tools/return-message/lib/baml_src/ns_return_message/`, and the installer links them from there, because it asks for the fields a package declares and validates the same values in its own configuration file.

The project of a tool holds its interface and no domain logic: the arguments it reads and what it prints, or the screens it draws and whatever the interface does to the system so it can be used.

A tool with no host declares no generator and has no `host/`. It ships as what `baml pack` makes of its entry point, and its `baml.toml` is the `[package]` name alone. Which tools have a host, and why, is decided in [Host Bridge](001-host-bridge.md).

## Where the tests are, and why they are in two places

The unit tests are in `tools/`, beside the code they test. The end-to-end harness is in `tests/`. That is not a preference; it is what the language allows.

A BAML test is a `test` block, written in a `.baml` file inside the project's `baml_src/`. It is source, compiled with everything around it, and there is nowhere else to put it: a directory outside the project is not part of the project, and the project cannot reference one. So the tests of a library or a tool are in its files — most of them at the foot of the file whose functions they exercise, and the dotfiles library's in a `tests.baml` of its own because they cross most of it.

What a test reads goes in `tests/` **inside the project**, as `tools/dotfiles/lib/tests/fixtures/` does. Relative paths in a test resolve against the project directory rather than against the working directory — `baml --directory tools/dotfiles/lib test` finds them from anywhere — so a fixture is addressed the same way whoever runs the suite is standing.

That is why a test that reads a fixture is in the root namespace of its project and never inside a namespace. The tests inside a namespace run in every project the namespace is linked into, and there a relative path resolves against that project, where the fixture is not.

The harness is the opposite case and gets the opposite answer. It boots a virtual machine on an image the project has built, it belongs to no project, and it tests all of them at once. `tests/e2e/` is where it lives: the wiring, the command that runs it, and a directory per case holding what that case hands the guest, as [End-to-End Testing](006-end-to-end-testing.md) lays out. The guest it runs the cases in is not its own: starting one and driving its serial line is `scripts/lib/guest.sh`, which `scripts/vm-installer.sh` and `scripts/vm.sh` use too.

## Why

- One project per tool is chosen because each tool ships separately and declares its own generator; if all tools share a project, every generated SDK carries every tool's code and any change to one tool rebuilds the others.
- The tools of an entity are gathered in the directory of that entity because they are interfaces over one library: the library and every tool built on it are found in one place, and the path of a tool says which library it is built on.
- Code with more than one caller has exactly one home, wherever that home is; if it is copied into each caller, the copies drift.
- What every host shares is in `tools/utils/` because it is generic by the same measure as `root.common`: it would read the same if the installer did not exist. It is a crate a host depends on by path rather than a namespace linked in, because the hosts are Rust, and a path dependency is how Cargo reaches code outside a project, where BAML has nothing but the link.
- Only generic code lives there, because a directory named for what code *is not* — not specific to anyone — collects whatever has two callers, and ends up holding the domain of every tool with none of their names on it. What belongs to an entity is that entity's, however many projects read it.
- The domain logic of an entity stays in its library even when a project outside the entity needs it, because where code lives is what says who owns it. If it moves out on its second caller, ownership follows use, and the answer to "who decides what this format means" changes every time something new reads it.
- The shared code is reached by symlinking its namespace directory because BAML offers no other way to pull sources in from outside a project; if the files are duplicated instead, whichever project owns them stops being the source of truth it exists to be.
- `tools/utils/` and the library of each entity declare no generator because they produce no artifact of their own; they exist to be included and to hold the tests for what they provide.
- A tool with no host declares no generator either, for the same reason: a generator exists to hand BAML's symbols to another language, and there is no other language to hand them to.
- `scripts/` is apart from `tests/` because what is in it is not a test: `install.sh` is published and run on a live environment, and `vm-installer.sh` and `vm.sh` are how a working tree is tried by hand. Keeping the tests in one directory of their own is what lets every kind of them be found in the same place.
- What drives a guest is in `scripts/lib/` rather than in the harness because more than the tests drive one: the harness runs its cases in a guest, and `vm.sh` installs a machine in one. Kept in the harness, `vm.sh` would reach into `tests/` for it; split this way, the tests depend on a script and a script never depends on the tests.
- `packages/` and `archiso/` are at the top level because nothing already there could hold them: `tools/` holds BAML projects and a `PKGBUILD` is not one, `assets/` is what the tools ship or read and neither a package definition nor an image profile is read by any tool, and `tests/` is the tests. What the two have in common is that they describe what is made out of this repository, packages and images, rather than what is in it, and that is not what any of the others is for.
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
- Do not add a shared namespace to a project that does not use it. The symlink is what declares the dependency, and it should mean something.
- A namespace owned by a library is a directory several projects read, so renaming or removing its entity breaks whoever links it. The symlink is what makes that visible: it names the owner in the path.
- A project's `tests/` holds what its tests read and no test of its own. A `.baml` file there would not be compiled, and would look like a suite nobody runs.
