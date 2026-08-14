# oparch-return-message-render

## Description

`oparch-return-message-render` builds the pre-boot return message image from a template package and the values that fill it, and installs it where the boot splash reads it.

It reads the values that fill the template from `/etc/opinionatedarch/return-message.yaml`, written during installation and editable afterwards, and defined in `002-values-format.md`:

```yaml
languages:
  - "ca"
  - "es"
fields:
  owner_name: "Ivan"
  phone: "+376 000 000"
logo:
  origin: url
  location: "https://example.invalid/logo.png"
```

The template package, the theme and the logo are not resolved from that file: each reaches the tool as a path it is given. Working out where they come from — a directory, an archive, a repository — belongs to whoever calls it, as decided in `../oparch-installer/003-input-sources.md`.

It writes three images into `/usr/share/plymouth/themes/opinionatedarch/`:

| Image | What it is |
| --- | --- |
| `return-message.png` | the message, in every selected language |
| `password-prompt.png` | the line asking for the passphrase, in English |
| `password-mask.png` | one glyph, drawn once per typed character |

Each is composed at a fixed width, with its height following its content. The boot splash scales them by the same factor to fit the screen it finds and arranges them, so no image depends on the display it was built for and none needs to know where the others are placed.

Beside them it writes `opinionatedarch.script`, the script the splash runs: the values of the theme's `screen` section, written as literals, followed by the body the project carries in its assets. Why the splash is handed them rather than reading them is in `003-theme-format.md`.

What the three look like — typography, colours, panels, spacing and the arrangement of the languages — comes from a theme, given to the tool as a directory and defined in `003-theme-format.md`. The tool composes; the theme decides how.

The prompt is in English because the system's interface is English, as decided in `../../decisions/010-localization-and-time-policy.md`. A template package translates what a finder reads, not what the owner reads.

How many languages may be selected, and how they are arranged, is the theme's: it declares an arrangement for each number it accepts. What that arrangement should aim for is argued in `../../decisions/006-preboot-ownership-message.md` — a composition closer to the shape of a screen than to a column, because a tall composition on a wide screen is limited by its height and ends up small.

## Why is needed

The message has to exist as an image before the initramfs is built, and it has to be rebuilt whenever what it says changes: a new phone number, a different address, one language more.

Rendering it during installation only would mean that changing a phone number requires reinstalling. A tool that owns the rendering can be run again on an installed system, and the installer is one of its callers rather than its only one.

Building an image, rather than having the boot splash draw text, is decided in `../../decisions/006-preboot-ownership-message.md`. The short of it: the splash draws with one font and no fallback, so any writing system that font does not cover renders as blanks, and it cannot justify, wrap or emphasise.

## Requirements

What has to be installed where this runs. None of it is on the official Arch live medium, which is what makes this the list worth reading before a first run: the failures it prevents look like defects in the rendering.

- **ImageMagick**, for `magick` and `identify`. It composes every image and reads back the size of what it drew.
- **Pango**, as ImageMagick's delegate. The text is drawn through it, which is what makes markup, wrapping and per-value styling possible at all. On Arch `pango` is an *optional* dependency of `imagemagick` by that package's own metadata, so installing the one does not bring the other, and ImageMagick without it is an ImageMagick that draws no text.
- **The font family the theme names**, and a fallback for what it does not cover. The project's own theme names `Noto Sans`, and takes its icons from Noto Sans Symbols through fontconfig's substitution, so `noto-fonts` covers both. A theme that names another family needs that one instead.
- **`fontconfig`**, for `fc-scan`, when the theme carries a font of its own: the family a font file declares is read from the file rather than trusted from the manifest.

There is no BAML runtime library in this list. This tool has no host, so `baml pack` makes it a standalone binary — the distinction is `../../development/001-host-bridge.md`.

The commands are called by name and nothing checks for them first. What a missing one produces is the exit status of a command that is not there, reported as the drawing step that failed.

## Input parameters

- `--config <path>`: Optional. Read the values from this file instead of `/etc/opinionatedarch/return-message.yaml`.
- `--template-package <path>`: Optional. Directory holding the template package to compose, as defined in `001-template-package-format.md`. Default: the project's own, inside `--assets`.
- `--theme <path>`: Optional. Directory holding the theme to compose it with, as defined in `003-theme-format.md`. Default: the project's own, inside `--assets`.
- `--assets <path>`: Optional. Directory holding the project's own assets: the template package and the theme used when neither is given, and the body of the Plymouth script. Default: `/usr/share/opinionatedarch/assets`.
- `--output <path>`: Optional. Directory to write the images into. Default: `/usr/share/plymouth/themes/opinionatedarch`.
- `--logo <path>`: Optional. Image file to compose above the message. Without it the message carries no logo.

The template package, the theme and the logo all arrive as paths on the local filesystem, never as the place they came from. Obtaining them — cloning a repository, downloading and unpacking an archive, letting the operator pick a directory from disk — belongs to whoever calls this tool, which for a new installation is the installer. The tool itself therefore reaches no network and unpacks nothing.

The exit status is `0` when the images were written, and non-zero when the configuration, the template package or the rendering failed. Nothing is written when any of them does.

## Interactive usage

There is no interactive version. What the message says is declared in the configuration file, and the installer collects it through its own screens.

Changing the message on an installed system is editing that file and running the tool again, naming the template package and the theme the message was built with when they are not the project's own. The result takes effect on the next boot, with no initramfs rebuild: the images live in the theme, which the splash reads at boot.
