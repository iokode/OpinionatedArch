# Installer Input Sources

## Context

Several of the installer's inputs are not values but content held elsewhere: the dotfiles package, the return message's template package, and the theme it is composed with are sets of files. The logo and the encrypted secret store are single files rather than sets of them.

Each was asked for as one line of text, and what the line meant was deduced from its shape: empty was the project's own, a string carrying a scheme was a URL to a `.tar` to download and unpack, and anything else was a directory. The operator had to know the convention, a git repository could not be named at all, and a directory could only be reached by typing its absolute path from memory — on a machine that is not theirs, in a live environment where the medium holding it is usually not mounted yet.

`oparch-return-message-render` reads the same locations from the other side. It is given a values file that names a `template` and a `theme`, and resolves them itself, downloading and unpacking when they are URLs. Its own command document already states the opposite rule for the logo: *"The logo arrives as a file, not as the URL the configuration names. Obtaining it — downloading it, or letting the operator pick one from disk — belongs to whoever calls this tool."*

## Specification

### An input is a package or a file, and its origin is asked for

A **package input** is a set of files: the dotfiles package, the template package, the theme. Its origin is one of four:

| Origin | How it is given |
| --- | --- |
| the project's own | chosen from the list; template package and theme only |
| local | a directory or a `.tar`, chosen with a picker |
| remote `.tar` | a URL |
| git repository | a URL; the whole content of the clone is the package |

A **file input** is one file: the logo, or the encrypted secret store. Its origin is a URL, or a local file chosen with a picker.

The origin is a question of its own, answered before the location, and nothing is deduced from the text of an answer. The project's own package and theme are chosen explicitly rather than by leaving a field empty.

### A local origin is copied as soon as it is named

A local origin is copied into the installer's staging directory, `/tmp/oparch`, the moment the installer learns of it: when the picker returns, or, in an unattended installation, when the configuration file is read. A directory is copied, a `.tar` is unpacked there, a file is copied. This happens for every local origin, whether or not the installer is what mounted the medium it came from.

### Removable media are mounted from inside the installer

F5 opens a mount widget, from any screen. A device is mounted at `/run/oparch/media/<device>`, where the pickers see it as a directory like any other.

Everything mounted this way is unmounted when the installation starts, at F2 on the summary screen. A partition of the disk about to be erased may therefore be mounted and browsed: by the time anything is written it is gone, and whatever was taken from it was copied when it was chosen. Leaving through F6 or F7 leaves the mounts in place — a shutdown unmounts them, and an operator who stays at a shell can deal with them.

### The host gains three widgets and no decisions

Decision 015 gives the host the terminal and the running of processes, and gives BAML which commands run and what their output means. The three additions keep that line where it is:

- A **package picker** and a **file picker**. They list directories themselves, which is the same filesystem access the host already performs for `read` and `exists` and carries no decision. In the package picker, where directories and `.tar` files appear in the same list, entering a directory and choosing it are different gestures.
- A **mount widget**, on F5, from any screen. It draws a list and nothing else. Which command lists the devices, what its raw output means, which partitions are worth offering, where a device is mounted and what a failure is called are all answered by BAML, asked for reentrantly from inside the widget exactly as pacman's output is parsed today. The widget runs the commands it is handed, because running commands is what the host is for, and decides none of them.

### A tool is given paths, not origins

`oparch-return-message-render` takes `--template-package` and `--theme`, each a directory, each defaulting to the project's own under `--assets`. It resolves nothing: no download, no unpacking, no clone. Its values file keeps the values themselves — the languages, the fields, and where the logo was taken from — and no longer names a template or a theme. Whoever runs the tool passes the flags.

## Why

- The origin is asked for rather than inferred because the four origins are not distinguishable by shape. A git repository and an archive are both URLs, and a rule that guesses between them is a rule that fetches the wrong thing and reports the failure as something else.
- A picker replaces a typed path because the operator is choosing content on a machine they are installing, not recalling a path they wrote. Typing an absolute path from memory fails silently into "no such directory", and the correction is another blind attempt.
- Mounting belongs inside the installer because a live system shows only what is mounted, and a package on a USB stick is otherwise unreachable without leaving for a shell — which is the one thing an installer with a form should not require.
- The mount widget is separate from the pickers because a picker that also mounts is two tools sharing one screen. Being global instead, it also serves every later screen that needs a medium, at no extra cost.
- A local origin is copied as soon as it is named, not when it is used, because two things happen in between: the unmount when the installation starts, and the erasure of the target disk. Reading the configuration file is the unattended counterpart of the operator choosing — the first moment the installer knows what the content is, and the last at which the content is certainly still there.
- The copy is unconditional because the alternative is a rule with a case inside it — copied when the installer mounted the medium, read in place otherwise — which fails the same way, only later and only sometimes.
- Unmounting when the installation starts, rather than when the installer exits, is what makes browsing the target disk harmless: the operator does not have to know which partitions belong to the disk they are about to erase.
- The renderer stops resolving origins because a tool that fetches its own inputs carries the network, `tar` and now `git` into a machine that only needs to compose an image, and has to be trusted with an archive on an installed system. The rule its own document already applies to the logo is the rule for all three.
- The values file stops naming a template and a theme because a location nothing resolves is a location nothing reads.
- Whoever runs the tool passes the flags, rather than the installer planting a copy of the package in the installed system for the tool to find, because the tool's inputs are then in one place — its parameters — and there is no second place where the answer might also be. The defaults cover the common case: an installation using the project's own package and theme rebuilds its message with no flags at all.

## Considerations

The configuration file that drives an unattended installation names the origin explicitly too, as a kind and a location. The pickers are the interactive way to answer that question, not a second way of asking it.

A dotfiles package is cloned whole where the other two are cloned at one revision. The others are read here and dropped, and a history is not their content; the dotfiles package stays, as the repository [Disk Layout](../../decisions/001-disk-layout.md) restores `/dotfiles` from, so its history is part of what is being fetched. A package taken as a directory or an archive leaves no repository, and that restore path does not exist on that machine.

The encrypted secret store is a file input, obtained the same way the logo is. What it holds and what opens it are specified in [Secret Store Archive](../oparch-dotfiles-sync/002-secret-store-archive.md).

What would change this decision: a rebuild of the return message that runs unattended on an installed system — a timer, or a tool rebuilding after an edit — has no one to pass the flags. That is when the values file would have to name the template and the theme again, as local paths the installer put there, and the copy into the installed system would come with it.
