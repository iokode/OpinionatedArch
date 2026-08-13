# Agent Protocol

 

## 1. One Way To Do Each Thing

- Every capability of this project has exactly one form. Formats, commands, and interfaces do not offer alternatives that achieve the same result.
- Never propose a design that permits several ways of expressing the same thing. When a constraint seems to require a second form, the constraint is what has to be solved, not worked around by adding an option.
- Exceptions require an explicit, documented justification, and are expected to be rare.
- Fewer branches beat convenience. Predictability is the goal: a reader of a file, a command, or a document should not have to ask which of the available styles is in use.

## 2. Documentation Is the Source of Truth

- `docs/` is the only source of truth for this project. It defines the operating model, the decisions behind it, the formats the project relies on, and the tools it ships.
- Document types, their directories, and their section orders are defined in `docs/README.md`. Follow them.
- Do not restate documented content elsewhere. Link to the document that owns it.
- `Why` sections must argue motivation, cause, consequence, or risk. Before editing one, ask: "Is this change explaining a reason, or just restating implementation/facts?"
- Implementation plans do not belong in these documents. When a plan is needed, it gets its own dedicated document.

## 3. Clean Live Baseline

- Installer scripts must assume execution starts from a clean Arch live environment baseline.
- Do not add defensive state-handling for pre-existing install paths or artifacts that are impossible in that baseline.
- Do not add preventive cleanup/check patterns "just in case".
- Keep install flow linear when baseline state is known; fewer commands and fewer branches are preferred.

## 4. Single Asset Path

- For any asset/data flow, define and preserve one single source of truth and one transfer path.
- Do not introduce duplicate download/copy paths for the same artifact.
- Do not patch a downstream symptom without tracing the upstream data flow that produces it.

## 5. All Or Nothing

- An installation either finishes in full or it fails. There is no third outcome: a run that stops leaves a machine that is not to be booted, not a machine missing a piece.
- Every step of a flow is required. A step that produces a convenience rather than a requirement is still required, and its failure stops the run exactly like any other.
- Never downgrade a failure to a warning so that a run can continue. A step that is allowed to fail without consequence does not belong in the flow at all.
- Never leave a partial result standing as good enough, and never route around a failing step. Trace it to its cause and fix the cause.

## 6. Language

- The repository's English-only rule has one exception: files under `assets/` may contain non-English localization or resource text when their purpose is multilingual user-facing content.
