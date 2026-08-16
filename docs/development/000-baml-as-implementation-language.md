# BAML as Implementation Language

The tool inventory and the policy governing it are defined in [Oparch Tools](../decisions/019-oparch-tools.md) and `docs/tools/`; they are not repeated here.

The installer had two earlier implementations, first in Bash and then in C#. Neither was the target state, and both were deleted once the BAML one reached what they did: an implementation kept for reference is one that gets read as if it still said something.

Only the PKGBUILD inspector needs LLM functions. The other tools use BAML as a general-purpose language.

## The language the tools are written in

The built-in tools of this distribution are written in BAML, unified on a single language and toolchain. This replaced both earlier implementations of the installer, and the `sh` operational tools with them.

## Why

- BAML is chosen because this project is the vehicle for trying it and learning it.
- BAML is chosen because [Antonio Sarosi](https://x.com/antoniosarosi), on the BAML team, is a personal contact, so direct support is available.
- BAML is chosen because this project is intended as feedback for the BAML team.
- A language specialized for agents is chosen because this project needs fast iteration and is therefore built entirely with AI. Being a new project, there is no existing codebase whose migration cost would weigh against it.
- BAML fits the PKGBUILD inspector directly, which uses an LLM to read a package build script and report its risk level.
- The unification across every tool is the point, rather than using BAML only where LLM functions are involved.

## Considerations

- BAML has no TUI in its standard library yet, so the installer needs a host language for its terminal interface for now. See [Host Bridge](001-host-bridge.md).
- The installed system now carries the BAML runtime, a shared library of about 25 MB, for every tool that runs on it. The superseded policy in [Oparch Tools](../decisions/019-oparch-tools.md) chose `sh` precisely to keep runtime dependencies minimal, and that criterion no longer has a replacement. It is accepted here rather than left implicit: the cost is one shared library for the whole tool set, paid once.

