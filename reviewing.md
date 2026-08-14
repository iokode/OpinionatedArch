# Reviewing

Tracking for the branch of work that puts the repository in order. One heading per document read through, holding what its review changed elsewhere and what it turned up that is still to do. What was done to the repository before any document was reviewed is at the top, under no document, because it belongs to none.

This file is temporary. When the branch is done it goes.

## The repository itself

Not from reviewing any document; this is the reordering the branch was opened for.

The old `sh` artifacts are gone — `installer/`, `lib/` and `bin/`, the last of which held the only implementation of five documented tools — and the C# artifacts with them. `baml/` is now `src/`, and `test/` is now `tests/`. The unit tests stayed inside each tool's project, because a BAML test is source compiled with the code it exercises and cannot live outside it; only the end-to-end harness moved.

`docs/development/` was a drawer holding three different things, and they now have their own places: `development/` for the lasting guidelines, `plans/` for finite plans, `state/` for where the project is. The Installer Port Plan was deleted and its content became What Is Built; `remaining.md` moved out of the root of `docs/` and became Remaining beside it. Dotfiles Integration was kept whole as a record rather than deleted, with a note at its head saying it has been carried out.

`docs/README.md` was split: it is now Document Types and holds only the rules, and Index holds the list of every document.

The tool document type gained a `Requirements` section — what a tool needs to find installed where it runs — and it was written for the three tools that exist. It names what a tool calls rather than what a medium carries.

`tests/e2e/run.sh` points at `src/` and `tests/`, and no longer cites a document that stopped existing long ago. `deploy-to-vm.sh` packs and copies `oparch-dotfiles-sync` beside the installer and the renderer, which the dotfiles plan asked for and nobody had done. `assets/grub/grub.cfg` cited the wrong decision by number, naming the mkinitcpio hooks policy where it meant the GRUB one.

Nothing is committed. The four test suites pass, the Rust host builds, both packed tools build, every document in `docs/` is in the Index, and no cross-reference is broken.

## Operating Model — reviewed

Went through section by section. It now has five sections, mentions no tool and no format, and every `See` points at a decision. Its introduction stopped being a summary of its own sections and says instead where the document sits and what it leaves out. The Storage section was cut for describing the inside of the machine rather than how it is operated.

### Changed elsewhere because of it

**Login users became work contexts, everywhere.** The review of its first section found that the login/logical split was a property of any Linux system rather than a decision of this one, and that "work context" and "login user" were two names for one thing — the glossary needed two entries that defined each other. That took the prose of twenty-one documents, the group `login-users` which is now `work-contexts`, the configuration keys `login_users` and `preserved_home_users` which are now `work_contexts` and `preserved_work_contexts`, three tool names — `oparch-work-context-create`, `oparch-work-context-remove` and `oparch-snapshot-work-context-create` — and the installer's field, parser, form step and error messages. The form now asks for work contexts on a screen of that name; the installation phase still says users, because that step is the `useradd`. The word *user* was kept for accounts in general, because the `dotfiles` group deliberately admits accounts that are not work contexts. The decision that owned all of it was renamed from User Model and Account Types to Work Contexts and Accounts, because "account types" was exactly the enumeration that was dropped.

**Recovery Strategy was created**, as an empty stub. The Snapshots and Recovery section needed something to point at that was about recovery rather than about a boot menu, and no decision owned it.

**Document Types now asks for an introduction** where it asked for a summary, in the three types that said so. The word changed because a summary of a document's own sections is a restatement of them, which is what its introduction had become.

### Still to do

**Dotfiles Policy has to grow into what it now owns.** Operating Model defers the shared-configuration principle to it, and the document does not contain it: its `Decision` covers permissions on `/dotfiles` and nothing else, and its `Context` frames the whole document as "what access the group gives". It needs to decide, in its own words, that the configuration is one source that every work context takes from, and that what differs between contexts or machines is declared rather than kept as separate copies. This is also the document that may legitimately link down to Dotfiles Map Format, being the layer that already touches implementation.

**The secret store is a domain fact owned by an infrastructure document.** Where the store lives, with what owner and what modes, is a property of the installed machine, and it is specified in Dotfiles Map Format. Dotfiles Policy expressly disclaims it, because the store sits outside `/dotfiles`. Underneath there is a worse one: the path is `/etc/oparch/dotfiles-sync/secrets`, so the name of a tool is inside the machine's layout.

**Snapshot Strategy contradicts itself after the rename.** It still says `home/@<login-user>` and `/snapshots/home/<login-user>/…` in five places, and `home/<work-context>` in one.

**What is OpinionatedArch carries the old vocabulary.** Its opening says "for each login account", and its problem statement "separate login accounts give each context its own session". The rename swept "login user" and "login-users" and never looked for "login account".

**The root README carries the same sentence**, word for word: "without maintaining separate system configurations for each login account".

**What is OpinionatedArch could take the whole-disk fact.** The Storage section was cut, but one thing in it was operationally relevant and is now in no general document: that the system takes the whole disk, so it does not share a machine with another system.

**Recovery Strategy has to be written.** What it collects is spread across Disk Layout, GRUB Boot Policy, Snapshot Strategy and Kernel Strategy, and two documents defer an obligation to it that had nowhere to go: Encryption Strategy leaves the LUKS header backup and its workflow to be written down later, and Work Contexts and Accounts requires root recovery procedures to be documented.

**Document Types could say what an introduction is not.** The rule now asks for an introduction rather than a summary, which is the right word, but nothing stops the next writer from writing a summary and calling it one.

**Operating Model has a trailing space** at the end of the first paragraph of Work Contexts, where a sentence was removed.
