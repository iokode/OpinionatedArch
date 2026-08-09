# Agent Protocol

 

## 1. Documentation Is the Source of Truth

- `docs/` is the only source of truth for this project. It defines the operating model, the decisions behind it, the formats the project relies on, and the tools it ships.
- Document types, their directories, and their section orders are defined in `docs/README.md`. Follow them.
- Do not restate documented content elsewhere. Link to the document that owns it.
- `Why` sections must argue motivation, cause, consequence, or risk. Before editing one, ask: "Is this change explaining a reason, or just restating implementation/facts?"
- Implementation plans do not belong in these documents. When a plan is needed, it gets its own dedicated document.

## 2. Clean Live Baseline

- Installer scripts must assume execution starts from a clean Arch live environment baseline.
- Do not add defensive state-handling for pre-existing install paths or artifacts that are impossible in that baseline.
- Do not add preventive cleanup/check patterns "just in case".
- Keep install flow linear when baseline state is known; fewer commands and fewer branches are preferred.

## 3. Single Asset Path

- For any asset/data flow, define and preserve one single source of truth and one transfer path.
- Do not introduce duplicate download/copy paths for the same artifact.
- Do not patch a downstream symptom without tracing the upstream data flow that produces it.

## 4. Language

- The repository's English-only rule has one exception: files under `assets/` may contain non-English localization or resource text when their purpose is multilingual user-facing content.

