# Return Message Values Format

## Context

A template package declares what the return message says and which values it needs. Those values are what one owner puts into it: their name, the ways to reach them, the languages they want shown.

`oparch-return-message-render` reads them from a file, so that changing the message on an installed system is editing that file and running the tool again.

The installer collects the same values through its screens and carries them in the `return_message` section of its own configuration file. That section is this format, embedded, together with the origins of the template package and the theme — which the installer resolves, and which this file never names.

## Specification

The file is YAML. It lives at `/etc/opinionatedarch/return-message.yaml` unless the tool is told otherwise.

```yaml
languages:
  - "ca"
  - "es"

fields:
  owner_name: "Ivan"
  phone: "+376 000 000"
  address: "Carrer de la Unió, Andorra"

logo:
  origin: url
  location: "https://example.invalid/logo.png"
```

### Keys

| Key | Value | Required |
| --- | --- | --- |
| `languages` | Language codes the package provides, as many as the theme accepts | yes |
| `fields` | Values for the fields the package declares | yes |
| `logo.origin` | `url` or `local` | only inside `logo` |
| `logo.location` | Where the logo was taken from: a URL, or a path | only inside `logo` |

A key outside this list is an error. Inside `fields` this does not apply: the names there belong to the package, as defined in `001-template-package-format.md`.

The file does not name the template package or the theme. They reach the renderer as directories, through the `--template-package` and `--theme` of `000-command.md`, resolved by whoever calls it — as decided in `../oparch-installer/003-input-sources.md`.

Text values are quoted, and a value YAML would read as something other than text is refused, as in `../oparch-installer/001-config-file-format.md`. A field value written as `+376000000` would come back without its `+`, so it is refused rather than converted.

Without `logo`, the message carries no logo. There is no separate key stating whether one is included.

`logo` states where the logo was taken from; it is not what the renderer reads. The renderer is given the file, through the `--logo` of `000-command.md`, by whoever resolved this key into one.

### Validation

The values are checked against the package and the theme they are rendered with:

- The package and the theme must be readable and valid.
- Every code in `languages` must be one the package provides.
- How many codes `languages` holds must be a number the theme declares an arrangement for.
- Every field the package declares as required must have a value.
- A field named here that the package does not declare is an error, because it would silently do nothing.

Nothing is rendered when any of these fails.

## Why

- The values live in a file rather than in command arguments because the field names come from the package and are not known in advance; arguments would have to be invented per package.
- The package and the theme are arguments rather than keys of this file, even though the values are a file, because they are not values: they are inputs the renderer needs to already exist. A key naming a location would have to be resolved, and resolving it means fetching, unpacking or cloning inside a tool whose work is composing an image.
- What the installer carries in its configuration is this format plus those two origins, rather than a shape of its own, because the values themselves are the same values; two shapes for one thing drift apart and one of them ends up wrong.
- A field named here that the package does not declare is refused rather than ignored, because a value that is typed and then dropped looks like it was used.
- The file is read at render time rather than baked into the image's own metadata because the point of the file is to be edited: a new phone number is a change to this file and a re-run, not a reinstallation.
- How many languages may be listed is not a number this format sets because the theme is what has to lay them out, as argued in `004-themes.md`; a number fixed here would refuse a theme that can do more and accept one that cannot do what it allows.
- The renderer is given the logo as a file rather than fetching this URL itself because a download that fails is a question — retry with another URL, or go on without one — and only something that can ask the operator may answer it. A renderer that fetched the URL could only guess, and a guess here either loses the branding silently or refuses to rebuild a message over an unrelated address.

## Considerations

- The file does not name the package its values were written for. Renaming a field in that package invalidates them, and the error names the field; rendering the same file with a different package is not prevented, only reported when a field does not fit.
- The file holds contact data that is published on the pre-boot screen by design, so it is not secret. It is not, however, the place for anything that is.
