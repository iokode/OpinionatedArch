# Agent Protocol

## 1. Fresh-Read Protocol (Mandatory)
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

## 2. Scope & Authorization Rule (Mandatory)

- Implement only what is **literally and explicitly requested**.
- Any change not explicitly described by the user is **out of scope by default**.

### Behavior changes
- Any of the following is a behavior change:
  - new function calls
  - removed function calls
  - new validations or checks
  - broader enforcement of existing rules
  - new execution paths or side effects

- Behavior changes are **forbidden unless explicitly authorized**.

### Authorization requirement
- Before applying a behavior change, the assistant must quote the **exact user message** that authorizes it.
- If no exact quote exists, the change is not allowed.

### No implicit expansion
- The following are NOT valid justifications:
  - “this is more correct”
  - “this improves consistency”
  - “this is safer”
  - “this is cleaner”
  - “this is expected”

## 3. Conservative Scope Classification Rule (Mandatory)

- If a change could reasonably be interpreted as:
  - part of the request, OR
  - an additional improvement

  → it MUST be classified as an **additional improvement (out of scope)**.

- If the assistant needs to explain why a change “still counts as requested scope”,
  then it is **not requested scope**.

- When in doubt, **do not apply the change**. Ask first.

## 4. Refactor Equivalence Rule (Mandatory)

- Refactor operations (extract, move, deduplicate, share) are **behavior-preserving by default**.

- This means:
  - no new calls
  - no removed calls
  - no added checks
  - no expanded usage of extracted code

- Extracting a function does NOT authorize using it in new places.

## 5. Pre-Edit Self-Check (Mandatory)

Before editing, the assistant must state:

- Requested operation:
- Planned changes:
- Behavior change: Yes/No

And answer explicitly:

1) Am I adding any new behavior?
2) Am I modifying anything not explicitly requested?
3) Am I applying extracted code in new places?

- If any answer is “Yes”:
  - quote exact user authorization, OR
  - stop and ask

## 6. Stop-On-Drift Rule (Mandatory)

- If the file changes externally during the turn, stop and ask before proceeding.
- Do not rely on earlier in-memory context when editing files.

## 7. Literal Language Rule (Mandatory)

- Interpret all user words by their literal definition.
- Treat user examples as examples only, not as exhaustive scope unless explicitly stated.
- Do not replace one term with another by "similar meaning" without explicit user confirmation.
- Keep distinct concepts distinct unless the user explicitly maps them.
- If any term could be interpreted in more than one literal way, stop and ask before proceeding.
- Do not try to assume user intentions, follow their words literally.

## 8. English-Only Output Rule (Mandatory)

- Regardless of the prompt language, any newly created code must be written in English.
- This includes variable names, symbols, and comments.
- Any newly created text files must also be written in English.
- Exception: files under `assets/` may contain non-English localization/resource text when their purpose is multilingual user-facing content.

## 9. Simplicity Rule (Mandatory)

- Prefer the simplest structure that fully satisfies the explicit request.
- Do not introduce extra folders, files, categories, or process steps unless explicitly needed.
- Keep documentation and scripting direct: one concern per file, one source of truth per topic.
- Avoid duplicate explanations across files.
- If multiple valid approaches exist, choose the less complex one or ask before adding complexity.

## 10. Clean Live Baseline Rule (Mandatory)

- Installer scripts must assume execution starts from a clean Arch live environment baseline.
- Do not add defensive state-handling for pre-existing install paths or artifacts that are impossible in that baseline.
- Do not add preventive cleanup/check patterns "just in case".
- Keep install flow linear when baseline state is known; fewer commands and fewer branches are preferred.

## 11. Critical Project Quality Rule (Mandatory)

- Treat this project as critical production infrastructure. Quick fixes and ad-hoc patches are not acceptable.
- Before changing behavior in installer scripts, read the full relevant code path end-to-end.
- Do not patch a downstream symptom without tracing the upstream data flow that produces it.
- For any asset/data flow, define and preserve one single source of truth and one transfer path.
- Do not introduce duplicate download/copy paths for the same artifact.
- Do not apply workaround fixes of any nature when root cause is unresolved. Fix root cause, not symptoms.
- If a fix could be interpreted as a workaround, stop and ask for approval before applying it.

## 12. Documentation Why Rule (Mandatory)

- Before editing any `Why` section, ask: "Is this change explaining a reason, or just restating implementation/facts?"
- `Why` sections must argue motivation, cause, consequence, or risk. Do not use them to repeat what the implementation does.
