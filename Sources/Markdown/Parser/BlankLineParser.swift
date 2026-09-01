/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Records runs of blank lines between blocks as ``BlankLines`` elements.
///
/// CommonMark treats one blank line and five as the same thing — a paragraph break — and
/// throws the difference away before anything downstream can see it. That is right for a
/// document meant to be read on the web, and wrong for one meant to be *printed*, where
/// the gaps an author left are a large part of how a letter, a title page or a signing
/// page is laid out.
///
/// Opt-in, and deliberately non-standard: the same file rendered by any other Markdown
/// tool shows no extra space.
///
/// ## How it decides
///
/// The gaps are read from the parsed tree, not from the source text: the line a block
/// ends on and the line the next block starts on are known exactly, and the difference
/// between them is the run of blank lines the author typed. So a blank line inside a code
/// block is never counted — it is inside the block's own range, not between two of them —
/// and that holds for indented code, fenced code, and a fence of any length or marker.
enum BlankLineParser {

    /// Insert a ``BlankLines`` between every pair of blocks the author separated by more
    /// than one blank line.
    static func record(in document: Document) -> Document {
        guard let rebuilt = insertBlankLines(into: document) as? Document else { return document }
        return rebuilt
    }

    private static func insertBlankLines(into markup: Markup) -> Markup {
        // Only between block-level siblings. Inline content has no lines to leave blank,
        // and a list's items are separated by its own loose/tight rule rather than by
        // anything an author can space out.
        let children = markup.children.map { child -> Markup in
            child is BlockContainer || child is Document ? insertBlankLines(into: child) : child
        }
        guard markup is Document || markup is BlockQuote || markup is FencedDiv else {
            return markup.withUncheckedChildren(children)
        }

        var rebuilt: [Markup] = []
        for (index, child) in children.enumerated() {
            if index > 0, let count = blankLines(between: children[index - 1], and: child), count > 0 {
                rebuilt.append(BlankLines(count: count))
            }
            rebuilt.append(child)
        }
        return markup.withUncheckedChildren(rebuilt)
    }

    /// How many blank lines beyond the first separate two blocks, or nil if it cannot be
    /// told from their ranges.
    ///
    /// The first blank line is the paragraph break itself and is not space; only what the
    /// author added beyond it is.
    private static func blankLines(between previous: Markup, and next: Markup) -> Int? {
        guard let end = previous.range?.upperBound.line,
              let start = next.range?.lowerBound.line else { return nil }
        return max(0, (start - end) - 2)
    }
}
