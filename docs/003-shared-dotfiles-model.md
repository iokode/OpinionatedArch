# 003: Shared Dotfiles Model

## Context and Decision

Dotfiles are stored in `/dotfiles` and shared across login users. The dotfiles repository declares how its files are linked into the installed system through `/dotfiles/oparch.map`.

The map file is a custom Oparch syntax file, not a shell file. Shell variables are not expanded. User expansion uses the Oparch placeholder `&USER`, which is expanded by the synchronization tool for each user in the `dotfiles` group.

All mapping rules must belong to an explicit category. Categories can define exclusions shared by all rules inside the category, and individual rules can define additional exclusions.

`oparch-dotfiles-link` reads the map, builds a complete synchronization plan, validates the full plan, and then applies it. If validation fails, no filesystem changes are made. `--dry-run` prints the plan without applying changes.

Managed targets are direct symlinks to files under `/dotfiles`. Secret substitution and rendered outputs are not supported in this phase.

The tool records managed links in `/var/lib/oparch/dotfiles-link/links`. Links recorded there but absent from the current plan are removed during synchronization.

## Map Syntax

The default map path is `/dotfiles/oparch.map`.

Example:

```text
# Comments start with #

[browser !experiments]
'browser/profile config/' -> '/home/&USER/.config/browser/profile config/' # Browser profile config
[/browser]

[desktop]
'hypr/' -> '/home/&USER/.config/hyprland/'
[/desktop]

[shell]
'bash/bashrc' -> '/home/&USER/.bashrc' !guest
[/shell]

[system]
'etc/some config.conf' -> '/etc/some config.conf'
[/system]
```

Syntax rules:

- Empty lines are ignored.
- Lines beginning with `#` are comments.
- Inline comments begin at `#` and continue to the end of the line.
- `[category]` starts a category.
- `[/category]` ends a category.
- Every mapping rule must be inside a category.
- Nested categories are invalid.
- Duplicate category names are invalid.
- Category exclusions are written in the category header as `!username`.
- Line exclusions are written after the mapping rule as `!username`.
- Exclusions in a rule are the union of category exclusions and line exclusions.
- Mapping rules use `'source' -> 'target'`.
- Source and target paths must be wrapped in single quotes.
- A single quote inside a quoted path is escaped as `\'`.
- A relative source path is resolved from the source directory, regardless of the current working directory.
- An absolute source path is used as written.
- The default source directory is `/dotfiles`.
- `&USER` is an Oparch placeholder, not a shell variable.
- If `target` contains `&USER`, the rule expands for every user in the `dotfiles` group except excluded users.
- If `target` does not contain `&USER`, the rule is global and applies once.
- Exclusions are invalid on global rules.

## Link Semantics

- If the source is a file, the tool creates one symlink at the target path.
- If the source is a directory, the tool recursively creates symlinks for every normal file under that directory.
- Directory mappings never create a symlink for the directory itself.
- Existing target paths are replaced by managed symlinks.
- Parent directories are created when needed.
- Parent directories created under `/home/<user>` for a rule expanded from `&USER` are owned by `<user>:<user>`.
- Parent directories created for global rules are owned by `root:root`.
- Symlinks inside mapped sources are invalid.
- Special files inside mapped sources are invalid.
- Only normal files and directories are valid inside mapped sources.
- Two generated links with the same target path are invalid.
- Excluded users must exist and belong to the `dotfiles` group.
- A map with no mapping rules is valid and removes all previously managed links recorded in the state file.

## Tool Interface

`oparch-dotfiles-link` accepts:

- `--source <path>`: optional. Dotfiles source directory. Default: `/dotfiles`.
- `--map <path>`: optional. Map file path. Default: `/dotfiles/oparch.map`.
- `--dry-run`: optional. Print the synchronization plan without applying changes.

There is no interactive version of this tool because synchronization behavior is fully declared by the map file.

## Why

- `/dotfiles` is used as the shared dotfiles source because multiple login users consume the same runtime configuration source.
- A declarative map is used because the dotfiles repository must define where its files apply without hardcoding those paths in the synchronization tool.
- The map uses custom Oparch syntax because the file is configuration data, not shell code, and shell variable expansion must not affect synchronization behavior.
- `&USER` is used instead of `$USER` to avoid confusion with shell variables and the current process user.
- Mandatory categories are used to simplify parsing and to give exclusions a clear scope.
- Directory mappings expand to file symlinks because versioned files should coexist with unmanaged files in the destination directory.
- Full-plan validation is required because sync can replace existing paths; failures must be detected before any partial filesystem change is made.
- Managed-link state is stored in `/var/lib/oparch/dotfiles-link/links` because stale links can only be removed safely when the tool knows which links it created.
- `--dry-run` is provided because the tool can replace existing paths and remove stale managed links.

## Implementation Plan

### Installer

1. Create `/dotfiles` in the installed system.
2. Create the `dotfiles` group if missing.
3. Add intended login users to `dotfiles`.
4. Set ownership to `root:dotfiles` and mode `2775` on `/dotfiles`.
5. Apply default ACL inheritance for `dotfiles` group write access.

### Tool

1. Implement `oparch-dotfiles-link` with `--source`, `--map`, and `--dry-run`.
2. Parse and validate the complete map before applying any change.
3. Expand `&USER` rules for users in the `dotfiles` group.
4. Build the complete link plan and reject duplicate targets.
5. Reject mapped sources containing symlinks or special files.
6. Apply the plan by replacing target paths with managed symlinks.
7. Store managed-link state in `/var/lib/oparch/dotfiles-link/links`.
8. Remove state-recorded links that are absent from the current plan.

## Considerations

- Do not create links from one login home to another login home.
- Avoid world-writable permissions on `/dotfiles`.
- Non-secret `/etc` configuration can be versioned in the dotfiles repository and linked into `/etc`.
- Secrets and private keys must not be stored in clear text inside the managed dotfiles tree.
- Secret substitution is out of scope in this phase.
- The map parser must reject invalid input before the sync tool changes the filesystem.

## Critical Notes With Replies (Copy of Discussion)

1. Assistant critique: custom mapping syntax can become fragile if placeholders, categories, exclusions, and recursive directory mappings are not strictly defined.
   Decision response: the mapping syntax is intentionally small and line-oriented. If parsing in `sh` becomes too complex, a small C parser can emit a simpler structure for the `sh` synchronization tool.
2. Assistant critique: `$USER` looks like a shell variable and can be confused with shell expansion.
   Decision response: the map file is not a shell file. The placeholder is `&USER` to avoid confusion with shell variables and the current process user.
3. Assistant critique: symlinks inside `/dotfiles` would make the source tree ambiguous and can escape the intended versioned source model.
   Decision response: symlinks inside mapped sources are forbidden. The tool fails before making any change.
4. Assistant critique: recursive directory mappings can overwrite destination configuration unexpectedly.
   Decision response: replacement is intentional. Synchronizing dotfiles enforces the versioned configuration over existing destination files.
5. Assistant critique: stale managed symlinks cannot be safely removed unless the tool knows which links it created.
   Decision response: the synchronization tool keeps local state in `/var/lib/oparch/dotfiles-link/links` and only removes links recorded there.
6. Assistant critique: per-line exclusions can become repetitive when a whole category should exclude the same user.
   Decision response: categories support exclusions in the category header, while individual rules can still add their own exclusions.
7. Assistant critique: allowing mappings to arbitrary target paths can affect system configuration outside user homes.
   Decision response: this is intentional because the dotfiles repository may manage non-secret system configuration as well as per-user configuration.
8. Assistant critique: replacing existing target paths and removing stale managed links is destructive.
   Decision response: the tool provides `--dry-run`, validates the complete plan before changing anything, and treats an empty map as an explicit cleanup request.
9. Assistant critique: secret substitution requires rendering generated files outside `/dotfiles`, which breaks the direct-edit workflow where applications modify files that are immediately versionable in the dotfiles repository.
   Decision response: secret substitution is not supported in this phase. Managed dotfiles remain direct symlinks to `/dotfiles` so application changes can be reviewed and committed directly from the dotfiles repository.
