# BAML Working Notes

What working in BAML has actually required, as opposed to what it looks like it should require. Everything here was found by running it, on toolchain `0.15.1-nightly.20260731.a` unless a note says otherwise, and each entry says what it costs the code.

This is a working document. An entry disappears when the toolchain stops needing it.

## Packaging a tool as an executable

`baml pack <function>` produces a standalone binary. For `oparch-return-message-render` it came out at 18 MB linked against `libc`, `libm` and `libgcc` only: no shared library to find and nothing downloaded on first run. That is not the situation of a tool with a generated SDK, described in `004-host-bridge.md`, where the host loads a ~25 MB library.

Three things about the generated entry point:

- **Every declared parameter becomes a mandatory flag**, `string?` included: an optional `--config` has to be written `--config null`. A tool whose options are optional therefore declares no parameters and reads `baml.sys.argv()` itself.
- `baml.sys.argv()` gives the whole command line, starting with the program path and the name of the packed target: `["./oparch-return-message-render", "main", "--config", "/etc/…"]`. Options start at the first argument that looks like one.
- **The return value is printed, not used as the exit status.** `baml.sys.exit` is what sets it.

## The language

- **`extends` is a reserved word** and cannot be a class field, even though it is what a field holding a parent's name wants to be called. `class PartialStyle { extends: string }` fails to parse with errors that point at the line after it.
- **`//#` comments are rejected inside an `implements` block**, where they parse as field declarations. `///` is accepted anywhere.
- **There is no int-to-float method.** `3.to_float()` and `baml.Int.from_float` do not exist; `value * 1.0` converts. `(3.7).round()` and `.floor()` return floats, not ints.
- **Narrowing is enforced, not merely offered.** After `if (value == null) { return … }` the compiler refuses `value ?? ""` as unnecessary. The same check that makes a value safe makes the fallback an error.
- **`\n` is dropped from a template literal that interpolates.** `` `${v}\n` `` is one character long, where `` `a\nb` `` is three, and `\t`, `\r` and `\\` survive in both. A generated line that ends in a value has to be written `` `… = ${v};` + "\n" ``, which is what the Plymouth prelude in `return-message-render` does.
- **Optional chaining stops at the field.** `(list.at(0))?.args.slice(0, 2)` does not compile, and `((list.at(0))?.args ?? [])` compiles to `string[] | _[]`, which has no methods at all. What works is a typed local — `let empty: string[] = []; x ?? empty` — or a small function whose declared return type does the coercion.

## The standard library

- `baml.yaml.parse` requires **string mapping keys**: a mapping keyed by numbers fails with `YAML mappings must use string keys to fit baml.json.json`. A format that wants to key entries by a number has to quote them, which is why `arrangement` in `../tools/oparch-return-message-render/003-theme-format.md` is written `"1":`.
- `baml.sys.exec`'s `ProcessOptions.env` **replaces the environment rather than adding to it**. `PATH` survives, `HOME` does not. Anything the child needs has to be passed.
- `baml.fs` has no `symlink` and no `chmod`. `root.common.SystemFiles` runs `ln -s` and `chmod` for those, which is why it needs a shell at all.
- `baml.sys.exec` takes the program and its arguments separately, so nothing built from a template package or a theme is ever parsed by a shell.

## Building a tool that has a host

`cargo build` is not the whole build. What the host runs is the BAML program embedded in its generated SDK, and only `baml generate` puts a change to `baml_src/` there — so a rebuilt binary happily runs the previous program, with nothing to suggest it. Two end-to-end runs were spent watching a phase that the source had but the binary did not. Anything that builds the installer runs `baml generate` first; `test/e2e/run.sh` does.

## The formatter

`baml fmt` is not run on this repository. Files that no one has touched are already unformatted by its standards, so running it would rewrite everything and bury the change that was actually made. Match the surrounding style by hand.

## Testing

`baml test` inside a project also runs the tests of every namespace symlinked into it, which is wanted and is why the counts in `001-installer-port-plan.md` overlap. Tests need no host, no bridge and no privileges; what stands in for the machine are the recording doubles in `root.common`.

A test asserting a command line is asserting a contract with a program that is not there. `RecordingShell` replies by exact command line, so a test that stops matching after an argument changes is the test working, not the test being brittle.
