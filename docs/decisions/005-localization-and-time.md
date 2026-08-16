# Localization and Time

## Context

Project tooling and maintenance are single-language, while keyboard layout and machine location differ per installation.

## Decision

System language is fixed to English and is not configurable.

The only multilingual exception is the pre-boot Plymouth ownership/return screen.

Two things are configurable:

- the console keymap
- the timezone

Clock policy is fixed: hardware clock (RTC) uses UTC.

## Why

- Fixing system language to English is required because project tooling and maintenance are intentionally single-language; if the system language is configurable, translation and consistency burden grows without operational benefit for this project.
- Keeping Plymouth as the only multilingual exception is required because that message is intended for unknown third parties who may find the device; if that screen is monolingual, return instructions are less accessible.
- The keymap is configurable because the layout depends on the physical keyboard in front of the machine; fixed here, a machine with another layout mistypes everything, the passphrase at unlock included.
- The timezone is configurable because local time and the timestamps in the logs depend on where the machine is; fixed here, they mislead everywhere else.
- Fixing RTC to UTC is required because it is the standard Linux clock policy and avoids ambiguous local-time hardware clock behavior; if RTC is kept in local time, cross-environment clock drift/conflicts are more likely.

## Considerations

- Keymap selection must be applied both in installed system and in early unlock path where relevant.
- Locale policy here does not change the separate Plymouth multilingual decision.
- If future project requirements demand multilingual system tooling, this decision must be revised explicitly.
