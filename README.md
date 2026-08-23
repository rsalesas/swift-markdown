# Swift Markdown (fork)

> **This is a fork of [swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown).**
> It exists to turn on capabilities that the underlying C parser has always had and
> that the Swift wrapper does not expose. Everything below the fork notes is upstream's
> own README, unchanged.

## Why this fork exists

`Markdown` is a Swift wrapper around [cmark-gfm](https://github.com/github/cmark-gfm),
and cmark-gfm can do more than the wrapper lets through. The most visible example is
footnotes. cmark-gfm has parsed `[^id]` since 2017 — `CMARK_OPT_FOOTNOTES`, with
`CMARK_NODE_FOOTNOTE_DEFINITION` and `CMARK_NODE_FOOTNOTE_REFERENCE` node types — but
the wrapper never sets the option, so `[^id]` arrives as ordinary text.

That gap has been [raised upstream in 2023](https://github.com/swiftlang/swift-markdown/issues/115),
and the [pull request to make options configurable](https://github.com/swiftlang/swift-markdown/pull/23)
has been open since 2024. A maintainer's stated position is that enabling footnotes is
easy, but they want visitor support and correct Swift-DocC rendering before doing it —
reasonable for a library whose primary client is DocC, and not much comfort if you are
writing something else.

So every project that needs footnotes reimplements them by rewriting the source text
before handing it to the parser: find `[^id]`, swap in a placeholder, put it back after
rendering. Microsoft's SwiftStreamingMarkdown does it. So did the project this fork was
built for. It is the same workaround every time, and it is wrong in the same way every
time, because a pre-parse text rewrite cannot see code blocks: a line reading
`[^x]: something` inside a fence gets treated as a real definition and vanishes from the
code sample.

The fix belongs in the parser, which already knows exactly where the code blocks are.

## What this fork adds

Everything is opt-in. No default behaviour changes, and a document parsed without these
options produces exactly the tree upstream produces.

| Addition | Kind | What it does |
| --- | --- | --- |
| `ParseOptions.parseFootnotes` | new | `[^id]` references and `[^id]: text` definitions, as `FootnoteReference` and `FootnoteDefinition` |
| `ParseOptions.parseAutolinks` | new | attaches cmark-gfm's autolink extension, so bare URLs, `www.` hosts and email addresses become `Link`s |
| `ParseOptions.strikethroughRequiresTwoTildes` | new | `~one~` stops being markup, matching how GitHub renders |
| `HTMLFormatterOptions.hardBreaks` / `.noBreaks` | new | render a soft break as `<br />` or as a space |
| `CodeBlock.languageName` | new | the leading word of the info string |
| `CodeBlock.language` | corrected docs | always was the *whole* info string, e.g. `swift title="Example"`, despite being documented as the language name |
| `HTMLFormatter.format(_:options:parseOptions:)` | additive | the string overload could not previously be given parse options, so it could never see any of the above |

### Footnotes

```swift
let document = Document(parsing: source, options: .parseFootnotes)
```

```
Document
├─ Paragraph
│  ├─ Text "Text"
│  ├─ FootnoteReference footnoteID: a
│  └─ Text "."
└─ FootnoteDefinition footnoteID: a
   └─ Paragraph
      └─ Text "A note."
```

`FootnoteDefinition` is a block container, so a note can hold several paragraphs, a
list, or a code block — not just one line of text.

Three behaviours come from cmark rather than from this fork, and are worth knowing
before you build a renderer on them:

- Definitions are moved to the end of the document and ordered by **first reference**,
  so a definition's position among the document's children is its footnote number.
- A definition that is never referenced is dropped.
- A reference with no definition is turned back into the literal text the author wrote,
  so `[^missing]` survives as `Text` — which is what lets a document quote the syntax.

## Using it

```swift
.package(url: "https://github.com/rsalesas/swift-markdown.git", branch: "main"),
```

`main` carries the additions. Each one also lives on its own branch off upstream
(`footnotes`, `exposed-options`) so it can be offered upstream unchanged, and
`upstream` is wired to swiftlang so this stays rebaseable rather than drifting.

## Relationship to upstream

This is a fork, not a replacement. Upstream owns the design of this library and
everything here follows its existing patterns — the same node-type plumbing that
`Strikethrough` and `Table` use, the same visitor and formatter conventions, the same
test style. If upstream takes these changes, this fork should stop existing.

Licensed under Apache License v2.0 with Runtime Library Exception, same as upstream.
See [LICENSE.txt](LICENSE.txt).

---

# Swift Markdown

Swift `Markdown` is a Swift package for parsing, building, editing, and analyzing Markdown documents.

The parser is powered by GitHub-flavored Markdown's [cmark-gfm](https://github.com/github/cmark-gfm) implementation, so it follows the spec closely. As the needs of the community change, the effective dialect implemented by this library may change.

The markup tree provided by this package is comprised of immutable/persistent, thread-safe, copy-on-write value types that only copy substructure that has changed. Other examples of the main strategy behind this library can be seen in [SwiftSyntax](https://github.com/swiftlang/swift-syntax).

## Getting Started Using Markup

In your `Package.swift` Swift Package Manager manifest, add the following dependency to your `dependencies` argument:

```swift
.package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
```

Add the dependency to any targets you've declared in your manifest:

```swift
.target(
    name: "MyTarget", 
    dependencies: [
        .product(name: "Markdown", package: "swift-markdown"),
    ]
),
```

To parse a document, use `Document(parsing:)`, supplying a `String` or `URL`:

```swift
import Markdown

let source = "This is a markup *document*."
let document = Document(parsing: source)
print(document.debugDescription())
// Document
// └─ Paragraph
//    ├─ Text "This is a markup "
//    ├─ Emphasis
//    │  └─ Text "document"
//    └─ Text "."
```

Please see Swift `Markdown`'s [documentation site](https://swiftlang.github.io/swift-markdown/documentation/markdown/)
for more detailed information about the library.

## Contributing to Swift Markdown

Please see the [contributing guide](https://swift.org/contributing/#contributing-code) for more information.

### Submitting a Bug Report

Swift Markdown tracks all bug reports with [GitHub Issues](https://github.com/swiftlang/swift-markdown/issues).
You can use the "Swift-Markdown" component for issues and feature requests specific to Swift Markdown.
When you submit a bug report we ask that you follow the
Swift [Bug Reporting](https://swift.org/contributing/#reporting-bugs) guidelines
and provide as many details as possible.

### Submitting a Feature Request

For feature requests, please feel free to file a [GitHub issue](https://github.com/swiftlang/swift-markdown/issues/new)
or start a discussion on the [Swift Forums](https://forums.swift.org/c/development/swift-docc).

Don't hesitate to submit a feature request if you see a way
Swift Markdown can be improved to better meet your needs.



<!-- Copyright (c) 2021-2023 Apple Inc and the Swift Project authors. All Rights Reserved. -->
