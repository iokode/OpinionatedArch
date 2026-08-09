# Installer Configuration File Format

## Context

`oparch-installer` can take every installation input from a file instead of asking for it, through `--config <path>`. That file has to express exactly what the interactive screens collect, so that an installation performed either way is the same installation.

The return message is defined by a template package that declares its own fields, so the file must be able to carry values whose names the installer does not know in advance.

The inputs themselves are decided in `../../decisions/000-installer-inputs-and-bootstrap-baseline.md`, and the return message in `../../decisions/007-preboot-ownership-message.md`. This document defines how they are written down.

## Specification

The file is YAML.

### Shape

```yaml
disk: /dev/sda
install_mode: wipe-all

ucode_package: amd-ucode
gpu_driver: none

swap:
  zram_gb: 8
  swapfile_gb: 0

login_users:
  - ivan
  - work
shared_secret: "a shared secret"

console_keymap: es
timezone: Europe/Madrid
hostname: oparch

dotfiles:
  repository_url: https://example.invalid/dotfiles.git

return_message:
  languages:
    - es
    - ca
  fields:
    owner_name: Ivan
    phone: "+34 666 555 666"
    address: Carrer de la Unió, Andorra
  logo_url: https://example.invalid/logo.png
```

### Keys

| Key | Value | Required |
| --- | --- | --- |
| `disk` | Path of an existing block device | yes |
| `install_mode` | `wipe-all` or `keep-homes` | yes |
| `preserved_home_users` | List of usernames | only with `keep-homes` |
| `ucode_package` | `intel-ucode`, `amd-ucode` or `none` | yes |
| `gpu_driver` | `nvidia`, `nvidia-open`, `nouveau` or `none` | yes |
| `swap.zram_gb` | Non-negative integer | no, defaults to `0` |
| `swap.swapfile_gb` | Non-negative integer | no, defaults to `0` |
| `login_users` | List of usernames, at least one | yes |
| `shared_secret` | Non-empty string | yes |
| `console_keymap` | Keymap name | yes |
| `timezone` | A timezone the live system reports | yes |
| `hostname` | Hostname | yes |
| `dotfiles.repository_url` | Repository URL | only inside `dotfiles` |
| `return_message` | The return message values, as defined in `../oparch-return-message-render/002-values-format.md` | no |

A key outside this list is an error, reported as `Unknown key in config file: <key>`. Unknown keys are refused rather than ignored, so a misspelled key cannot silently drop a setting. Inside `return_message` the same rule applies, with the keys that document defines, and inside `return_message.fields` it does not apply at all: the names there are the template's.

### Optional sections

A section that is absent turns its feature off:

- Without `dotfiles`, no dotfiles repository is cloned.
- Without `return_message`, there is no pre-boot return message, and nothing about it is read.
- Without `return_message.logo_url`, the message carries no logo.

There is no separate key stating whether a feature is enabled.

### Values

Every value that is text must be written as text. A value YAML would read as a number, a boolean or a date has to be quoted, and is refused otherwise:

```yaml
    phone: "+34 666 555 666"
```

The error names the key, says what YAML made of the value, and what to do:

```text
return_message.fields.phone must be quoted: YAML read it as a number, not as text. Wrap the value in double quotes.
```

The value itself is never repeated back, because what the installer received is already the canonical form of what YAML decided: echoing it would suggest exactly the value that was lost.

Usernames are one to thirty-two characters, start with a lowercase letter or `_`, and contain only lowercase letters, digits, `_` and `-`. The name `system` is reserved. Repeated names in a list are kept once, in first-seen order.

Hostnames are one to sixty-three characters, start with a letter or digit, and contain only letters, digits, `.` and `-`.

### Validation against the live system

Before anything is installed, the configuration is checked against the machine it will run on:

- `disk` must be an existing block device.
- `timezone` must be one of the timezones the live system reports, which is the same list the interactive screen offers.
- The return message values are checked against their template package, as that format defines.

The first problem found stops the run, and nothing is executed.

## Why

- YAML is used because the return message carries fields whose names come from the template rather than from the installer, and a flat key list cannot express that without inventing a prefix convention.
- Lists are written as YAML sequences because the previous format had to encode them as comma-separated strings, which needed its own parsing and its own errors for something the file format already expresses.
- A missing section means the feature is off, rather than a separate key saying so, because two ways of expressing the same thing can disagree; a file that says the return message is disabled while carrying its fields has no obvious meaning, and the previous format had to define which one won.
- Unknown keys are refused because a configuration file is written by hand; a silently ignored key would install something other than what the file describes.
- The return message section is the values format rather than a copy of it, because the same values are read by `oparch-return-message-render` on an installed system; two shapes for one thing drift apart.
- A text value YAML would read as a number is refused rather than converted, because converting it back to text gives the number's canonical form and not what was written: `+34666555666` loses its `+`, and `1.10` its trailing zero, with nothing failing. A quoted value is one keystroke; a phone number that silently loses its country prefix is discovered when someone cannot call it.
- Values are validated against the live system rather than only against their own syntax, because a well-formed file can still name a disk, a timezone or a template that does not exist.
- The file is validated completely before execution starts, because a configuration error found halfway through leaves a partially installed disk.

## Considerations

- The file holds `shared_secret` in clear text. A file used for a real installation is as sensitive as the passphrase it contains, because that one secret unlocks the disk and every login user.
- A file written for one machine is not portable to another without review: `disk` names a device, and `console_keymap` and `timezone` describe where the machine is used.
- The template package is fetched during validation, so a file naming a template by URL only works where that URL is reachable.
