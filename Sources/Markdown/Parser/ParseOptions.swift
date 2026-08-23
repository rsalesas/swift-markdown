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
}

