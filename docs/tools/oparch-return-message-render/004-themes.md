# Return Message Themes

## Context

The pre-boot return message is rendered to an image, as decided in `../../decisions/006-preboot-ownership-message.md`. What it says comes from a template package, and the values that fill it from a values file. Presentation is deliberately absent from both: a package carries wording, in every language it offers, and nothing about how that wording looks.

Until now nothing carried it. The look lived in the renderer — one font, one set of colours, one arrangement for each number of languages, all of them constants in its source. An operator who wanted the message to look like anything else had to change the tool.

`007` left the question open and `../remaining.md` recorded it: whether the rendered message may be decorated by something supplied the way a template is, and what such a thing may control.

## Specification

The message is drawn from a **theme**. Its format is `003-theme-format.md`.

### What a theme is

A theme is a package, obtained exactly as a template package is, from any of the origins `../oparch-installer/003-input-sources.md` defines: a directory or a `tar` archive on the machine, an archive by URL, or a repository. An archive has its entries listed and refused before extraction if any would land outside the destination. The operator may supply their own. The project ships one, chosen when no other is.

A theme reaches the renderer as a directory it is given, through `--theme`, beside the `--template-package` that carries the package. Which theme that is, and where it came from, is asked by whoever calls the renderer — the installer, through the screen defined in `../oparch-installer/002-inputs-and-bootstrap-baseline.md`.

### What a theme controls

Everything visible except the words and the logo.

It does not define the message text or the language names, which are the template package's; which languages are shown or what the fields say, which are the values file's; the logo image, which is given to the tool by whoever calls it; or the wording of the password prompt, which is the tool's.

It does define the typography, the colours, the panels behind each language and behind the prompt, the spacing, the shape of the glyph that marks a typed character, the decoration applied to a field according to its `kind`, the arrangement of the languages, and what the boot splash paints behind everything.

### A theme is data

A theme is data with a closed schema. It fills a fixed set of named slots that the renderer knows about. It never carries drawing instructions, and nothing in it is executed.

Colours and fonts are declared once, by name, and referenced by that name. A colour or a font written as a literal anywhere else is refused rather than accepted.

A theme may carry font files, so that it can bring its own icons, and one image for the screen background.

### How many languages

The theme declares which numbers of languages it accepts, by declaring an arrangement for each. That is what the number of selected languages is checked against.

This replaces the fixed limit of four that `007` set.

### Validation

A theme is validated completely, with the template package and the values, before anything is drawn and before the installer touches the disk. Nothing is written when any of it fails.

## Why

- Presentation is moved out of the renderer because it is the part of this that varies by owner and by taste, and the renderer is the part that does not; while the look lived in the source, changing a colour meant changing the tool, and every installation that wanted a different one carried a fork.
- A theme is a package delivered like a template package because it is written by the same person and obtained the same way; if it had a delivery of its own, there would be two ways of bringing presentation onto a machine, and the machinery that refuses an archive entry pointing outside its destination would have to exist twice.
- A theme is data with a closed schema, and never drawing instructions, because a theme may be fetched from a URL. Something that could describe drawing operations would be a program, and fetching one would run it on the machine being installed. `007` refuses exactly that for template packages, and the reason is stronger here: a theme has more control over the result, so it would have more reason to want it.
- Colours and fonts are referenced by name, with literals refused, because coherence is the only thing a theme exists to produce, and a colour written in seven places stops being one colour at the first edit. Refusing the literal, rather than discouraging it, is what leaves one way of writing it.
- A theme may carry fonts because an icon drawn beside a phone number has to come from somewhere, and it is drawn inside running text, which wraps: it must be a glyph, and a glyph the system does not have must arrive with the theme that asks for it.
- The number of languages is the theme's because only the theme knows which arrangements it has. A number fixed by the tool refuses a theme built for five and accepts one that has no arrangement for four, and in both cases the tool decides something it cannot see.
- The readability that the fixed limit of four protected is not abandoned with it: it is now a property of the arrangement and the sizes a theme chooses, which is where it belongs, since those are what decide how large each message ends up on the screen.
- The theme is validated with the package rather than at the moment each value is used, because a theme that cannot be read is a configuration error, and a configuration error found halfway through leaves a partially installed disk. This is the rule `007` already sets for template packages.

## Considerations

- A theme may carry font files and a background image, so a theme fetched from a URL puts a binary in front of FreeType and ImageMagick. A template package carries only text and never did. This is the cost of a format that can bring its own icons and its own background, and it is accepted rather than left implicit.
- A theme's screen values reach the boot splash as a generated prelude: the renderer writes them as numeric literals above the static script the project carries, and the two together are what the splash runs. It is specified in `000-command.md`. It works that way because a boot splash script cannot read them for itself — values declared for it arrive as text and its language cannot make a number of text — and it is the renderer that writes them because it is the only thing that has the theme read and validated. Only numbers cross: nothing a theme or a template package wrote as text is ever emitted into the script.
- Return-message readability still has to be validated on the real display resolutions used by the target machines, as `007` already requires. A theme makes that easier to correct and does not make it unnecessary.
