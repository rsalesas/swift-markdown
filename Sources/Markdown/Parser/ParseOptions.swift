/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Options for parsing Markdown.
public struct ParseOptions: OptionSet, Sendable {
    public var rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Enable block directive syntax.
    public static let parseBlockDirectives = ParseOptions(rawValue: 1 << 0)

    /// Enable interpretation of symbol links from inline code spans surrounded by two backticks.
    public static let parseSymbolLinks = ParseOptions(rawValue: 1 << 1)
    
    /// Disable converting straight quotes to curly, --- to em dashes, -- to en dashes during parsing.
    public static let disableSmartOpts = ParseOptions(rawValue: 1 << 2)

    /// Parse a limited set of Doxygen commands. Requires ``parseBlockDirectives``.
    public static let parseMinimalDoxygen = ParseOptions(rawValue: 1 << 3)

    /// Disable including a `data-sourcepos` attribute on all block elements during parsing.
    public static let disableSourcePosOpts = ParseOptions(rawValue: 1 << 4)

    /// Enable GitHub-style footnotes: `[^id]` references and `[^id]: text` definitions.
    ///
    /// The underlying cmark-gfm parser has always been able to do this; this option
    /// turns it on and surfaces the results as ``FootnoteReference`` and
    /// ``FootnoteDefinition`` elements.
    ///
    /// Enabling it changes the shape of the parsed document in three ways, all of them
    /// cmark's behavior rather than this library's:
    ///
    /// - Definitions are moved to the end of the document and ordered by *first
    ///   reference*, so their position in `Document.children` is their number.
    /// - A definition that is never referenced is dropped from the document.
    /// - A reference with no matching definition is left as the literal text the
    ///   author wrote, e.g. `[^missing]`.
    public static let parseFootnotes = ParseOptions(rawValue: 1 << 5)

    /// Enable GitHub's autolink extension, which turns bare URLs, `www.` hosts and
    /// email addresses in ordinary text into ``Link`` elements.
    ///
    /// cmark-gfm ships this as a syntax extension and this library has never attached
    /// it, so `Visit https://example.com` parses as one run of ``Text`` by default.
    public static let parseAutolinks = ParseOptions(rawValue: 1 << 6)

    /// Require two tildes to open and close a ``Strikethrough``.
    ///
    /// By default a single `~foo~` is struck through as well. GitHub's own renderer
    /// is configured this way, so a document written against GitHub may contain
    /// single tildes it never meant as markup.
    public static let strikethroughRequiresTwoTildes = ParseOptions(rawValue: 1 << 7)

    /// Enable Pandoc's fenced divs — `::: name` … `:::` — as ``FencedDiv`` elements.
    ///
    /// Markdown has no way to say "this run of blocks belongs together", which is what a
    /// callout, a signature panel or a column needs. Pandoc settled this with colon
    /// fences, and this is that syntax.
    ///
    /// Composes with ``parseBlockDirectives``: the two are independent syntaxes, and a
    /// fenced div may appear inside a block directive.
    ///
    /// > Note: A marker inside a code block is content, which this determines by parsing
    /// once and asking where the code blocks are rather than by tracking fences. A
    /// marker that is indented inside a list item or prefixed by a block quote's `>` is
    /// *not* recognised — placing a container inside another container needs
    /// continuation logic that only the underlying C parser has.
    public static let parseFencedDivs = ParseOptions(rawValue: 1 << 8)

    /// Enable Pandoc's attribute blocks on headings and images.
    ///
    ///     # Preface {.unnumbered}
    ///     ![Chart](chart.png){width=40% .right}
    ///
    /// The block is taken off the element's text and onto ``Heading/attributes`` or
    /// ``Image/attributes``, so it is removed exactly once and an element can never be
    /// found carrying it in one form and not the other.
    ///
    /// > Note: Claimed from the parsed tree rather than from the source text, so a block
    /// inside a code sample is left exactly as the author wrote it. Parsing is strict: a
    /// bare word anywhere inside the braces means it is prose, and `# Chapter {see note
    /// 4}` keeps its words.
    public static let parseAttributes = ParseOptions(rawValue: 1 << 9)

    /// Record runs of blank lines between blocks as ``BlankLines`` elements.
    ///
    /// CommonMark treats one blank line and five as the same paragraph break and throws
    /// the difference away. That is right for a document meant to be read on the web and
    /// wrong for one meant to be printed, where the gaps an author left are a large part
    /// of how a letter or a signing page is laid out.
    ///
    /// > Note: Read from the parsed tree, so a blank line inside a code block is never
    /// counted — it is inside the block's range rather than between two of them, which
    /// holds for indented code and for a fence of any length or marker.
    public static let preserveBlankLines = ParseOptions(rawValue: 1 << 10)

    /// Enable CriticMarkup comments — `{>> … <<}` — as ``InlineComment`` elements.
    ///
    /// A comment is *about* the document rather than part of it. Markdown has no way to say
    /// that, so a comment is either a separate file nothing else can read, or a convention;
    /// CriticMarkup is the convention.
    ///
    /// > Note: claimed from the parsed tree, so a comment inside a code sample of any kind
    /// is left exactly as written. A comment cannot span a line break or contain inline
    /// markup — see ``InlineComment``.
    public static let parseComments = ParseOptions(rawValue: 1 << 11)

    /// Enable Pandoc's bracketed span — `[text]{.class}` — as ``InlineAttributes`` elements.
    ///
    /// Markdown can emphasise a run of words and can make it code, and there it stops. A
    /// document that needs to say *this phrase is a defined term* — a contract, a
    /// specification, a report — has no way to name that, and a block-level wrapper cannot
    /// reach three words in the middle of a sentence. The span is where a run of text says
    /// what it IS, leaving what that looks like to the stylesheet.
    ///
    /// The attribute grammar is the one ``ParseOptions/parseAttributes`` uses on headings
    /// and images, so a block is claimed only when every token in it is clearly an
    /// attribute and `[see note]{4}` stays the prose it is.
    ///
    /// > Note: claimed before ``ParseOptions/parseAttributes``, and the order is
    /// load-bearing. `# The [Contracting Party]{.defined-term}` ends in a brace block, so a
    /// heading claiming its own attributes first would take `.defined-term` for the
    /// heading and leave `[Contracting Party]` as literal text.
    ///
    /// > Note: the attributes are stored as the author wrote them, which is Pandoc's
    /// spelling rather than the JSON5 that ``InlineAttributes`` carries when cmark's own
    /// `^[text](attrs)` syntax produces one. Both round-trip through ``MarkupFormatter``
    /// in the spelling they were written in.
    public static let parseInlineSpans = ParseOptions(rawValue: 1 << 12)
}

