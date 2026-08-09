# Dotfiles Sync

## Context

The `/dotfiles` directory is the shared source of configuration for all intended login users.

## Specification

`/dotfiles` is intended to be kept under version control, but no specific system is required and version control is not mandatory. Neither the map format nor `oparch-dotfiles-sync` inspects, requires, or depends on version control metadata.

It should contains a mapping file that declares how dotfiles will be synced. The map is a declarative syntax file. It is not a shell file and cannot execute commands.

### Map Syntax

The default map path is `/dotfiles/main.dfmap`. The file extension means "Dotfiles Map".

Example:

```text
oparch dotfiles map
version = '0.1'

include 'common.dfmap'
include 'hosts/desktop.dfmap' for host 'desktop'
include 'hosts/laptop.dfmap' for host 'laptop'

[packages]
hyprland
uwsm

[aur-packages]
opencode

[values.github]
# At work, I use a different github account created by the company.
username = 'personal-account' for user 'personal'
username = 'work-account'     for user 'work'

[secrets.github]
# Due I use different github accounts, the personal access token is different by user (work context).
token with scope 'user'

[dotfiles.hypr]
link 'hypr/keybindings.lua' to '&HOME/.config/hypr/keybindings.lua'
link 'hypr/monitors_desktop.lua' to '&HOME/.config/hypr/monitors.lua' for host 'desktop'
link 'hypr/monitors_laptop.lua' to '&HOME/.config/hypr/monitors.lua' for host 'laptop'
link 'hypr/animations.lua' to '&HOME/.config/hypr/animations.lua' except host 'laptop' # My laptop is not enough powerful, so I disable animations on it.

[dotfiles.opencode]
link 'opencode/agent/' to '&HOME/.config/opencode/agent/'
render 'opencode/mcp/common.conf.tpl' + 'opencode/mcp/github.conf.tpl' to '&HOME/.config/opencode/mcp.conf' with mode '0600'

[dotfiles.boot]
copy 'grub/' to '/boot/'
```

Syntax rules:

- Empty lines are ignored.
- Lines beginning with `#` are comments.
- Inline comments begin at `#` and continue to the end of the line.
- The first line is the fixed header `oparch dotfiles map`, at the very start of the file; nothing may precede it, not even a comment or blank line.
- A `version` entry is mandatory and must follow the header, before any include or section.
- Top-level include entries may appear after the `version` entry and before sections.
- A section starts with a section header and ends at the next section header or end of file.
- Sections are not nested and do not use closing headers.
- A section name may appear more than once, within one file or across included files.
- Repeated `[values.<category>]` and `[secrets.<category>]` occurrences accumulate keys into the one `<category>.<key>` namespace.
- Repeated `[dotfiles.<category>]` are different categories.
- Every entry must fit on one physical line. Line continuation is not supported.
- Paths, values, the version number, user and host names in selectors, and option values such as `scope`, `mode`, and `ownership` are wrapped in single quotes.
- A single quote inside a quoted value is escaped as `\'`.
- Shell variables and shell expressions are not expanded.
- Unknown sections, operations, options, selectors, and placeholders are invalid.
- Declaration order does not affect the resulting plan: includes, operations, value definitions, packages, and other entries may appear in any order. The one exception is the left-to-right order of sources within a single `render` composition.
- Two active operations that expand to the same target are invalid.

### File Header

Every map file begins with the fixed line:

```text
oparch dotfiles map
```

It is the first line, at byte zero, with nothing before it — no comment and no blank line. The header identifies the format by content rather than by name, so `oparch-dotfiles-sync` rejects a file that does not start with it before parsing anything, and `file(1)` can recognize it from a single magic rule:

```text
0 string oparch\ dotfiles\ map OpinionatedArch dotfiles map
```

### Map Version

The `version` entry declares the revision of the map format. It does not declare the version of the tool.

A version is `<major>.<minor>`.

Compatibility is semantic:

- A `major` increment is an incompatible change: removing or renaming a construct, changing what an existing rule does, or tightening validation so a previously valid map becomes invalid.
- A `minor` increment is strictly additive: a new optional section, operation, selector, or placeholder. Every map valid under an earlier minor of the same major stays valid and keeps its meaning.

A map is accepted only when the tool implements the map's major and the map's minor is less than or equal to the highest minor the tool implements for that major.

Version rules are:

- A map whose major the tool does not implement is rejected.
- A map whose minor is higher than the tool implements for its major is rejected, because it may use rules the tool cannot interpret.
- Rejection happens during validation, before anything is changed.
- An unimplemented version is rejected rather than interpreted.
- The tool may implement more than one major at a time. The specification neither requires nor forbids multi-major support: implementing a single major is valid, and so is implementing several.
- Major version `0` carries no compatibility guarantee. Any `0.x` revision may break the format, no compatibility is guaranteed between `0.x` revisions, and no automatic migration is provided. The additive-minor guarantee applies from `1.0` onward.
- Every file in one include graph must declare the same major. Files may declare different minors of that shared major; the version required by the assembled map is the highest minor any file declares, evaluated against the acceptance rule above.

At this moment, the current version is '0.1'.

### Includes

Top-level maps may include other maps:

```text
oparch dotfiles map
version = '0.1'

include 'common.dfmap'
include 'desktop.dfmap' for host 'desktop'
include 'laptop.dfmap' for host 'laptop'
```

Include rules are:

- `include` is allowed only at top level.
- Include entries must appear after the `version` entry and before the first section.
- Include paths are wrapped in single quotes.
- Include paths are relative to the map file that contains the include entry.
- Absolute include paths are invalid.
- Include paths cannot escape the dotfiles source directory.
- Included files must also begin with the `oparch dotfiles map` header and a `version` entry, and every file in the include graph must declare the same major (see Map Version).
- Included files may include other files.
- Include cycles are invalid.
- Missing included files are validation errors.
- Includes do not override earlier rules.
- Duplicate active targets remain invalid after include expansion.

Include entries may use user and host selectors:

```text
include 'common.dfmap'
include 'hosts/desktop.dfmap' for host 'desktop'
include 'users/work.dfmap' for user 'work'
```

Selectors on an include entry are inherited by every entry in the included file, including nested include entries. If an inherited selector is invalid for an included entry, the expanded map is invalid.

### Package Sections

Official repository packages are listed in `[packages]`:

```text
[packages]
hyprland
uwsm
```

AUR packages are listed separately in `[aur-packages]`:

```text
[aur-packages]
opencode
```

Package behavior is additive:

- Missing declared packages are installed.
- Already installed declared packages are left installed.
- Removing a package from the map does not uninstall it.
- Package version constraints are not supported in the map (see Version Constraints).
- Package entries may use hostname selectors.
- User selectors are invalid for package entries because packages are system-wide.

Example:

```text
[packages]
nvidia for host 'desktop'
brightnessctl for host 'laptop'
```

#### Version Constraints

The map has no syntax for pinning a package to a specific version. The recommended workaround is to manage a pacman configuration file (for example `/etc/pacman.conf`) as a dotfile: pacman honors it, and because managed targets are applied before packages are installed (see Application Order), the pin takes effect on the same synchronization.

### Dotfile Operations

Every rule in a `[dotfiles.<category>]` section begins with one explicit operation.

The `<category>` in a `[dotfiles.<category>]` header is an organizational label and a selector scope only. It never appears in a target path, is referenced by no template, and has no relation to the `[values.<category>]` and `[secrets.<category>]` categories. A header applies its selectors to the rules written under it; because target uniqueness is global and rules carry no precedence, sharing a category name across sections carries no additional meaning for the resulting plan.

#### Link

```text
link 'source' to 'target'
```

- A file source creates one direct symlink at the target.
- A directory source recursively creates direct symlinks for every normal file under the source while preserving relative paths.
- A directory mapping does not create a symlink for the directory itself.
- Application changes made through a linked target modify the source under `/dotfiles` directly.

#### Copy

```text
copy 'source' to 'target'
```

- A file source creates one managed copy at the target.
- A directory source recursively copies normal files while preserving relative paths.
- Copy exists for targets that cannot consume links to the encrypted `@dotfiles` subvolume, specially the EFI boot partition.

#### Render

```text
render 'template' to 'target'
render 'first.tpl' + 'second.tpl' to 'target'
```

Render is the only operation that substitutes placeholders, so it is the only one that consumes values and secrets; `link` and `copy` reproduce their source verbatim (see Versioned Values and Secret Declarations).

- Render accepts one or more regular-file sources.
- Directory render sources are invalid.
- Sources are read in listed order and concatenated without implicit separators.
- Source files own any required spaces and trailing newlines.
- The concatenated text is processed as one template and written as one managed output file.
- Rendering is textual composition, not format-aware merging.
- JSON, YAML, TOML, or other structured formats receive no special merge behavior.
- Application changes to rendered targets do not modify `/dotfiles` and are overwritten by the next synchronization.

The optional `with mode '<octal-mode>'` option overrides the output mode of a copy or a rendered file:

```text
render 'private.conf.tpl' to '&HOME/.config/application/private.conf' with mode '0640'
```

Mode behavior is:

- Every copy and every rendered file defaults to `0440`, regardless of category or content.
- `mode` overrides that default per rule.
- `mode` is invalid for links, because a symlink has no independent mode.

Because managed copies and rendered files default to read-only, a target an application must rewrite in place is a poor fit for `copy` or `render` and should be a `link` instead, so edits flow back to `/dotfiles`.

### Source and Target Paths

- Source paths are relative to `/dotfiles`, or to the directory selected through the tool's `--source` option.
- Absolute source paths are invalid.
- Source paths cannot escape the source directory.
- Source symlinks and special files are invalid.
- Target paths must resolve to absolute paths.
- Parent directories are created when needed.
- Parent directories and managed outputs of a user target are owned by that user and that user's own primary group, for example `iokode:iokode`, not by the `dotfiles` group.
- Parent directories and managed outputs of a global target are owned by `root:root`.

Path placeholders are:

- `&USER`: current login username.
- `&HOME`: the current login user's home directory.
- `&HOST`: the current value of `/etc/hostname`.

Source paths may contain `&USER` and `&HOST`. Target paths may contain all three placeholders.

A target containing `&HOME` or `&USER` is a user target. It is expanded once for every member of the `dotfiles` group after selectors are evaluated. A target containing neither placeholder is global and applies once.

User selectors are invalid on global targets. Host selectors are valid on user and global targets.

The `ownership` option forces a user target's output, and any parents it creates, to `root:root` instead of the target's user. Its only value is `'root'`:

```text
copy 'seed.db' to '/var/&USER/seed.db' with ownership 'root'
```

### Selectors

Selectors can include or exclude users and hostnames:

```text
for user 'personal'
for user 'personal','work'
except user 'work'
for host 'desktop'
for host 'desktop','laptop'
except host 'test-machine'
```

A condition is introduced by `for` (include) or `except` (exclude), then a dimension keyword — `user` or `host` — and a quoted value; comma-separated values match any listed value. Options are introduced by `with` in the same shape, as in `with mode '0640'` and `with scope 'user'`. Any number of `for`, `except`, and `with` clauses may appear on an entry, in any order.

Selector behavior is:

- Matching is exact and case-sensitive.
- Comma-separated values inside one selector use OR semantics.
- Different selector dimensions use AND semantics.
- A matching `except` clause vetoes the rule.
- Duplicate selectors of the same kind on one entry are invalid.
- User selectors are evaluated separately for each user expansion.
- Host selectors are evaluated against `/etc/hostname`.

For example:

```text
render 'work.conf.tpl' to '&HOME/.config/application.conf' for user 'work' host 'desktop','laptop'
```

This rule applies only to user `work` on host `desktop` or `laptop`.

A dotfile section may define selectors inherited by every rule in the section:

```text
[dotfiles.browser except user 'work']
link 'browser/' to '&HOME/.config/browser/'
```

Rule-level selectors further restrict inherited section selectors and cannot broaden them.

A section header's selectors apply only to the rules under that physical header. Because a category name may be declared more than once, each occurrence scopes its own rules independently:

```text
[dotfiles.hypr for host 'desktop']
link 'hypr/monitors_desktop.lua' to '&HOME/.config/hypr/monitors.lua'

[dotfiles.hypr]
link 'hypr/keybindings.lua' to '&HOME/.config/hypr/keybindings.lua'
```

Here `for host 'desktop'` restricts only the first block; the second block's rule is unrestricted. Repeating the category name does not combine the two headers' selectors, whether the occurrences are in one file or spread across included files.

### Versioned Values

Non-secret values live in `[values.<category>]` sections. The section suffix is the value category, each line defines one key inside that category, and the full value name is `<category>.<key>`:

```text
[values.git]
email = 'ivan@example.com'
email = 'ivan@iokode.net' for user 'iokode'
sign_commits = 'true'
sign_commits = 'false' for host 'test-machine'
```

Value definitions may use user and host selectors. Resolution for a value in a render context is default-plus-override:

- A definition with no selectors is the default for its key.
- A definition with selectors overrides the default for every context its selectors match.
- At most one selector-qualified definition may match a single context. Two qualified definitions matching the same context are a validation error.
- If no qualified definition matches and no default exists, resolution fails validation.

In the example above, `git.email` resolves to `ivan@iokode.net` for user `iokode` and to `ivan@example.com` for every other user, while `git.sign_commits` resolves to `false` on host `test-machine` and to `true` otherwise.

### Secret Declarations

Secrets are declared in `[secrets.<category>]` sections. As with values, the section suffix is the category and each line names one key, so the full secret name is `<category>.<key>`. A declaration names the secret and its scope but never contains the value:

```text
[secrets.github]
token with scope 'user'

[secrets.backup]
password
```

A secret is `global` by default — one value for the machine, shared by every user. The option `with scope 'user'` makes the secret per-login-user; omit `with scope` for a global secret.

Secret values are stored outside `/dotfiles` to avoid them beign versioned.

Secret behavior is:

- Missing required secrets fail validation before managed targets are changed.
- Secret values are never written to logs, dry-run output, or synchronization state.
- User-scoped secrets are available only while rendering that user's target.
- Secret values are not passed through command arguments.

### Secret Store

Secret values live in the local dotfiles secret store, outside `/dotfiles`. Its root is `/etc/oparch/dotfiles-sync/secrets/`, owned `root:root` with mode `0700`. Each secret is one regular file, owned `root:root` with mode `0600`, whose contents are the value; one trailing newline is stripped if present, with no other transformation.

The file that holds a secret is selected by its scope:

```text
global   /etc/oparch/dotfiles-sync/secrets/global/<name>
user     /etc/oparch/dotfiles-sync/secrets/user/<username>/<name>
```

- `<name>` is the full secret name `<category>.<key>`, used verbatim as the file name. Dots such as in `github.token` are literal, not directory separators.
- `<username>` is the login user whose target is being rendered.

Resolution behavior is:

- A `global` secret is read once from the `global` directory.
- A `user` secret is read from the current user's directory only while rendering that user's targets.
- A declared secret reached by the current-machine plan whose file is missing is a validation error, reported before any managed target is changed.
- The store is read-only to synchronization: `oparch-dotfiles-sync` never creates, edits, or deletes secret files.

### Template Syntax

Rendering supports placeholders. Three are three built-in values: `{{USER}}`, `{{HOME}}`, `{{HOST}}`. Values and secrets are referenced by their full `<category>.<key>` name:

```text
{{USER}}
{{HOME}}
{{HOST}}
{{github.account}}
{{github.token}}
```

`{{github.account}}` references the value defined in `[values.github]` as `account`, and `{{github.token}}` references the secret declared in `[secrets.github]` as `token`.

A referenced `<category>.<key>` must resolve to exactly one declared value or secret. A reference to an undeclared name, or to a `<category>.<key>` declared as both a value and a secret, is a validation error reported before any target is changed.

Value and secret references are global. A template may reference any declared value or secret by its full `<category>.<key>` name regardless of which `[dotfiles.<category>]` section holds the rule being rendered.

Example template:

```text
{
    "github": {
        "account": "{{github.account}}",
        "personalAccessToken": "{{github.token}}"
    }
}
```

A placeholder is escaped with a leading backslash so it renders literally instead of being substituted. Exactly one leading `\` is removed and the remaining text, including the surrounding `{{` and `}}`, is written verbatim:

```text
{{\git.email}}    renders  {{git.email}}
{{\\git.email}}   renders  {{\git.email}}
{{\\\git.email}}  renders  {{\\git.email}}
```

Each additional backslash escapes one more level.

Template substitution is raw, single-line text substitution. Templates do not support:

- shell evaluation
- command substitution
- conditions
- loops
- implicit escaping for a target file format
- arbitrary functions

### Validation and Application

`oparch-dotfiles-sync` builds and validates the complete current-machine plan before applying managed filesystem targets.

Validation includes:

1. Parse the complete map and validate its version.
2. Expand the complete include graph in file order.
3. Reject missing includes, include cycles, and include paths that escape the dotfiles source directory.
4. Resolve the current hostname and members of the `dotfiles` group.
5. Evaluate package, include, section, and rule selectors.
6. Expand source and target placeholders.
7. Validate every source and target path.
8. Resolve every referenced value and secret.
9. Reject duplicate targets after all expansion and selector evaluation.
10. Reject file-versus-directory target conflicts.
11. Validate package declarations.

Two rules may declare the same target when their selectors are mutually exclusive on the current machine. Two active rules producing the same expanded target are invalid.

#### Application Order

After successful validation, the tool applies changes in this order:

1. Remove stale managed targets recorded in the previous state but absent from the current plan.
2. Apply copies, renders, and links.
3. Install missing declared packages.

Managed filesystem targets are applied before packages are installed so that configuration the map manages is in place before pacman runs. This is what allows a managed pacman configuration to constrain installed package versions (see Version Constraints).

Because filesystem targets are applied first, a package installation failure leaves the applied links, copies, and rendered outputs in place.

### Managed State

Synchronization state is stored under:

```text
/var/lib/oparch/dotfiles-sync/
```

The state records links, copies, and rendered targets created by the tool. Rendered outputs are staged in this directory before being written to their targets. Managed targets recorded in the previous state but absent from the current plan are removed during synchronization.

### Tool Interface

`oparch-dotfiles-sync` accepts:

- `--source <path>`: optional dotfiles source directory. Default: `/dotfiles`.
- `--map <path>`: optional map path. Default: `/dotfiles/main.dfmap`.
- `--dry-run`: print the plan without installing packages or changing filesystem targets.

Dry-run output identifies secret references without printing their values.

There is no interactive synchronization mode because behavior is declared by the map. Any interactive secret collection must remain a separate interface that populates the local dotfiles secret store before calling `oparch-dotfiles-sync`.

## Why

- One top-level map is used because package requirements and configuration targets need one versioned source of truth.
- Includes are supported because the top-level map can remain a small index while common, host-specific, and user-specific rules live in focused files.
- Explicit `link`, `copy`, and `render` operations are used because direct links, early-boot copies, and generated user-specific files have different runtime behavior and must not be inferred from filenames or targets.
- Rendering is supported because configuration can share a common structure while using different account values or secrets for each login context.
- Textual composition is supported because applications that cannot load multiple configuration files still need large configurations to be split into smaller versioned fragments.
- Rendering remains deliberately limited because shell execution, general-purpose template logic, and format-aware merging would make validation and synchronization behavior harder to predict.
- User and hostname selectors are separate because login contexts and physical machines are different dimensions. For example, `personal` and `work` are users, while `desktop` and `laptop` are hostnames.
- Secret declarations are versioned without secret values because public dotfiles repositories must describe required configuration without publishing credentials.
- A single local secret store is used instead of a pluggable backend interface because one fixed, file-based origin on the encrypted root keeps secret resolution auditable, statically describable, and free of network dependencies during synchronization.
- Full-plan validation is required because synchronization can replace existing targets and remove stale managed targets; detecting conflicts after partial application would leave the system inconsistent.
- Package synchronization is additive because the system can contain baseline or manually installed packages that the dotfiles map does not own.
- Managed filesystem targets are applied before package installation because a pacman configuration managed through the map must be in place before pacman resolves packages; this is how version pinning is expressed without a version-constraint syntax in the map.
- Arbitrary commands are forbidden because allowing the map to execute code would turn declarative configuration data into an installation script and prevent complete static plan validation.

## Considerations

- `../decisions/008-grub-boot-policy.md` already requires copying `grub/` into `/boot`; `copy` makes that behavior explicit in the map instead of retaining a GRUB-specific special case.
- Rendered targets are generated artifacts. Application edits to them are not versioned and are overwritten during synchronization.
- Because managed filesystem targets are applied before packages are installed, a package installation failure can leave applied configuration without the packages it configures.
- A managed target that collides with a file owned by a not-yet-installed package conflicts with that package at install time. Pacman configuration, owned by the already-installed `pacman`, is the reliable pre-install case.
- Includes only assemble one logical map. They must not introduce override or precedence semantics.
- Secrets rendered into application configuration exist as clear text at their runtime target, even though the source secret remains outside `/dotfiles` and the filesystem is encrypted at rest.
- Login users are work-context boundaries rather than security boundaries. User-scoped secret resolution prevents accidental account mixing but does not create isolation between mutually untrusted people.
- The installer currently synchronizes an externally obtained public dotfiles source before first boot. If that map requires secrets, those secrets must be provisioned before complete synchronization; secret-dependent rules must not be skipped silently.
- AUR packages must not be applied until the project defines the AUR helper, restricted build user, and PKGBUILD review policy.
- Do not add arbitrary synchronization scripts, shell expressions, template conditions, loops, or format-specific merge engines to this syntax without a separate decision.
