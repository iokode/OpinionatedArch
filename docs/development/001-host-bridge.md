# Host Bridge

BAML has no TUI in its standard library yet. It streams what a command writes to standard output while the command runs, through `baml.sys.start_process`, but not what it writes to standard error, which a process started that way does not capture. A tool that draws a terminal interface, or that reads a long command's standard error while the command is still running, needs what BAML does not give.

Until BAML covers them, such a tool needs a host language. BAML calls it through a generated SDK ("the bridge"), declared as a `[generator.<name>]` in `baml.toml`. Ten targets exist: `python/pydantic`, `python/pydantic/v1`, `typescript/node`, `typescript/web`, `swift`, `go`, `rust`, `java`, `cpp`, `csharp`.

The BAML team has stated they are working on TUI support in the standard library, so whatever is chosen here is temporary.

## The bridge, and what keeps it disposable

The bridge is **`rust`**, with the host kept as a thin, disposable shim over the terminal and process execution.

Because the host is disposable, the selection criterion is not which host is best today, but which one leaves the BAML code untouched on the day it is deleted.

### Only a tool that needs one has a host

A host exists to own a terminal and to read a command's standard error while it is still running. A tool that needs neither has no host and no bridge: `baml.sys` runs commands and `baml.fs` touches files, and `baml pack` turns the tool into the executable it ships as.

Which tools need one is not settled by this document and is not expected to stay as it is. Today `oparch-installer-interactive` is the only one that has a host, and `oparch-return-message-render` the first built without one; a terminal interface is the kind of thing more tools will want, and each of them arrives at the same bridge by the same argument.

A **port** is the boundary between a tool and something outside it: running a command, touching a file, opening an encrypted store, drawing a terminal. It is declared as an interface so that a test can put a stand-in where the machine would be. Every interface in this project is a port today; the word is kept because an interface does not have to be one.

What a tool without a host uses instead are the same `Shell` and `Files` ports every tool is written against, implemented over `baml.sys` and `baml.fs` and living beside the recording doubles in [Repository Layout](002-repository-layout.md). Nothing above the port can tell which implementation is underneath, so the tests do not change and neither does the code being tested.

### Only commands cross the bridge

A host that exists is given the commands and nothing else. Touching a file is neither of the two things a host is for, so `Files` is implemented over `baml.fs` in every tool, hosted or not, and there is no host-side implementation of it to choose between.

Opening the installer's encrypted secret store crossed as well, for as long as there was nowhere else for it to happen: BAML's standard library has no `scrypt` to derive its key with, and `age(1)` took a passphrase from a terminal and from nowhere else. Since `age` 1.3, its `batchpass` plugin takes one from a file descriptor, so the store is opened by running `age` through the shell, as any other command is, and the host is given nothing that is not a command.

## Why

- A host language is used at all because BAML currently provides no TUI, and streams a command's standard output but not its standard error; a tool that tells what a command said from what it complained about, while the command runs, cannot do it in BAML alone.
- A tool that needs neither of those has no host because a host is then pure cost: a second language, a generated SDK, a build step and a runtime library, all to forward calls that `baml.sys` and `baml.fs` already make. It would also be cost paid for something already scheduled for deletion.
- The port is kept even where there is no host to hide, because what the ports buy is the recording doubles: a tool that called `baml.sys.exec` directly could only be tested by running the commands for real.
- One bridge target is chosen for the project rather than per tool, because the reasons below are properties of the boundary and not of any one tool; a second target would mean a second set of them to keep in mind, for no gain.
- The bridge is treated as disposable because BAML's standard library will cover this ground; if the host is designed as a permanent component, its constraints get baked into code that outlives it.
- `rust` is chosen over `go` because Go has no sum types, so a BAML union reaches the Go SDK as `any`. Working around that means flattening unions into tagged classes *in BAML* — permanent code written to serve a disposable host. Rust receives a generated `enum` and needs no such workaround.
- `rust`'s own limitations are accepted because they land entirely on the host side: function-type aliases cannot cross the boundary (inline closure types work), and reentrant calls must use the `_async` API. Neither deforms the BAML data model.
- `python` and `typescript` are rejected because both drag a language runtime plus dependencies into the live ISO, and Python additionally requires pinning the bridge package by hand. Rust produces a single binary.
- `csharp` is rejected because its generator aborts the entire build on an unsupported type rather than skipping the affected function.
- `swift`, `cpp` and `java` are rejected because none offers an advantage over Rust for this use case, and the first two share Rust's boundary limitations without its ecosystem fit for a small ISO binary.

## Considerations

### Evidence

The decision is based on a spike, not on documentation. A BAML project exercising every boundary shape a host needs was generated for all ten targets, and host programs were built and executed for `rust`, `go` and `python`. All results below are against toolchain `0.15.1-nightly.20260731.a`.

#### What each target accepts

| Target | `interface` argument | function-type alias | returns a closure | flat closure arguments | union return |
| --- | --- | --- | --- | --- | --- |
| `rust` | omitted | omitted | omitted | yes | typed `enum` |
| `go` | omitted | yes | yes | yes | `any` |
| `java` | `Object` | yes | yes | yes | typed `Union4<…>` |
| `python/pydantic`, `/v1` | `typing.Any` | yes | yes | yes | typed |
| `typescript/node`, `/web` | `unknown` | yes | yes | yes | typed |
| `swift` | omitted | omitted | omitted | yes | not measured |
| `cpp` | omitted | omitted | omitted | yes | not measured |
| `csharp` | generation aborts | — | — | — | — |

The three columns that decided the outcome are the first, the second and the last.

#### Interfaces do not cross in any target

They fail in three different ways: omitted from the SDK (`go`, `rust`, `swift`, `cpp`), a fatal generation error (`csharp`), or emitted with the parameter degraded to an untyped value (`java`, `python`, `typescript`). The third case is the dangerous one, since it compiles and fails only when called. Verified from Python, where both ways of satisfying it fail:

- a duck-typed host object: `TypeError: Cannot encode argument 'ui' of type PyUi into baml_inbound.proto`
- an instance of a BAML class that declares `implements Ui`: `TypeError: host value type 'ConsoleUi' is not assignable to declared type 'Ui'`

Only data and callable handles cross the boundary. Subtype polymorphism does not survive it, which is why the interface has to be reconstructed on the BAML side of the entrypoint.

#### Streaming works, through reentrancy

The host spawns the process, reads it line by line, and calls back into a BAML entrypoint for each line — while it is inside a callback that BAML itself invoked. That reentrancy works, and it is what keeps output parsing in BAML rather than in the host. Verified end to end on both `rust` and `go`: emitted timestamps track the child process's own pauses instead of arriving together at exit.

In Rust the reentrant call must use the `_async` API and an async callback; the synchronous form panics with `CalledSyncFromAsync`. Go needs no equivalent ceremony.

The more elegant shape — BAML handing the host its own line sink, as a callback that takes a callback — does not work anywhere. `go` drops the function with no diagnostic at all; `rust` emits it and then fails at call time with `expected function with named parameters, got wire variant handle`.

#### Why not Go

Go was the leading candidate until the streaming test. It accepts more of the boundary than Rust does: function-type aliases, and functions returning closures.

Two findings reversed it:

1. Go has no sum types, so consuming a BAML union from the host requires flattening it into a class with a discriminant field, plus a wrapper function to produce it. That is permanent BAML code whose only purpose is to serve a host that is scheduled for deletion. In Rust the same host code matches on the generated `enum` directly.
2. The Go generator reports nothing it discards. On identical sources, `go` emitted zero `warning: skipped` lines where `rust` emitted 217. A function can therefore vanish from the Go SDK with no diagnostic and exit code 0.

Rust's constraints, by contrast, are confined to the disposable side: write closure types inline instead of behind a `type` alias, and use the async API for reentrant calls.

#### Measurements

- A host-to-BAML call costs roughly 28 µs (5000 calls in 140 ms, release build). Calling BAML once per output line of a long command is not a performance concern.
- The host binary is not self-contained: it loads a ~25 MB shared library, downloaded on first run unless shipped in the archiso with `BAML_LIBRARY_PATH` pointing at it. `BAML_LIBRARY_DISABLE_DOWNLOAD` turns a missing library into a failure instead of a silent download, which is the wanted behaviour inside the ISO.
- The runtime logs to stdout as it starts, which lands on top of a TUI. `BAML_LOG` controls it.
- The bridge package is pinned to the exact toolchain build. The `rust` and `go` generators write that pin themselves; with Python it must be pinned by hand, and a mismatch surfaces as `Failed to deserialize BAML bytecode: Unexpected variant tag: 7`.

A tool with a host and a packed tool therefore ship differently, and what `baml pack` produces instead is measured in [BAML Working Notes](005-baml-working-notes.md).

### Consequences of the choice

- Classes with function-typed fields do not cross the boundary, so host closures must arrive flat at the entrypoint. They are wrapped there by a BAML class that implements the interface, and every other function sees only the interface.
- A hosted flow stays testable without the bridge: a BAML implementation of the same interface substitutes for the host, so `baml test` exercises the full flow with no host binary involved. The bridge is a production-only dependency.
- What would change this decision: BAML shipping a TUI and a stream of a command's standard error removes the need for a host entirely, which is the expected end state. Short of that, Go becomes preferable only if Rust's boundary limitations grow to affect the BAML side rather than the host side.
