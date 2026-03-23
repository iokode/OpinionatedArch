# 011: Pre-Boot Ownership Message

## Context and Decision

The disk-unlock screen shown at boot must display an ownership-and-return message before the operating system starts.

The message includes both contact channels:

- owner name
- phone number
- email address
- return address

The message is shown in four languages:

- English
- Catalan
- Spanish
- French

The visual layout is a clear 2x2 grid (one language block per cell). Each language block includes a PNG flag icon and clear visual separation from other blocks.

Each language block must include a 3-letter uppercase label:

- `ENG`
- `CAT`
- `ESP`
- `FRA`

The canonical message content is: "This device belongs to [owner name]. If found, please call [...], send an email to [...], or return it to the address [...]."

The installer asks for all message data at install time (owner name, phone, email, return address).

The ownership screen may optionally include a company logo. The installer first asks whether logo inclusion is desired. If yes, it asks for `logo_url`, downloads it during installation, and embeds it into Plymouth assets before initramfs generation.

If logo download fails (for example 404 or invalid URL), the installer must not continue silently. It must ask whether to retry with a new URL or continue consciously without logo.

Boot-time rendering must be fully offline: no network dependency is allowed during unlock.

Implementation target is a custom Plymouth theme used during LUKS unlock.

## Why

- Showing ownership-and-return text at pre-boot unlock is required because a finder can read contact instructions immediately without needing OS access; if omitted, device return depends on external assumptions and recovery chance drops.
- Including owner name is required because the finder needs a clear identity marker for who should receive the device; if owner identity is missing, return intent is less explicit and can create confusion.
- Including both phone and email is required because the finder may only be able to use one communication channel at that moment; if only one channel is shown, reachable contact probability is lower.
- Including a return address is required because some finders may prefer physical return over remote contact; if address data is missing, return options are reduced.
- Restricting to four languages is required because this travel/usage profile prioritizes clarity and screen simplicity over broad language coverage; if too many languages are shown, readability drops and key contact information is harder to scan quickly.
- Excluding Estonian is required because it is not part of the primary operating regions in this phase; if included now, layout complexity increases without enough expected return value.
- Fixed uppercase labels (`ENG`, `CAT`, `ESP`, `FRA`) are required because language identification must remain obvious even if a flag icon is not recognized; if labels are omitted, language selection can be ambiguous.
- A 2x2 grid is required because four languages map cleanly to equal visual blocks; if layout is uneven, message scanning time increases and comprehension under stress is worse.
- PNG flag icons are required because early-boot rendering is more reliable with explicit image assets than with emoji font fallback; if emoji or implicit fonts are used, rendering can break and language cues can disappear.
- Clear separation between language blocks is required because the screen must be readable quickly by unknown users; if blocks visually blend, users may miss their language section.
- Installer-time capture of owner name, phone, email, and return address is required because personal identity/contact data must not be hardcoded in scripts; if hardcoded, reuse across machines and updates becomes error-prone.
- Optional logo support is required because ownership branding is useful but not always desired on every machine; if logo inclusion cannot be chosen explicitly, installer behavior becomes less controllable.
- `logo_url` is required only when logo inclusion is enabled because logo source data must be explicit and reproducible; if source is implicit, logo provisioning becomes brittle.
- Downloading the logo only at install time is required because early boot has no network guarantees; if boot depends on remote retrieval, unlock UI can fail or degrade unpredictably.
- Logo download failure must trigger explicit operator choice (retry URL or continue without logo) because URL typos are common and silent fallback hides configuration mistakes; if failure is silent, intended branding is lost without user awareness.
- Using a custom Plymouth theme is required because default cryptsetup prompts do not provide the needed multilingual visual customization; if default prompt is kept, this message cannot be presented as designed.

## Implementation Plan

1. Add a Plymouth theme under project assets for pre-boot unlock.
2. Prompt for owner name, phone, email, and return address values.
3. Add four localized text blocks with labels (`ENG`, `CAT`, `ESP`, `FRA`) and the same owner/contact data in each block.
4. Add PNG flag assets and place them next to each language block.
5. Prompt whether to include a logo (`yes/no`).
6. If `yes`, prompt for `logo_url` and attempt download during installation.
7. If download fails, prompt for explicit choice: retry with a new URL or continue without logo.
8. If logo download succeeds, copy it into Plymouth theme assets used for initramfs generation.
9. Arrange the layout as a 2x2 grid with clear separators.
10. Configure initramfs and boot flow to use Plymouth during disk unlock.
11. Validate readability on real display resolutions used by the target machines.

## Considerations

- Contact data is intentionally public on the pre-boot screen by design decision.
- If Plymouth fails, unlock should still fall back to functional text-mode prompt.
- Owner name, phone, email, and return address values should be injected from installer input to avoid hardcoded personal data in scripts.
- `logo_url` is requested only after explicit logo opt-in.
- Logo download failures must never be silent; operator must explicitly choose retry or continue without logo.
- Runtime unlock must never fetch remote assets; all Plymouth assets must be local before initramfs is built.
