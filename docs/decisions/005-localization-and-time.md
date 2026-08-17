# Localization and Time

## Context

The project's tooling and its maintenance are single-language. 

Keyboard layouts differ, and so does the local time where a machine is used. The hardware clock keeps a time without saying which one it is.

## Decision

System language is fixed to English and is not configurable. The locale is `en_US.UTF-8`.

The one text of the machine that is not in English is the pre-boot return message, shown in the languages the operator selects, as decided in [Pre-Boot Ownership Message](009-preboot-ownership-message.md).

Two things are configurable:

- the console keymap
- the timezone

Clock policy is fixed: hardware clock (RTC) uses UTC.

## Why

- The system language is not configurable because making it configurable means keeping a translation of everything the tooling says, in step with everything that changes it, and this project does not take that cost on.
- The return message is the one exception because it is read by whoever finds a lost machine, who did not choose this system and need not read English; in one language, instructions for returning the machine reach fewer of the people they are written for.
- The keymap is configurable because the layout depends on the physical keyboard in front of the machine; fixed here, a machine with another layout mistypes everything, the passphrase at unlock included.
- The timezone is configurable because local time and the timestamps in the logs depend on where the machine is; fixed here, they mislead everywhere else.
- The hardware clock keeps UTC because that is the standard Linux clock policy.

