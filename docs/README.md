# Document Types

What a document of this project may be: the types, what each one is for, and the shape it takes. This is also where `docs/` starts, so it says where the rest is.

What documents there actually are is the [Index](INDEX.md), the other half of this directory, kept apart from this one so that adding a document does not touch the rules and changing a rule does not touch the list. A new document is listed there and nowhere else.

Every document belongs to exactly one document type. Each type has its own directory and defines the section order its documents follow. Every document is numbered inside its directory, and the number is part of the file name: `<number>-<name>.md`.

A document says what something is, or what was decided and why. It does not say what is going to be done about it, and it does not say how far along it is: a plan is a document of its own, under `plans/`, and where the project stands is `state/`. Keeping those out of the rest is what lets a document be read as true rather than as true-for-now.

A reference to another document is a relative path from the document making it, so it can be followed from where it is written.

## General

Documents describing what OpinionatedArch is and how it works.

Directory: `general/`

General documents have no fixed section order. They open with an introduction and use free `##` sections.

## Decision

Documents defining one decision each about the distribution itself: what OpinionatedArch installs and how the installed system behaves.

A decision about how a tool behaves belongs to that tool, and a decision about how the project is built belongs to `development/`. Neither is a decision document.

Directory: `decisions/`

Section order:

1. Context
2. Decision
3. Why
4. Considerations (optional)

## Tool

Documents defining one tool each. Every tool has its own directory, named after the command, and its documents are numbered inside it: `tools/<tool-name>/<number>-<name>.md`.

The first document of a tool is its command document, `000-command.md`, with this section order:

1. Description
2. Why is needed
3. Requirements (when the tool is written)
4. Input parameters (when applicable)
5. Interactive usage (when applicable)

`Requirements` states what the tool needs to find already installed on the system it runs on, and what those things have to be able to do — a package that is useless without an optional dependency is not met by installing the package. It names what the tool calls rather than what any one medium carries: which media carry what is decided where the media are, and a tool that named a medium would have to be edited every time one changed. A tool that is only specified has no such section, because what it needs follows from how it is written and it has not been written.

Any further document of a tool specifies part of what the tool defines — a format, a syntax, a protocol — with this section order:

1. Context
2. Specification
3. Why
4. Considerations (optional)

The `Specification` section uses free `###` subsections.

## Development

Documents describing how OpinionatedArch is built, tested and iterated on. They describe the project's own working environment, not the distribution it produces.

A decision about how the project is built is a development document, whatever it decides: the language the tools are written in, how the sources are laid out, and the internal code they share are all part of the working environment and none of them are shipped.

These are the documents that outlast the work. What is being done next is a plan, and how much of it is done is state; neither belongs here.

Directory: `development/`

Development documents have no fixed section order. They open with an introduction and use free `##` sections.

## Plan

Documents describing work that is going to be done: where it goes, in what order, and why that way and not another. One plan per document.

A plan is finite. It is written when work is large enough that deciding it while doing it would mean deciding it badly, and it is deleted when that work is done — unless the argument it makes is written down nowhere else, in which case it stays and says at its head that it has been carried out. It is never maintained as a description of what exists: that is the other documents' job.

Directory: `plans/`

Plans have no fixed section order. They open with what gap they close and use free `##` sections.

## State

Documents describing where the project is: what it has, and what it does not. These are the only documents that are expected to be wrong tomorrow, and gathering them is what keeps that expectation off everything else.

Directory: `state/`

State documents have no fixed section order. They open with an introduction and use free `##` sections. They describe; they do not define. Anything that would still be true if the project stopped today belongs to another type.

## Critical Notes With Replies (Copy of Discussion)

Any document may end with this optional section, whatever its type.

It records the critiques an LLM raised against the document during discussion, each one followed by the reply it received. Keeping both together makes it possible to review later whether the direction taken was the right one, and where it was deliberately argued against.

Entries are a numbered list. Each entry states the critique on the first line and the reply on the second:

```text
1. Assistant critique: <the objection raised>
   Reply: <the answer given>
```
