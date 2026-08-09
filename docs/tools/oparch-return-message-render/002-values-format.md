# Return Message Values Format

## Context

A template package declares what the return message says and which values it needs. Those values are what one owner puts into it: their name, the ways to reach them, the languages they want shown.

`oparch-return-message-render` reads them from a file, so that changing the message on an installed system is editing that file and running the tool again.

The installer collects the same values through its screens and carries them in the `return_message` section of its own configuration file. That section is this format, embedded.

## Specification

The file is YAML. It lives at `/etc/opinionatedarch/return-message.yaml` unless the tool is told otherwise.

```yaml
template: "https://example.invalid/andorra.tar"

languages:
  - "ca"
  - "es"

fields:
  owner_name: "Ivan"
  phone: "+34 666 555 666"
  address: "Carrer de la Unió, Andorra"

logo_url: "https://example.invalid/logo.png"
```

### Keys

| Key | Value | Required |
| --- | --- | --- |
| `template` | Directory or URL of a template package | no, defaults to the project's package |
| `languages` | One to four language codes the package provides | yes |
| `fields` | Values for the fields the package declares | yes |
| `logo_url` | URL of a logo to compose into the message | no |

A key outside this list is an error. Inside `fields` this does not apply: the names there belong to the package, as defined in `001-template-package-format.md`.

Text values are quoted, and a value YAML would read as something other than text is refused, as in `../oparch-installer/001-config-file-format.md`. A field value written as `+34666555666` would come back without its `+`, so it is refused rather than converted.

Without `logo_url`, the message carries no logo. There is no separate key stating whether one is included.

### Validation

The values are checked against the package they are for:

- The package must be reachable and valid.
- Every code in `languages` must be one the package provides.
- Every field the package declares as required must have a value.
- A field named here that the package does not declare is an error, because it would silently do nothing.

Nothing is rendered when any of these fails.

## Why

- The values live in a file rather than in command arguments because the field names come from the package and are not known in advance; arguments would have to be invented per package.
- The file is the same shape the installer carries in its configuration, rather than a translation of it, because two shapes for one thing drift apart and one of them ends up wrong.
- A field named here that the package does not declare is refused rather than ignored, because a value that is typed and then dropped looks like it was used.
- The file is read at render time rather than baked into the image's own metadata because the point of the file is to be edited: a new phone number is a change to this file and a re-run, not a reinstallation.

## Considerations

- The file names the template package. Renaming a field in that package invalidates the values written for it, and the error names the field.
- The file holds contact data that is published on the pre-boot screen by design, so it is not secret. It is not, however, the place for anything that is.
