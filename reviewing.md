# Reviewing

Tracking for the branch of work that puts the repository in order. One heading per document read through, holding what its review changed elsewhere and what it turned up that is still to do. What was done to the repository before any document was reviewed is at the top, under no document, because it belongs to none.

This file is temporary. When the branch is done it goes.

## Index

Every document, ticked when its review is called done. Only the operator ticks a box. A document with a heading below it has notes, which says nothing about whether it is finished.

**General**

- [x] What is OpinionatedArch
- [x] Operating Model
- [ ] Installation Overview

**Decisions**

- [ ] Work Contexts and Accounts
- [ ] Disk Layout
- [ ] Encryption
- [ ] Swap
- [ ] Snapshots
- [ ] Localization and Time
- [ ] System Identity
- [ ] Kernel
- [ ] Boot Image Format — work in progress, nothing decided yet
- [ ] Bootloader
- [ ] Pre-Boot Ownership Message
- [ ] Return Message on an Installed System — work in progress, nothing decided yet
- [ ] mkinitcpio Hooks
- [ ] Recovery — work in progress, nothing decided yet
- [ ] Package Baseline — work in progress, nothing decided yet
- [ ] AUR — work in progress, nothing decided yet
- [ ] Service Baseline — work in progress, nothing decided yet
- [ ] Network Stack
- [ ] Audio Stack — work in progress, nothing decided yet
- [ ] Security Baseline — work in progress, nothing decided yet
- [ ] Dotfiles
- [ ] Oparch Tools

**Tools**

- [ ] oparch-installer, and its configuration file, inputs and input sources
- [ ] oparch-return-message-render, and its package, values and theme formats
- [ ] oparch-dotfiles-sync, and its map format and secret store archive
- [ ] oparch-work-context-create
- [ ] oparch-work-context-remove
- [ ] oparch-snapshot-system-create
- [ ] oparch-snapshot-work-context-create
- [ ] oparch-snapshot-restore
- [ ] oparch-password-rotate
- [ ] oparch-password-rotate-interactive

**Development**

- [ ] BAML as Implementation Language
- [ ] Host Bridge
- [ ] Repository Layout
- [ ] Where a Command Runs
- [ ] Acting on Another System
- [ ] BAML Working Notes
- [ ] End-to-End Testing
- [ ] Installation Checks

**Plans**

- [ ] Dotfiles Integration

**State**

- [ ] What Is Built
- [ ] Remaining

**Outside `docs/`**

- [x] README
- [ ] AGENTS

## The repository itself

Not from reviewing any document; this is the reordering the branch was opened for.

The old `sh` artifacts are gone — `installer/`, `lib/` and `bin/`, the last of which held the only implementation of five documented tools — and the C# artifacts with them. `baml/` is now `src/`, and `test/` is now `tests/`. The unit tests stayed inside each tool's project, because a BAML test is source compiled with the code it exercises and cannot live outside it; only the end-to-end harness moved.

`docs/development/` was a drawer holding three different things, and they now have their own places: `development/` for the lasting guidelines, `plans/` for finite plans, `state/` for where the project is. The Installer Port Plan was deleted and its content became What Is Built; `remaining.md` moved out of the root of `docs/` and became Remaining beside it. Dotfiles Integration was kept whole as a record rather than deleted, with a note at its head saying it has been carried out.

`docs/README.md` was split: it is now Document Types and holds only the rules, and Index holds the list of every document.

The tool document type gained a `Requirements` section — what a tool needs to find installed where it runs — and it was written for the three tools that exist. It names what a tool calls rather than what a medium carries.

`tests/e2e/run.sh` points at `src/` and `tests/`, and no longer cites a document that stopped existing long ago. `deploy-to-vm.sh` packs and copies `oparch-dotfiles-sync` beside the installer and the renderer, which the dotfiles plan asked for and nobody had done. `assets/grub/grub.cfg` cited the wrong decision by number, naming the mkinitcpio hooks policy where it meant the GRUB one.

All of it is one commit on `repository-reordering`, pushed. The four test suites pass, the Rust host builds, both packed tools build, every document in `docs/` is in the Index, and no cross-reference is broken.

## Operating Model

Went through section by section. It now has five sections, mentions no tool and no format, and every `See` points at a decision. Its introduction stopped being a summary of its own sections and says instead where the document sits and what it leaves out. The Storage section was cut for describing the inside of the machine rather than how it is operated.

### Changed elsewhere because of it

**Login users became work contexts, everywhere.** The review of its first section found that the login/logical split was a property of any Linux system rather than a decision of this one, and that "work context" and "login user" were two names for one thing — the glossary needed two entries that defined each other. That took the prose of twenty-one documents, the group `login-users` which is now `work-contexts`, the configuration keys `login_users` and `preserved_home_users` which are now `work_contexts` and `preserved_work_contexts`, three tool names — `oparch-work-context-create`, `oparch-work-context-remove` and `oparch-snapshot-work-context-create` — and the installer's field, parser, form step and error messages. The form now asks for work contexts on a screen of that name; the installation phase still says users, because that step is the `useradd`. The word *user* was kept for accounts in general, because the `dotfiles` group deliberately admits accounts that are not work contexts. The decision that owned all of it was renamed from User Model and Account Types to Work Contexts and Accounts, because "account types" was exactly the enumeration that was dropped.

**Recovery was created**, as an empty stub. The Snapshots and Recovery section needed something to point at that was about recovery rather than about a boot menu, and no decision owned it.

**Document Types now asks for an introduction** where it asked for a summary, in the three types that said so. The word changed because a summary of a document's own sections is a restatement of them, which is what its introduction had become.

### Still to do

**Dotfiles has to grow into what it now owns.** Operating Model defers the shared-configuration principle to it, and the document does not contain it: its `Decision` covers permissions on `/dotfiles` and nothing else, and its `Context` frames the whole document as "what access the group gives". It needs to decide, in its own words, that the configuration is one source that every work context takes from, and that what differs between contexts or machines is declared rather than kept as separate copies. This is also the document that may legitimately link down to Dotfiles Map Format, being the layer that already touches implementation.

**The secret store is a domain fact owned by an infrastructure document.** Where the store lives, with what owner and what modes, is a property of the installed machine, and it is specified in Dotfiles Map Format. Dotfiles expressly disclaims it, because the store sits outside `/dotfiles`. Underneath there is a worse one: the path is `/etc/oparch/dotfiles-sync/secrets`, so the name of a tool is inside the machine's layout.

**Snapshots contradicts itself after the rename.** It still says `home/@<login-user>` and `/snapshots/home/<login-user>/…` in five places, and `home/<work-context>` in one.

**What is OpinionatedArch could take the whole-disk fact.** The Storage section was cut, but one thing in it was operationally relevant and is now in no general document: that the system takes the whole disk, so it does not share a machine with another system.

**Recovery has to be written.** What it collects is spread across Disk Layout, Bootloader, Snapshots and Kernel, and two documents defer an obligation to it that had nowhere to go: Encryption leaves the LUKS header backup and its workflow to be written down later, and Work Contexts and Accounts requires root recovery procedures to be documented.

**Document Types could say what an introduction is not.** The rule now asks for an introduction rather than a summary, which is the right word, but nothing stops the next writer from writing a summary and calling it one.

## README

Its opening sentence lost the dead vocabulary, and the link to the blog post left it: that link already lived in What is OpinionatedArch, and the chain now runs README, then that document, then the article. The section that summarised the operating model and repeated the list of what the project is opinionated about is gone, replaced by one that says why the project exists — no method for what comes after an installation, and work contexts made affordable by having one.

### Changed elsewhere because of it

**What is OpinionatedArch was rewritten.** Its problem section became five problems, one per paragraph, each conceding what can be done without this project and none of them naming the answer, which is Operating Model's to give. Its `What It Decides` lost the inventory — the last copy of it in the repository — and states the boundary instead: the system, not the interface. Both documents lost the sentence with "login account" in it, and the file lost a non-breaking space hidden inside a word.

### Still to do

**The link to the introductory article is now in neither.** It was in both, word for word; it came out of the README because it belonged one hop further in, and then out of What is OpinionatedArch as well. If it is meant to survive, it goes back into the second.

## What is OpinionatedArch

What the README's review did to this document is recorded above; this is the pass on the document itself.

Its problem section gained a spine. The first paragraph now names the root — Arch decides almost nothing and offers no method for what comes after — and says that most of what follows is that same absence seen from another side, which is also what the README says the project is for. The work-contexts problem moved to second, because the opening line of the document promises it and it used to arrive third, behind two paragraphs about Arch's baseline. The lost machine stayed but is now declared: it is the one problem on the list that no method would have prevented.

Where To Continue stopped being the listing of its own directory. It gained the decisions and the tools, which are what the document has just told the reader exist, and the glossary stopped being a step of the route and became a line for when a term is in the way.

### Changed elsewhere because of it

**Remaining gained the audio stack** as a pending decision. The document names the audio daemon among the choices this project takes for the operator, and nothing in the repository decides it.

### Still to do

**The document does not answer the question in its title.** It says what OpinionatedArch is for — five problems — and where its edges are, and where to go next. It never says what the thing consists of: an Arch installation with a set of decisions already taken and the tools that hold them. The opening line tries it in one sentence, and that sentence is only about work contexts.

**Oparch Tools does not carry the role this document gives the tools.** Here and in the README they are the way of working that keeps the decisions true as the machine changes, and Where To Continue presents them as the commands that keep a machine in the shape the decisions describe. The decision that owns them opens with "small commands for recurring system operations" and then legislates the naming format and the split between command-line and interactive. Nothing in it says they are what holds a machine to its decisions. Same shape as the Dotfiles entry above: a general document defers a claim to a decision that does not contain it.

**The session and login strategy is obsolete and still written down.** Remaining carries "Real session/login strategy — initial display manager and fallback until custom implementation exists" as a pending decision, and Work Contexts and Accounts closes its discussion notes by saying the model implies developing a custom session manager for username-only login. Neither is going to happen. They also sit on the wrong side of the boundary this document now draws, which puts the interface with the operator.

**The two new links go to a file listing.** `../decisions/` and `../tools/` resolve to directories with no page in them, so a reader who follows either lands on a list of file names rather than on something written. The two places that do have a written list are the Index and the repository's README.

## Glossary

Deleted, and the two links to it removed: the Index entry, and the closing line of Where To Continue in What is OpinionatedArch.

The pass before that had given it a criterion — an entry is a noun this project introduces and gives its own meaning to — and cut nine entries that failed it. Applying the same criterion to what survived is what settled the question: thirteen of its sixteen entries were compressed copies of definitions their own documents already carry, which is what `AGENTS.md` forbids. Being copies is also why it drifted. Two of its entries were caught wrong in one sitting: restore-based recovery presented restoring as the only way to recover, and the secret store entry said the sensitive content is declared in the map when the map format says, in as many words, that a declaration never contains the value. A copy has no reason to be revisited when the original changes.

It worked badly as an index too, being grouped by topic rather than alphabetical: finding a term meant guessing its topic, which is nearly the work of guessing which document owns it — and that one the Index answers by title.

### Still to do

**Three terms had no other home, and the definitions died with the file.** They are written out here so they can be put where they belong.

**Port** — no document defines it; Host Bridge uses it in five places as if it were understood, and that is where the word does its work. *The boundary between a tool and something outside it: running a command, touching a file, opening an encrypted store, drawing a terminal. It is declared as an interface so that a test can put a stand-in where the machine would be. Every interface in the project is a port today; the word is kept because an interface does not have to be one.*

**Harness** — End-to-End Testing describes the apparatus, but the argument for the word lived only in the glossary. *It is not the thing under test and it is not the assertions; it is what makes running them possible at all. The word is the one used for a wiring harness — the thing that connects and drives — and not for anything to do with the tools this project is written with.*

**Recovery mode** — Operating Model says what it is in passing, and Recovery will own it once written. *A second Arch system on the machine's own disk, started in place of the installed one, from which a damaged system is repaired by hand or restored from one of its snapshots.*

**"Shared configuration" will probably give way to "dotfiles".** The two are practically synonyms here, and the long form misleads: *shared* suggests sharing between people, and this system is built for one. Five documents carry it — Operating Model, whose second section is called Shared Configuration across Work Contexts, plus What is OpinionatedArch, Dotfiles, Work Contexts and Accounts, and Installation Checks.
