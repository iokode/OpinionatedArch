# Pre-Boot Ownership Message

## Context

The disk-unlock screen shown at boot can display an ownership-and-return message before the operating system starts.

## Decision

The installer asks whether this return message should be included.

If the return message is disabled, the installer does not ask for ownership fields, logo inclusion, or `logo_url`, and it does not configure Plymouth for the return-message screen.

The message includes both contact channels:

- owner name
- phone number
- email address
- return address

The message is shown in 1 to 4 installer-selected languages from template files under `assets/returning-templates`.

Each template is a `.tpl` file composed as follows: language name on line 1, blank separator on line 2, and localized return message from line 3 onward.

The supported template placeholders are:

- `{{OWNER_NAME}}`
- `{{OWNER_PHONE}}`
- `{{OWNER_EMAIL}}`
- `{{OWNER_RETURN_ADDRESS}}`

The visual layout reserves four language slots under the optional logo and above the password input.

Layout rules are:

- 1 selected language: one block fills all four language slots.
- 2 selected languages: the first block uses the top half and the second block uses the bottom half.
- 3 selected languages: the first block uses the top half, and the second and third blocks split the bottom half.
- 4 selected languages: blocks use a 2x2 grid.

Language identity is shown from the template language name, not from flags.

The canonical message content is: "This device belongs to [owner name]. If found, please call [...], send an email to [...], or return it to the address [...]."

When the return message is enabled, the installer asks for all message data at install time (owner name, phone, email, return address).

The ownership screen may optionally include a company logo. When the return message is enabled, the installer asks whether logo inclusion is desired. If yes, it asks for `logo_url`, downloads it during installation, and embeds it into Plymouth assets before initramfs generation.

If logo download fails (for example 404 or invalid URL), the installer must not continue silently. It must ask whether to retry with a new URL or continue consciously without logo.

Boot-time rendering must be fully offline: no network dependency is allowed during unlock.

Implementation target is a custom Plymouth theme used during LUKS unlock.

## Why

- Making the ownership-and-return text optional is required because not every installation should publish contact data at pre-boot; if it is mandatory, privacy or deployment-specific preferences cannot be represented without editing installer code.
- Showing ownership-and-return text at pre-boot unlock is useful because a finder can read contact instructions immediately without needing OS access; if omitted, device return depends on external assumptions and recovery chance drops.
- Including owner name is required because the finder needs a clear identity marker for who should receive the device; if owner identity is missing, return intent is less explicit and can create confusion.
- Including both phone and email is required because the finder may only be able to use one communication channel at that moment; if only one channel is shown, reachable contact probability is lower.
- Including a return address is required because some finders may prefer physical return over remote contact; if address data is missing, return options are reduced.
- Restricting selection to at most four languages is required because the screen must preserve readable contact text at early-boot resolutions; if too many languages are shown, each message becomes too small or too dense to scan quickly.
- Installer-selected language templates are required because travel and deployment regions can differ per machine; if the language set is fixed, some installations show irrelevant languages while others miss useful ones.
- Template files are required because localized wording must have one source of truth per language; if translations are embedded directly in installer logic, updates become harder to review and reuse.
- Native language names are required because they identify the readable block without relying on political or regional symbols; if flags are used for languages, the cue can be ambiguous or inappropriate.
- Adaptive slot layout is required because the selected language count is variable; if a fixed 2x2 layout is used for every case, one-language and two-language configurations waste space that should improve readability.
- Installer-time capture of owner name, phone, email, and return address is required when the return message is enabled because personal identity/contact data must not be hardcoded in scripts; if hardcoded, reuse across machines and updates becomes error-prone.
- Optional logo support is required because ownership branding is useful but not always desired on every machine; if logo inclusion cannot be chosen explicitly, installer behavior becomes less controllable.
- `logo_url` is required only when logo inclusion is enabled because logo source data must be explicit and reproducible; if source is implicit, logo provisioning becomes brittle.
- Downloading the logo only at install time is required because early boot has no network guarantees; if boot depends on remote retrieval, unlock UI can fail or degrade unpredictably.
- Logo download failure must trigger explicit operator choice (retry URL or continue without logo) because URL typos are common and silent fallback hides configuration mistakes; if failure is silent, intended branding is lost without user awareness.
- Using a custom Plymouth theme is required when the return message is enabled because default cryptsetup prompts do not provide the needed multilingual visual customization; if default prompt is kept, this message cannot be presented as designed.

## Considerations

- Contact data is intentionally public on the pre-boot screen by design decision.
- Contact data is requested only when the return message is enabled.
- If Plymouth fails, unlock should still fall back to functional text-mode prompt.
- Owner name, phone, email, and return address values should be injected from installer input to avoid hardcoded personal data in scripts.
- `logo_url` is requested only after explicit logo opt-in.
- Logo download failures must never be silent; operator must explicitly choose retry or continue without logo.
- Runtime unlock must never fetch remote assets; all Plymouth assets must be local before initramfs is built.
- Return-message readability must be validated on the real display resolutions used by the target machines.
