# oparch-return-message-render

## Description

`oparch-return-message-render` builds the pre-boot return message image from a template package and the values that fill it, and installs it where the boot splash reads it.

It reads its input from `/etc/opinionatedarch/return-message.yaml`, written during installation and editable afterwards. That file has the same shape as the `return_message` section of the installer's configuration file, defined in `../oparch-installer/001-config-file-format.md`:

```yaml
template: "https://example.invalid/andorra.tar"
languages:
  - "ca"
  - "es"
fields:
  owner_name: "Ivan"
  phone: "+34 666 555 666"
logo_url: "https://example.invalid/logo.png"
```

It writes three images into `/usr/share/plymouth/themes/opinionatedarch/`:

| Image | What it is |
| --- | --- |
| `return-message.png` | the message, in every selected language |
| `password-prompt.png` | the line asking for the passphrase, in English |
| `password-mask.png` | one glyph, drawn once per typed character |

Each is composed at a fixed width, with its height following its content. The boot splash scales them by the same factor to fit the screen it finds and arranges them, so no image depends on the display it was built for and none needs to know where the others are placed.

The prompt is in English because the system's interface is English, as decided in `../../decisions/011-localization-and-time-policy.md`. A template package translates what a finder reads, not what the owner reads.

When more than one language is selected, they are arranged to keep the composition closer to the shape of a screen than to a column: four languages are laid out as a grid rather than stacked. A tall composition on a wide screen is limited by its height and ends up small.

## Why is needed

The message has to exist as an image before the initramfs is built, and it has to be rebuilt whenever what it says changes: a new phone number, a different address, one language more.

Rendering it during installation only would mean that changing a phone number requires reinstalling. A tool that owns the rendering can be run again on an installed system, and the installer is one of its callers rather than its only one.

Building an image, rather than having the boot splash draw text, is decided in `../../decisions/007-preboot-ownership-message.md`. The short of it: the splash draws with one font and no fallback, so any writing system that font does not cover renders as blanks, and it cannot justify, wrap or emphasise.

## Input parameters

- `--config <path>`: Optional. Read the values from this file instead of `/etc/opinionatedarch/return-message.yaml`.
- `--assets <path>`: Optional. Directory holding the project's own template package, used when the configuration names no template. Default: `/usr/share/opinionatedarch/assets`.
- `--output <path>`: Optional. Directory to write the images into. Default: `/usr/share/plymouth/themes/opinionatedarch`.

The exit status is `0` when the images were written, and non-zero when the configuration, the template package or the rendering failed. Nothing is written when any of them does.

## Interactive usage

There is no interactive version. What the message says is declared in the configuration file, and the installer collects it through its own screens.

Changing the message on an installed system is editing that file and running the tool again. The result takes effect on the next boot, with no initramfs rebuild: the images live in the theme, which the splash reads at boot.
