# Where a Command Runs

A program may have more than one root in play: the system it is running on, and a system mounted somewhere else. Writing a file into the second one is a matter of where the path points; running a command against it is not, because a command has its own idea of what `/` means.

`Target` is what names which root is meant, and whether a command aimed at it has to be run inside it. It lives in the shared code, with the `Shell` and `Files` ports it is used with, for the reasons `005-baml-repository-layout.md` gives.

## What a target is

Two things, and they are separate on purpose:

```baml
class Target {
    root: string,
    uses_chroot: bool,
}

local_target()          // "/",  not entered
chroot_target("/mnt")   // /mnt, entered
```

`uses_chroot` is answered rather than worked out from the root. They are different questions about the same volume: a mounted system is read and written directly whatever the answer, and only a command that has to see it as its own root is entered with `arch-chroot`. Deriving one from the other would make "mounted" and "entered" the same word, and they are not.

## Two questions, one target

The same target answers both, and each has its own way in.

**Paths** go through `target_path`, which prefixes the root and refuses a relative path outright — a path that is not absolute has no meaning against a root, and taking it would silently write somewhere relative to wherever the program happens to be.

```baml
target_path(chroot_target("/mnt"), "/etc/fstab")   // /mnt/etc/fstab
target_path(local_target(), "/etc/fstab")          // /etc/fstab
```

**Commands** go through `run_in`, or `feed_in` when the command reads from standard input:

```baml
run_in(shell, local_target(), "locale-gen", [])          // locale-gen
run_in(shell, chroot_target("/mnt"), "locale-gen", [])   // arch-chroot /mnt locale-gen
```

So a caller writes a file into a target and runs a command against it without deciding anything twice, and without either call knowing what the other did.

## Why the answer is not the caller's

Where a command runs is a property of the target it is aimed at, not of whoever aims it. Two callers deciding it separately would decide it differently, and the second one would decide it while reading the first one's code.

The practical shape of that: a caller working only on the system it runs on passes a local target and never learns the other case exists. Nothing about its code says "no chroot here" — there is simply nothing to say.

## The environment a command runs with

Variables are given by wrapping the shell rather than by passing them down to every call:

```baml
let drawing = with_env(shell, { "XDG_DATA_HOME": theme_directory });
```

They are handed over through `env`, which is a program and not a property of the process, so it reads the same through every implementation of the port — the recording one sees them in the line it writes down, and a command entered into another root gets them with it.

They are **added** to the environment the command would have had, not put in its place. A command that loses its `PATH`, `HOME` and locale in order to gain one variable has been given less than it had.

### What is assumed, when a target is entered

The wrapping happens outside the entry, not inside it:

```
env LC_ALL=C.UTF-8 arch-chroot /mnt fold -s -w 40
```

and not `arch-chroot /mnt env LC_ALL=C.UTF-8 fold …`. What that assumes is that neither `arch-chroot` nor `chroot` clears the environment, so what is set outside is still set for the command that ends up running inside. That holds.

The narrower form would not rest on the assumption, and is not used because only the function that builds the entry could place the variables there — which would mean a caller that wants an environment carrying it down to every command it eventually runs, instead of wrapping a shell once.

## What uses it

`oparch-installer`, with `chroot_target("/mnt")`: it writes into the mounted system directly and enters it for the commands that have to see it as their root, and one target answers both.

Nothing else. `oparch-dotfiles-sync` and `oparch-return-message-render` work on the machine they run on and call the shell directly, which is the same thing a local target would do. That is worth stating plainly rather than leaving the abstraction looking more used than it is: it is here because a second kind of caller is expected — anything that repairs or inspects a system it is not running on — and because the alternative was for the installer to keep owning it, where a second caller would have had to reach into a tool to get at it.
