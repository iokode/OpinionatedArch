# Pre-Boot Ownership Message

## Context

The disk-unlock screen shown at boot can display an ownership-and-return message before the operating system starts. It is read by whoever finds a lost machine, on a screen with no operating system behind it.

The message wording, and the data it needs, vary by owner and by region. A message that names the local police force needs a field that another message has no use for.

## Decision

The installer asks whether this return message should be included. If it is disabled, the installer asks nothing further about it and does not configure the unlock screen for it.

### Template packages

The message is defined by a template package, not by the installer. A package contains:

- A manifest declaring the fields the message needs, each with a name, the label shown to the operator, and whether it is required.
- One message body per language, with the language's own name and the message text, referencing fields by placeholder.

The manifest is mandatory. The installer asks for exactly the fields the manifest declares, in the order it declares them, and for nothing else.

The operator may supply their own package, from a local directory or a URL. When none is supplied, the project's default package is used. The default package provides the message in several languages.

The message is shown in 1 to 4 languages, selected from those the package provides.

### The message is data

A template package is data. Its text is never executed, and it is escaped wherever it is embedded, so a package obtained from a URL cannot introduce anything that runs during boot.

### Rendering

The message is rendered to an image at install time and that image is what the unlock screen displays. Text is not drawn by the boot splash.

The rendered image is scaled proportionally and centred at boot, so it does not depend on the display it was rendered for. Margins keep the message from touching the screen edges; the horizontal margin governs line length and so is the one that matters for readability.

The composition is chosen from the number of selected languages, preferring a wide arrangement over a tall one: four languages are laid out as a grid rather than stacked, because a composition shaped like the screen leaves the text larger after scaling.

Language identity is shown from the language's own name, not from flags.

### The unlock screen

Everything the unlock screen shows is an image: the message, the prompt asking for the passphrase, and the glyph that marks each typed character. The boot splash draws no text, so the installed system carries no font for it.

The prompt is in English, and is not part of a template package. The system language is English, as decided in `011-localization-and-time-policy.md`; a template package translates what a finder reads, not what the owner reads.

The typed passphrase is masked with a repeated image rather than a character, so what marks a keystroke is drawn rather than looked up in a font.

### Logo

The screen may include a logo, asked for only when the return message is enabled. Its source is a URL, downloaded during installation and composed into the rendered image.

If the download fails, the installer must not continue silently. It asks whether to retry with a new URL or to continue deliberately without a logo.

### Validation

The template package is fetched, parsed and checked before anything is written to disk: that the manifest is well formed, that the selected languages exist in the package, and that every required field has a value.

Boot-time rendering is fully offline. Everything the unlock screen needs is local before the initramfs is built.

## Why

- Showing ownership-and-return text at pre-boot unlock is useful because a finder can read contact instructions immediately without needing OS access; if omitted, device return depends on external assumptions and recovery chance drops.
- Making the message optional is required because not every installation should publish contact data at pre-boot; if it is mandatory, privacy or deployment-specific preferences cannot be represented without editing installer code.
- Fields are declared by the template rather than fixed by the installer because the data a message needs follows its wording, which varies by owner and region; when the fields were fixed, region-specific content had to be smuggled into a field that did not mean that, such as naming a police force inside the return address.
- A manifest is mandatory rather than inferred from the placeholders because inferring gives no labels, no order and no way to mark a field optional, and because one predictable way of declaring fields is preferred over several that behave differently.
- Operator-supplied packages are required because the project cannot anticipate every wording; if only project templates exist, the only way to change the message is to change the project.
- Restricting selection to at most four languages is required because the screen must preserve readable contact text at early-boot resolutions; if too many languages are shown, each message becomes too small to scan quickly.
- Native language names are required because they identify the readable block without relying on political or regional symbols; if flags are used, the cue can be ambiguous or inappropriate.
- Template content is treated as data and escaped because the message ends up inside the boot splash's own theme; if it were interpolated as code, a package fetched from a URL would run arbitrary code during boot, before the disk is unlocked.
- Rendering to an image at install time is required because the boot splash draws text with a single font and no fallback or shaping, which silently fails for scripts that font does not cover; rendering on the live system uses a complete text engine, so any writing system works. It also allows formatting the splash cannot express.
- The prompt and the mask are images too, and not only the message, because a screen that still draws one line of text still needs a font installed for it, and that font still fails for what it does not cover. The mask is the case in point: it was written with asterisks because the bundled font drew dots as empty boxes.
- The prompt is in English because it is part of the system's interface, which is English, and not part of the message, which exists to be read by someone who did not choose this system.
- Proportional scaling with margins is required because the screen at boot is not necessarily the one the message was rendered for; if a fixed aspect ratio is assumed, the message is stretched or cropped on a docked display or a differently shaped panel.
- The composition is chosen by language count because the number of languages decides the shape of the message; a tall composition on a wide screen is limited by height and shrinks the text, while a composition shaped like the screen keeps it large. Enlarging the font instead does not help, because a taller image is scaled down by the same proportion.
- Downloading the logo only at install time is required because early boot has no network guarantees; if boot depends on remote retrieval, unlock can fail or degrade unpredictably.
- Logo download failure must trigger an explicit choice because URL typos are common and silent fallback hides configuration mistakes; if failure is silent, intended branding is lost without the operator knowing.
- Validating the package before the disk is touched is required because a message that cannot be built is a configuration error, and a configuration error found halfway through leaves a partially installed disk.

## Considerations

- Contact data is intentionally public on the pre-boot screen by design decision.
- The rendered message is an image, so it carries no selectable text. This is accepted: at this point there is no operating system and no assistive tooling, and what a finder sees is pixels either way.
- Changing the message on an installed system means rendering it again, which is why rendering is a tool of its own rather than installer-internal behaviour. That tool is `../tools/oparch-return-message-render/000-command.md`.
- If the boot splash fails, unlock must still fall back to a functional text-mode prompt.
- Runtime unlock must never fetch remote assets; everything must be local before the initramfs is built.
- Return-message readability must be validated on the real display resolutions used by the target machines.
- Whether a theme may decorate the rendered message, and what it would control, is not decided; it is listed in `../remaining.md`.

## Critical Notes With Replies (Copy of Discussion)

1. Assistant critique: a bigger default font would fix a message that renders too small.
   Reply: it would not, when the message is limited by height. A larger font makes the image taller in the same proportion, the scale factor drops in the same proportion, and the size on screen is identical. The composition, not the font size, is what changes the result.
