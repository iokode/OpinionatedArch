# Pre-Boot Ownership Message

## Context

The disk-unlock screen shown at boot can display an ownership-and-return message before the operating system starts. It is read by whoever finds a lost machine.

## Decision

The return message is optional. When enabled, it is shown at the disk unlock prompt.

### The message

The wording of the message, the languages it offers and the data it needs are not fixed by this project: they come from a template package, which the operator may supply and which the project ships one of. Its format is [Return Message Template Package Format](../tools/oparch-return-message-render/001-template-package-format.md).

A package is data. Nothing in it is executed, and its text is escaped wherever it is embedded, so a package obtained from a URL cannot introduce anything that runs during boot.

The message is shown in the languages the operator selects.

### Rendering

The message is rendered to images, and those images are what the unlock screen displays.

The rendered images reach the edges of the screen. Their content does not: the renderer composes them with a margin around it.

What the message looks like, and how the languages are arranged, are the theme's, as decided in [Return Message Themes](../tools/oparch-return-message-render/004-themes.md).

Everything the unlock screen needs is on the machine before the initramfs is built. Nothing is fetched at boot.

### The unlock screen

The message, the prompt asking for the passphrase and the glyph that marks each typed character are all images. The boot splash draws no text, so the installed system carries no font for it.

The prompt is in English, and is not part of a template package. The system language is English, as decided in [Localization and Time](005-localization-and-time.md); a template package translates what a finder reads, not what the owner reads.

The prompt asks for the secret and names nothing else. It does not say that a disk is being unlocked, and it does not call the secret a passphrase.

The typed passphrase is masked with a repeated image rather than a character, so what marks a keystroke is drawn rather than looked up in a font.

If the boot splash fails, unlock still falls back to a text-mode prompt.

## Why

- The message is on the unlock screen because that is as far as whoever finds the machine gets: everything behind it is encrypted, so a screen that says nothing leaves them with a device and no way to return it.
- The message is optional because not every machine should publish contact data where anyone who picks it up reads it, and having a machine without one must not mean changing the project.
- The message comes from a package rather than from this project because its wording, and the data that wording needs, vary by owner and by region: a message that names the local police force needs a field another message has no use for. A project that fixed them would be the only place either could change.
- Template content is treated as data and escaped because the message ends up inside the boot splash's own theme; if it were interpolated as code, a package fetched from a URL would run arbitrary code during boot, before the disk is unlocked.
- The message is rendered to an image because the boot splash draws text with a single font and no fallback or shaping, which silently fails for scripts that font does not cover; the live system has a complete text engine, so any writing system works, and formatting the splash cannot express becomes possible.
- The prompt and the mask are images too, and not only the message, because a screen that still draws one line of text still needs a font installed for it, and that font still fails for what it does not cover. The mask is the case in point: it was written with asterisks because the bundled font drew dots as empty boxes.
- The prompt is in English because it is part of the system's interface, which is English, and not part of the message, which exists to be read by someone who did not choose this system.
- The prompt names neither the disk nor the passphrase because this screen is the one screen of the system that anyone who picks the machine up will see, and the owner is the only person it has anything to tell. Whoever else is reading is being told, for nothing, that the machine is encrypted and that what is being typed is the key to it; the owner already knows what to type.
- A background image is meant to reach every edge; text laid over it is not. So the margin goes around the content, and the renderer leaves it when it composes the image.

## Considerations

- Contact data is intentionally public on the pre-boot screen.
- The rendered message is an image, so it carries no selectable text. This is accepted: at this point there is no operating system and no assistive tooling, and what a finder sees is pixels either way.
- Changing the message on an installed system means rendering it again with [oparch-return-message-render](../tools/oparch-return-message-render/000-command.md).
- Return-message readability must be validated on the real display resolutions used by the target machines.
- What the rendered message looks like is a theme's, decided in [Return Message Themes](../tools/oparch-return-message-render/004-themes.md).

