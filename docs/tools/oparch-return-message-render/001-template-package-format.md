# Return Message Template Package Format

## Context

The pre-boot return message is defined by a template package rather than by the installer, as decided in `../../decisions/007-preboot-ownership-message.md`. A package carries the wording, in every language it offers, and declares the data that wording needs.

`oparch-return-message-render` builds the message from a package. The installer reads the same package to know which values to ask for. The operator may supply their own package, so the format is what a person writes by hand, and the project's own package is expected to grow to many languages.

## Specification

A package is a directory:

```
<package>/
  manifest.yaml
  ca.txt
  en.txt
  es.txt
  fr.txt
```

`manifest.yaml` declares the package. Every other file is the message in one language, named after that language's code.

A package is given as a local directory, or as a URL to a `tar` archive of that directory. The archive is extracted into a directory the installer chooses, and entries that would land anywhere else are refused.

### Manifest

```yaml
version: "1.0"
name: "Default OpinionatedArch message"
notice: "A message with no way to contact you cannot bring the device back."

fields:
  - name: "owner_name"
    label: "Owner name"
    kind: "text"
    required: true
  - name: "phone"
    label: "Phone number"
    kind: "phone"
    required: false

languages:
  - code: "es"
    name: "Español"
  - code: "ca"
    name: "Català"
```

Text values are quoted, and a value YAML would read as something other than text is refused, as in `../oparch-installer/001-config-file-format.md`.

`name` describes the package to the operator.

`notice` is shown on the screen where the package's fields are asked. It belongs to the package because what is worth warning about follows the wording: a package whose every contact field is optional has something to say that a package with one mandatory field does not. A package that declares no `notice` shows none.

### Version

`version` declares the revision of this format, not the version of the tool that reads it. Its compatibility rules are the ones defined for the map version in `../oparch-dotfiles-sync/001-map-format.md`: a major increment is incompatible, a minor increment is strictly additive, an unimplemented version is rejected during validation rather than interpreted, and major `0` carries no compatibility guarantee.

### Fields

Each entry of `fields` declares one value the installer asks for:

| Key | Value | Required |
| --- | --- | --- |
| `name` | Identifier used as the placeholder in message bodies | yes |
| `label` | Text shown to the operator when asking for the value | yes |
| `kind` | `text`, `phone`, `email`, `address` or `url` | no, defaults to `text` |
| `required` | Whether the message can be rendered without it | no, defaults to `true` |

Field names are lowercase letters, digits and `_`, and start with a letter.

The installer asks for the fields in the order the manifest declares them, and asks for nothing else.

`kind` does not change how a value is validated or asked for. It states what the value is, so that a renderer can present it accordingly.

### Languages

Each entry of `languages` declares one message:

| Key | Value | Required |
| --- | --- | --- |
| `code` | Two lowercase letters, unique in the package | yes |
| `name` | The language's own name, as shown on screen | yes |

The message for a language is the file named `<code>.txt` in the package directory. There is no key naming it: the code is the name. Nothing in a package refers to a file by path, so nothing in a package can reach outside it.

### Message bodies

A body is a plain-text file. It is the message in that language, and nothing else: no language name, no separators, no presentation.

A field is referenced as `{{field_name}}`. The reference is replaced by the value the operator gave. A reference to a field the manifest does not declare is an error.

Text between `[[` and `]]` is an optional region. When any field referenced inside it has no value, the whole region is removed, including the words around the reference. When every field inside has a value, the delimiters are removed and the text stays.

A region is what makes an optional field usable: the words that introduce a value have to disappear with it, and they are rarely a whole line of their own.

```text
Este dispositivo pertenece a {{owner_name}}.

Si lo encuentra:[[
llame a {{phone}}]][[
escriba a {{email}}]][[
devuélvalo a {{address}}]]

¡Muchas gracias!
```

Regions do not nest. There is no way to write a literal `{{` or `[[`: both sequences always mean what they mean here.

### The package is data

A body is text to be shown, never something to be executed. Its content is escaped wherever it is embedded, so a package obtained from a URL cannot introduce anything that runs during boot.

### Validation

A package is rejected, with the first problem found, when:

- `manifest.yaml` is missing, is not valid YAML, or is not a mapping.
- `version` is missing, or its revision is one the installer does not implement.
- A field declares no `name` or no `label`, or a `kind` outside the listed values.
- Two fields share a `name`, or two languages share a `code`.
- A language declares no `code` or no `name`.
- A language's `<code>.txt` is missing from the package.
- A body references a field the manifest does not declare.
- A body opens an optional region and does not close it, or nests one region inside another.
- The package declares no language, or no field.
- An archive holds an entry that would be written outside the directory it is extracted into.

The installer validates the package before asking anything, and before writing anything to disk.

## Why

- A package declares its own fields because the data a message needs follows its wording; when the fields were fixed by the installer, region-specific content had to be smuggled into a field that did not mean that.
- The manifest is mandatory rather than inferred from the placeholders because inferring gives no label to show the operator, no order to ask in, and no way to mark a field optional.
- Labels are part of the package because the operator is asked for a value by a program that knows nothing about the message; without a label the prompt can only show an identifier.
- `kind` exists because a renderer cannot tell a phone number from an address by looking at it, and decorating one differently from the other is exactly what a theme would do. It is declared now because adding it later would require updating every package already written.
- `kind` does not affect validation because a phone number's shape varies by country, and rejecting a valid number is worse than accepting an odd one on a screen whose purpose is to be read by a human.
- `kind` is declared once per field rather than at each reference in a body, because it is a property of the value and not of where it appears.
- A message lives in its own file because the project's package is expected to carry many languages, and a translation is contributed, reviewed and corrected one language at a time. Held in one file, every contribution would touch the same lines.
- A message file is found by the language's code, with no key naming it, because a name that can be written can be written wrongly, and a reference that can point anywhere has to be checked for where it points. There is nothing to write and nothing to check.
- A remote package travels as an archive extracted into a directory the installer chooses, with entries outside it refused, because that is the failure mode of unpacking anything from a network: an entry that escapes the destination writes wherever it likes.
- `notice` belongs to the package because what is worth warning about depends on the wording. A package whose contact fields are all optional can be filled in so that it says nothing useful, and only the package knows that.
- A message that says nothing useful is the responsibility of whoever configured it. The installer warns with the package's own words and does not refuse, because which combination of fields is useful is a property of the message, not something an installer can judge.
- The format is versioned because a package written for a later revision must be rejected with a reason rather than half-understood, and because packages are written by people who do not upgrade at the same time as the installer.
- An unanswered optional field removes an explicitly marked region rather than the line holding it, because the words that introduce a value are not reliably alone on a line; dropping a line removes too much when two channels share one, and leaves a dangling "or send an email to" when the wording continues after the reference.
- The author marks the region rather than the renderer inferring where a sentence ends, because inference has to guess and a guess is not predictable across languages that punctuate differently.
- There is no escape for a literal `{{` or `[[` because neither sequence occurs in the prose of a return message, and an escape is machinery for a case that does not arise. If one ever does, it is a format change with a version to carry it.
- A package is validated completely before the installer asks anything, because a broken package discovered after the operator has typed every answer wastes the work and, if discovered later still, leaves a partially installed disk.

## Considerations

- The project ships a default package, used when the operator supplies none.
- Whether a theme may decorate the rendered message, and how a package would select one, is not decided; it is listed in `../../remaining.md`. Nothing in this format prevents it: presentation is deliberately absent from packages.
- A package fetched from a URL is only usable where that URL is reachable at install time.
- Field names appear in the values file defined in `002-values-format.md`, so renaming a field in a package invalidates every file written for it.
