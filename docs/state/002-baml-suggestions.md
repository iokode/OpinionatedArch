# BAML Suggestions

What this project would ask of BAML's standard library. The tools are written in BAML, as [BAML as Implementation Language](../development/000-baml-as-implementation-language.md) decides, and that decision counts this project as feedback for the BAML team. Each suggestion here is something the tools ran into, checked against the toolchain they are built with, `0.17.1-nightly.20260815.a`, and it stops being here when the toolchain covers it.

## Reading a command's standard error while it runs

**What there is.** `baml.sys.start_process` starts a program and returns at once with a `baml.sys.Process` whose `stdout` is a live line stream: each line is handed over as the child writes it, and reading it suspends only the green thread that reads. `baml.sys.exec` waits for the child to exit and returns both streams, buffered. What neither gives is the child's standard error while the child runs. A process started with `start_process` does not capture it at all: it goes to the parent's own standard error, which the toolchain's documentation of `baml.sys.Process` explains as keeping diagnostics visible without the risk of a stderr pipe that fills because nothing reads it.

**What is suggested.** A line stream for the child's standard error on `baml.sys.Process`, read the way `stdout` is, asked for in `baml.sys.ProcessOptions` so that a program that does not ask keeps today's behaviour and cannot leave a pipe unread.

**What it is for.**

- Telling what a command said from what it complained about, as it happens. The installer's log does that for every command it runs, line by line while the command runs, and [Remaining](001-remaining.md) carries an issue about how those lines are shown; a tool without a host that wanted the same could not have it, because the one stream it can read as it arrives is standard output.
- Owning what a command writes. A program that streams a command today gets the command's diagnostics mixed into its own standard error, with nothing to mark which program wrote which line, and no way to report, filter or keep a line it never sees.

**How it was found.** `baml describe` on `baml.sys.start_process`, `baml.sys.Process` and `baml.sys.ProcessLineStream` gives the behaviour above. A program started with `start_process` that wrote a line, slept two seconds and wrote another was read with the two lines arriving two seconds apart, which is what shows that standard output streams and is why standard error is the one that is missing.
