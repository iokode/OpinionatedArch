# Localization and Time

## Context

Project tooling and maintenance are single-language, while keyboard layout and machine location differ per installation.

## Decision

System language is fixed to English and is not configurable in the installer.

The only multilingual exception is the pre-boot Plymouth ownership/return screen.

The installer asks for:

- console keymap
- timezone

Clock policy is fixed: hardware clock (RTC) uses UTC.

## Why

- Fixing system language to English is required because project tooling and maintenance are intentionally single-language; if the system language is configurable, translation and consistency burden grows without operational benefit for this project.
- Keeping Plymouth as the only multilingual exception is required because that message is intended for unknown third parties who may find the device; if that screen is monolingual, return instructions are less accessible.
- Asking for keymap is required because keyboard layout depends on the physical keyboard used by each machine; if keymap is hardcoded, installations on different layouts (for example AZERTY vs QWERTY variants) will produce wrong key mapping and problematic unlock/input behavior.
- Asking for timezone is required because correct local time display and logs depend on machine location/use context; if timezone is wrong, timestamps become misleading.
- Fixing RTC to UTC is required because it is the standard Linux clock policy and avoids ambiguous local-time hardware clock behavior; if RTC is kept in local time, cross-environment clock drift/conflicts are more likely.

## Considerations

- Keymap selection must be applied both in installed system and in early unlock path where relevant.
- Locale policy here does not change the separate Plymouth multilingual decision.
- If future project requirements demand multilingual system tooling, this decision must be revised explicitly.
