# Agent Protocol

## Fresh-Read Protocol (Mandatory)
For any requested file edit, always follow these steps in order:

1. Re-read from disk before editing and show proof:
   - `sha256sum <file>`
   - `rg -n "<key-identifiers>" <file>`
   - `nl -ba <file> | sed -n '<start>,<end>p'` (relevant lines only)
2. Perform only the requested edit.
3. Re-read from disk after editing and show proof:
   - `sha256sum <file>`
   - `rg -n "<key-identifiers>" <file>`
   - `nl -ba <file> | sed -n '<start>,<end>p'`
   - `git diff -- <file>`

## Stop-On-Drift Rule (Mandatory)
- If the file changes externally during the turn, stop and ask before proceeding.
- Do not rely on earlier in-memory context when editing files.

## Scope Rule (Mandatory)
- Do not do anything that was not explicitly requested.
- If a change is not clearly requested, stop and ask before doing it.
- If a change is requested to specific file or area, do only on that file or area.
- If the requested change cannot be completed within the explicit scope, do not proceed: ask first (per Ask-Before-Assuming Protocol and Dependency Escalation Rule).

## Dependency Escalation Rule (Mandatory)
- Implement only the explicitly requested change.
- If completing the request requires any additional change not explicitly requested
  (tests, signatures, DI, routes, refactors, imports, formatting, new files, etc.),
  stop and ask before modifying those files.
- Do not assume "obvious" or "necessary" follow-up changes without asking first.
- Provide 1-3 concrete options with impacted files and wait for user choice.

Question format (mandatory):
- "To complete X, I also need to change Y. Choose:
  1) Only requested scope (partial outcome),
  2) Include minimal required extra changes (list files),
  3) Include full consistency changes (list files)."

## Ask-Before-Assuming Protocol (Mandatory)
- If a task can be done in multiple valid ways and the user did not specify which one, ask before choosing.
- If there is any doubt about scope, naming, behavior, side effects, or intent, ask before proceeding.
- Do not infer missing requirements when they can change implementation decisions.
- If clarification is needed, stop and ask concise, explicit options.

## Literal Language Rule (Mandatory)
- Interpret all user words by their literal definition.
- Treat user examples as examples only, not as exhaustive scope unless explicitly stated.
- Do not replace one term with another by "similar meaning" without explicit user confirmation.
- Keep distinct concepts distinct (for example structure vs agent directive) unless the user explicitly maps them.
- If any term could be interpreted in more than one literal way, stop and ask before proceeding.
- Do not try to assume user intentions, follow their words literally.

## English-Only Output Rule (Mandatory)
- Regardless of the prompt language, any newly created code must be written in English.
- This includes variable names, symbols, and comments.
- Any newly created text files must also be written in English.

## Simplicity Rule (Mandatory)
- Prefer the simplest structure that fully satisfies the explicit request.
- Do not introduce extra folders, files, categories, or process steps unless explicitly needed.
- Keep documentation and scripting direct: one concern per file, one source of truth per topic.
- Avoid duplicate explanations across files.
- If multiple valid approaches exist, choose the less complex one or ask before adding complexity.

## Docs Structure Clarification (Mandatory)
- Any "one-level" constraint applies to filesystem directory structure under `docs/` only.
- Do not reinterpret directory-depth constraints as markdown formatting constraints.
- Inside markdown files, use the correct component for content semantics:
  - ordered lists when order matters,
  - bullet lists when order does not matter.
- Ordered vs bullet lists are not directory nesting and must not be treated as such.

## Decision Critique Rule (Mandatory)
- Critique decisions directly in chat, not only in documentation.
- Keep documentation focused on the final decision.
- If requested, include a copied section named `Critical Notes With Replies (Copy of Discussion)` that preserves critique and user responses.

## Why Clarity Rule (Mandatory)
- Every decision document must include a `Why` section.
- `Why` must explain the literal reason for each relevant decision item.
- For each decision item, `Why` must include a concrete cause and a concrete consequence of not doing it.
- A `Why` sentence that only restates the decision (`what`) is invalid.
- Avoid vague statements (for example: "it is efficient", "it is cleaner") unless the concrete mechanism is explicitly explained.
- If multiple items are decided (for example several subvolumes), explain the reason for each item explicitly.
- Before finalizing a decision document, run a line-by-line coverage check:
  1) list each decision item from `Context and Decision`,
  2) verify there is one matching causal explanation in `Why`,
  3) rewrite any item that fails this mapping.
- If the causal reason cannot be written literally, the decision is incomplete and must return to discussion.

## Why Acceptance Gate (Mandatory)
- Before finalizing any decision document, the assistant must validate each decision item using this structure in working notes:
  - `Decision item: <what was decided>`
  - `Literal reason: <real-world cause that motivates it>`
  - `If omitted: <specific failure mode or risk>`
- If any item cannot be completed with all three fields, the document must be treated as incomplete and returned to discussion instead of being finalized.
- Causal wording must be explicit and concrete. Sentences that only rename the decision are invalid.
- Quick validity test:
  1) Remove the word "because" from a `Why` sentence.
  2) If what remains is still basically the same decision, it is a fake why and must be rewritten.

## Why Workflow Lock (Mandatory)
- For decision documents, do not edit the file until the assistant has posted the full `Decision item -> Literal reason -> If omitted` matrix in chat.
- If the user challenges any `Why`, stop further document edits and return to matrix-first mode.
- A decision document can be finalized only after every `Context and Decision` item has an accepted causal mapping in chat.
