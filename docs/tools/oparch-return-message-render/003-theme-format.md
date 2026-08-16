# Return Message Theme Format

## Context

The pre-boot return message is rendered to an image, as decided in [Pre-Boot Ownership Message](../../decisions/009-preboot-ownership-message.md). What that message says is defined by a template package, in [Return Message Template Package Format](001-template-package-format.md), and which values fill it by [Return Message Values Format](002-values-format.md). Neither says anything about what the result looks like: presentation is deliberately absent from both.

A theme is what says it. It carries the typography, the colours, the panels, the spacing and the arrangement of the languages, and nothing else. `oparch-return-message-render` builds the images from a template package, a set of values and a theme.

The operator may supply their own theme, so the format is what a person writes by hand, and a theme may be fetched from a URL exactly as a template package may.

## Specification

### What a theme decides, and what it does not

A theme decides everything visible except the words and the logo.

It does not define the message text or the language names, which belong to the template package; which languages are shown or what the fields say, which belong to the values file; the logo image, which is given to the tool by whoever calls it; or the wording of the password prompt, which belongs to the tool and is English by [Localization and Time](../../decisions/005-localization-and-time.md).

### The package

A theme is a directory:

```
<theme>/
  manifest.yaml
  fonts/               optional
    icons.ttf
  background.png       optional
```

`manifest.yaml` declares the theme. `fonts/` holds font files the theme brings with it. Any other file is only meaningful if a key names it.

A theme is given from any of the origins [Installer Input Sources](../oparch-installer/003-input-sources.md) defines. An archive is extracted into a directory the installer chooses, and entries that would land anywhere else are refused before extraction. This is the delivery defined for template packages in [Return Message Template Package Format](001-template-package-format.md), unchanged.

### Version

`version` declares the revision of this format, not the version of the tool that reads it. Its compatibility rules are the ones defined for the map version in [Dotfiles Map Format](../oparch-dotfiles-sync/001-map-format.md): a major increment is incompatible, a minor increment is strictly additive, an unimplemented revision is rejected during validation rather than interpreted, and major `0` carries no compatibility guarantee.

The format is at `0.1` and stays in major `0` until the distribution is released.

### Values, names and references

- A **name** — of a colour, a font or a style — is lowercase letters, digits and `_`, starting with a letter. This is the rule field names follow in [Return Message Template Package Format](001-template-package-format.md).
- A **colour** is written `"#RRGGBB"` or `"#RRGGBBAA"`, quoted. Without quotes YAML reads `#` as the start of a comment.
- A **number** is an integer greater than zero, except `size` and `fit`, which are decimals.
- **Every key is required** unless it is marked optional here. A theme has no defaults: what it does not say, it does not have. The project ships a complete theme, which is what is used when no other is given.
- A key outside the list its section defines is an error.
- Every colour is a name declared in `palette`, and every font a name declared in `fonts`. A colour or a font written as a literal anywhere else is an error.

### palette

```yaml
palette:
  ink: "#E8EEF4"
  accent: "#8FC2FF"
  panel: "#12202CE6"
  edge: "#25415A"
```

A mapping of name to colour. At least one entry.

### fonts

```yaml
fonts:
  sans:  { family: "Noto Sans" }
  icons: { file: "fonts/icons.ttf" }
```

A mapping of name to one font. An entry declares exactly one of:

| Key | Value |
| --- | --- |
| `family` | The name of a family already present on the machine |
| `file` | Path of a font file inside the package |

Declaring both, or neither, is an error.

With `file`, the font travels inside the theme and the tool makes it available while it draws, without installing it on the system. Its family name is read from the file itself, so there is nothing to declare and nothing to get wrong.

A family the theme does not bring must be present on the machine. Text is drawn through a text engine that substitutes another family for any writing system the chosen one does not cover, so a template in a script the theme did not anticipate still renders.

### styles

```yaml
styles:
  regular:     { font: sans, color_palette: ink, size: 1.0, weight: regular, slant: upright, align: left }
  title:       { extends: regular, color_palette: accent, size: 1.25, weight: bold }
  centered:    { extends: regular, align: center }
  value:       { extends: regular, color_palette: accent, weight: bold }
  accent_icon: { extends: regular, font: icons, color_palette: accent, size: 1.2 }
```

A mapping of name to one text style.

| Key | Value | Required |
| --- | --- | --- |
| `extends` | Name of another style, whose values fill in what this one does not declare | no |
| `font` | Name declared in `fonts` | yes, unless inherited |
| `color_palette` | Name declared in `palette` | yes, unless inherited |
| `size` | Decimal greater than zero, relative to the body size | yes, unless inherited |
| `weight` | `light`, `regular`, `medium`, `semibold` or `bold` | yes, unless inherited |
| `slant` | `upright` or `italic` | yes, unless inherited |
| `align` | `left`, `center` or `right` | yes, unless inherited |

`extends` may chain. A name that is not declared is an error, a cycle is an error, and a style still missing a key once its chain is resolved is an error. There is no implicit inheritance: `extends` is the only way a style takes a value from another.

`size` is never a point size. The body size is derived from `canvas.body_size_ratio` and the width of the block the text falls in, and `size` multiplies it.

### elements

```yaml
elements:
  language_heading_style: title
  body_style: regular
  password_prompt_style: centered
```

The three texts the tool draws, each naming the style it is drawn with.

| Key | What it draws | Where |
| --- | --- | --- |
| `language_heading_style` | The language's own name, as the template package's manifest declares it | At the top of that language's panel |
| `body_style` | That language's message, with its fields substituted and its unanswered optional regions removed | Below the heading, in the same panel |
| `password_prompt_style` | The line asking for the password | In `password-prompt.png` |

The heading is above the message. A theme does not reorder them.

### kinds

```yaml
kinds:
  phone:   { text_style: value, icon_glyph: "\uE001", icon_style: accent_icon }
  email:   { text_style: value, icon_glyph: "\uE002", icon_style: accent_icon }
  address: { text_style: value }
```

How a substituted value is decorated, by the `kind` its field declares in the template package. The section is optional, and so is every entry in it.

| Key | Value | Required |
| --- | --- | --- |
| `text_style` | Name declared in `styles`, used for the value itself | no |
| `icon_glyph` | The characters drawn before the value | no |
| `icon_style` | Name declared in `styles`, used for the glyph | no |

The key of an entry is one of the five kinds the template package format defines: `text`, `phone`, `email`, `address`, `url`. Any other key is an error. `icon_glyph` and `icon_style` are declared together; one without the other is an error.

A value whose kind has no entry, or an entry without `text_style`, is drawn with the body style. Without an icon, nothing precedes it. An icon is separated from its value by one space.

An icon is a glyph, drawn inside the running text, so a theme that wants its own icons brings the font that has them and names their code points here.

### password_mask

```yaml
password_mask: { shape: circle, size: 96, color_palette: ink }
```

The glyph drawn once for each character typed into the password prompt, written as `password-mask.png`.

| Key | Value |
| --- | --- |
| `shape` | `circle` or `square` |
| `size` | The side of the image, in canvas pixels |
| `color_palette` | Name declared in `palette` |

It is a drawn shape and not a character, which [Pre-Boot Ownership Message](../../decisions/009-preboot-ownership-message.md) requires.

### language_panel and password_prompt_panel

```yaml
language_panel:        { fill_palette: panel, border: { color_palette: edge, width: 4 }, corner_radius: 32, padding: 64 }
password_prompt_panel: { fill_palette: panel, border: { color_palette: edge, width: 0 }, corner_radius: 24, padding: 48 }
```

The two rectangles drawn behind something. `language_panel` is the one behind a single language — its heading and its message together — so there is one per cell of the arrangement. `password_prompt_panel` is the one behind the password prompt.

| Key | Value |
| --- | --- |
| `fill_palette` | Name declared in `palette` |
| `border.color_palette` | Name declared in `palette` |
| `border.width` | Canvas pixels; `0` is no border |
| `corner_radius` | Canvas pixels; `0` is square corners |
| `padding` | Canvas pixels between the text and the inside of the border |

A fill is a colour and nothing else. Transparency is a colour with an alpha component.

The prompt's panel is as wide as the text it holds plus its padding, and is placed across the width of `password-prompt.png` according to the alignment of the prompt's style.

### canvas

```yaml
canvas: { width: 3840, row_gap: 96, column_gap: 96, body_size_ratio: 0.0215 }
```

| Key | Value |
| --- | --- |
| `width` | The width the message and the prompt are composed at |
| `row_gap` | Space between the rows of the arrangement |
| `column_gap` | Space between the cells of a row |
| `body_size_ratio` | The body's point size as a fraction of the inner width of the block it falls in |

`width` is chosen above any display the message is expected to meet, so that the boot splash always scales the composition down. Enlarging is what turns text into a blur; reducing never does.

The inner width of a cell is its width less twice the sum of `language_panel.border.width` and `language_panel.padding`. For the prompt, it is `canvas.width` less twice the sum of the equivalent values of `password_prompt_panel`.

### spacing

```yaml
spacing: { language_heading_gap: 32, line_gap: 12, paragraph_gap: 64 }
```

| Key | Value |
| --- | --- |
| `language_heading_gap` | Space between a language's name and its message |
| `line_gap` | Space between the lines of one paragraph |
| `paragraph_gap` | Space between paragraphs |

A blank line in a message body separates paragraphs and is drawn as `paragraph_gap`. A single line break separates lines within a paragraph and is drawn as `line_gap`. The template says what is separated; the theme says by how much.

### logo

```yaml
logo: { width: 1200, gap: 120, position: above }
```

The whole section is optional.

| Key | Value |
| --- | --- |
| `width` | The width of the box the logo is fitted into, keeping its proportions |
| `gap` | Space between the logo and the message |
| `position` | `above` or `below` the message |

A theme without this section draws no logo, which is what a theme designed around a fixed background needs. Giving the tool a logo while using such a theme is an error, not a silent discard.

### arrangement

```yaml
arrangement:
  "1": [[1]]
  "2": [[1], [1]]
  "3": [[1], [1, 1]]
  "4": [[1, 1], [1, 1]]
```

One entry per number of languages the theme accepts, and those entries are what the number of selected languages is checked against. At least one entry.

The number is written quoted, because it is the name of an entry rather than a quantity, and a mapping key is text.

Each entry is a list of **rows**, and each row a list of **column weights**. A weight is an integer greater than zero and states the share of the row's width that column takes, in proportion to the other weights in its row, once `column_gap` has been taken out between them. `[[1, 1]]` is two equal columns; `[[2, 1]]` is two thirds and one third; `[[3, 2, 2]]` is three columns of three, two and two sevenths. Every row is as wide as `canvas.width`.

The cells of all the rows of an entry must come to exactly the number that entry is keyed by.

Languages fill the cells in the order the values file lists them, row by row from the top and, within a row, from left to right. Every panel in a row is drawn to the height of the tallest one in that row.

A narrow column makes the text of that block smaller, because the body size follows the width of the block. That is the consequence of the weights a theme chooses, and the format does not prevent it.

### screen

```yaml
screen:
  background_palette: panel
  background_image: "background.png"
  fit: 0.85
  message_gap: 120
  mask_gap: 48
```

What the boot splash needs and the three images cannot carry.

| Key | Value | Required |
| --- | --- | --- |
| `background_palette` | Name declared in `palette`, painted behind everything, and without an alpha component | yes |
| `background_image` | Path of an image inside the package, scaled to cover the screen and centred over the colour | no |
| `fit` | Fraction of the limiting screen dimension the composition is scaled to, greater than `0` and at most `1` | yes |
| `message_gap` | Space between the message and the password prompt | yes |
| `mask_gap` | Space between the password prompt and the typed characters | yes |

The gaps are in canvas pixels, so they are reduced along with everything else.

There are no coordinates here, or anywhere else in this format, because the heights are not known when a theme is written: a message is as tall as its text, which changes with the language, with which fields were answered and with the width of its cell.

### How a message is drawn

The text of a template package is data and cannot carry markup. The markup is written by the tool: it escapes the text of the package, escapes each substituted value, and wraps the value in the style of its field's kind, preceded by its icon.

### Choosing a theme

A theme reaches the tool as a directory, through the `--theme` of [oparch-return-message-render](000-command.md), exactly as the template package arrives through `--template-package`. The values file names neither. Without the flag, the project's own theme is used. The theme is validated with the template package, before the installer touches the disk.

### Validation

A theme is rejected, with the first problem found, when:

- `manifest.yaml` is missing, is not valid YAML, or is not a mapping.
- `version` is missing, or its revision is one the tool does not implement.
- A key appears outside the list its section defines, or a required key is missing.
- A colour is not `#RRGGBB` or `#RRGGBBAA`, or is written unquoted.
- `screen.background_palette` names a colour that carries an alpha component.
- A name does not follow the rule for names.
- A colour or a font is written as a literal instead of a name.
- A name is referenced that is not declared in `palette`, `fonts` or `styles`.
- An `extends` names a style that is not declared, or forms a cycle.
- A style is still missing a key once its chain is resolved.
- An entry of `fonts` declares both `family` and `file`, or neither.
- A `file`, or `screen.background_image`, is not in the package or points outside it.
- A key of `kinds` is not one of the five kinds a template package declares.
- An entry of `kinds` declares `icon_glyph` without `icon_style`, or the other way round.
- `weight`, `slant`, `align`, `shape` or `position` is outside its list of values.
- A number that must be an integer greater than zero is not, or `fit` is not greater than `0` and at most `1`.
- `arrangement` declares no entry, an entry whose cells do not come to the number it is keyed by, or a weight that is not an integer greater than zero.
- The archive holds an entry that would be written outside the directory it is extracted into.

A theme is validated completely before anything is drawn, and nothing is written when any of this fails.

## Why

- A theme is delivered as a package, and by the same means as a template, because it is written by the same person and obtained the same way; if it had a delivery of its own, there would be two ways of bringing presentation onto a machine and one of them would be the one nobody tested.
- A theme is data with a closed schema, and never drawing instructions, because a theme may be fetched from a URL. A theme that could describe drawing operations would be a program, and fetching one would run it on the machine being installed — which is exactly what [Pre-Boot Ownership Message](../../decisions/009-preboot-ownership-message.md) refuses for template packages, and the reason applies unchanged to something with more control over the result.
- Colours and fonts are declared once and referenced by name, with literals refused rather than discouraged, because coherence is the only thing a theme exists to produce, and a colour written in seven places stops being one colour on the first edit. Refusing the literal is what leaves one way of writing it; allowing both would mean a reader has to check which is in use.
- `extends` is explicit because an implicit parent hides where a value came from: a reader of a style would have to know which style is the root, and know it is a root, before knowing what the style says.
- Sizes are relative to the body, and the body is a fraction of the block's width, because the width of a block changes with the arrangement. If sizes were point sizes, a theme would render well with two languages and unreadably with four, and nothing would say so.
- The measure is a fraction of a width rather than a count of characters because in a proportional font a character has no width. A count promises a precision it cannot keep, and it forces the tool to measure a font in order to guess at what the theme meant.
- The password mask is a drawn shape and not a character because the splash draws no text and the installed system carries no font for it; the previous implementation had to mask with asterisks because the font it did carry drew dots as empty boxes.
- An icon is a glyph and not an image because it is drawn inside running text, which wraps. An image would have to be placed at a position in a line, which means laying out the line by hand, which means losing the shaping and the font substitution that make non-Latin scripts render at all.
- The icon's glyph is declared for each kind rather than in a collection of its own because it differs by kind by definition — a phone and an address do not share one. What repeats is its style, and styles already have names.
- A panel is filled with a colour and not an image because a panel takes the size of its cell, and cells differ in size within one composition. Stretching an image to fit distorts its corners, so an image fill needs nine-slice scaling, which is a mechanism of its own for a case a colour, a radius and a border already cover.
- The screen background may be an image because it is not stretched to a cell: it covers a screen, which is one rule and the same rule every time.
- An alpha component is refused on `screen.background_palette`, rather than dropped, because there is nothing behind the bottom layer for it to show: a component that is written and then means nothing looks like it was used, which is the trap the values format avoids by refusing a field the package does not declare. It is worse here than there, because the panels of the same theme carry alpha that does work, so nothing in the file would tell a reader the one key where it counts for nothing from the ones where it counts.
- The theme declares which numbers of languages it accepts because only the theme knows which arrangements it has. A number fixed by the tool would refuse a theme built for five and accept one with no arrangement for four, and in both cases the tool would be deciding something it cannot see.
- Every key is required, and a theme has no defaults, because a theme with holes leaves the tool choosing. What the screen looks like would then be partly the theme's and partly the tool's, and reading the theme would not tell anyone which parts.
- A logo given to a tool whose theme draws none is an error because a value that is supplied and then dropped looks like it was used, which is the reason the values format refuses a field the package does not declare.
- There are no coordinates because the heights follow the content: a theme is written before anyone knows how long a message is, in how many languages, with which optional regions surviving.
- `fit` is a fraction of the limiting dimension rather than the whole screen because the margin has to come from somewhere and the boot splash has no layout engine to negotiate one. A composition scaled to the full screen ends its outermost line against the panel edge, which is where a display's own overscan or a bezel eats it.
- The tool that draws the images is also the one that writes `screen` into the boot splash, because it is the only thing that has the theme already fetched, resolved and validated. Anything else would have to obtain the same theme a second time to answer the same question, and the day the two disagree — a URL that moved, a validation only one of them runs — the screen would be painted for a theme that is not the one the images were drawn from.
- What is written into the script is numbers only, and never a name, a filename or a path the theme chose, because the script is executed. A theme fetched from a URL that could put text of its own into it would be a program again, which is the one thing this format exists to prevent.

## Considerations

- A theme may carry font files and a background image, so a theme fetched from a URL puts a binary in front of FreeType and ImageMagick. Template packages carry only text and never did. This is the cost of a format that can bring its own icons, and it is accepted rather than left implicit.
- The values of `screen` reach the boot splash as literals in its script. `oparch-return-message-render` writes them above the body of the Plymouth script the project ships, and installs the two as one file beside the images. The colour is written as its three components, each a fraction between `0` and `1`, and `background_image` becomes a `1` or a `0`; nothing else of the theme is written there.
- The project ships a complete theme, used when no other is given.
- For a given number of languages, a wide arrangement leaves the text larger than a tall one: the composition is scaled by whichever screen dimension limits it, so a tall composition on a wide screen is limited by its height and shrinks everything in it. Raising `body_size_ratio` does not answer that, because the taller image is scaled down by the same proportion.
- Gradients, and image fills for panels, are not in this revision. Both are additive, so either can arrive in a later minor one.
