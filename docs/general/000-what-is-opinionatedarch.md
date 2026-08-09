# What is OpinionatedArch

OpinionatedArch is an Arch-based system for one physical person who wants multiple work contexts without maintaining separate system configurations for each login account.

For a longer introduction, read [Introducing OpinionatedArch](https://iokode.blog/posts/opinionated-arch/).

## The Problem It Solves

One person often separates their activity into contexts: personal use, client work, a specific project. Separate login accounts give each context its own session, browser profiles, cookies, and running processes.

Keeping several accounts on a normal system means configuring each one, and repeating every configuration change across all of them. OpinionatedArch treats the accounts as contexts of the same operator: configuration is shared from `/dotfiles`, while sessions and data stay separate per account.

## What It Decides

OpinionatedArch is opinionated about the operating model, disk layout, encryption, snapshots, recovery, dotfiles, and maintenance invariants.

It does not decide how the user should interact with the machine day to day (the desktop environment, window manager, shell workflow, etc.).

## Where To Continue

- [Operating Model](001-operating-model.md) describes how the system works.
- [Installation Overview](002-installation-overview.md) describes how a machine is installed.
- [Glossary](003-glossary.md) defines the terms used across the documentation.

