/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Claims Pandoc's bracketed span — `[text]{.class}` — as ``InlineAttributes`` elements.
///
/// ## What it is for
///
/// Markdown can say a run of words is emphasised, and that it is code, and there it stops.
/// A document that needs to say *this phrase is a defined term* has no way to name that.
/// A fenced div cannot help: a block wrapper cannot reach three words in the middle of a
/// sentence. The span is where a run of text says what it IS, and what that looks like is
/// left to the stylesheet — the same division of labour as `::: warning`.
///
/// ## Why this runs on the tree
///
/// Same reason as `CriticMarkupParser`: ``InlineCode``, ``CodeBlock``, ``InlineHTML`` and
/// ``HTMLBlock`` hold their content as strings rather than as ``Text`` children, so a
/// rewriter that only splits ``Text`` runs cannot reach inside one. A document explaining
/// this syntax is exactly the document that must not have it applied to its samples.
///
/// ## A label is not always one run of text
///
/// `[Contracting Party]{.defined-term}` is a single ``Text`` node and splits like a
/// comment. `[**Contracting Party**]{.defined-term}` is three siblings — `Text "["`, a
/// ``Strong``, `Text "]{.defined-term}"` — because cmark parsed the emphasis before
/// anything looked for a span. A defined term set in bold is the ordinary case in the
/// documents this exists for, so the scan crosses siblings and wraps what it finds
/// between them.
///
/// ## Strictness
///
/// The attribute grammar is `AttributeBlockParser`'s, so `[see note]{4}` is prose here for
/// the same reason `# Chapter {see note}` is prose there, and the two spellings cannot
/// drift apart. Beyond that: the block must follow the `]` immediately, brackets inside a
/// label must balance, and a label that could not be held by an ``InlineAttributes`` is not
/// claimed at all. Every doubtful case stays as the author typed it — the cost of being
/// wrong is somebody's words rewritten.
enum InlineSpanParser {

    /// Take the spans in `document` out of the text and into ``InlineAttributes`` elements.
    static func claim(in document: Document) -> Document {
        var rewriter = Rewriter()
        return rewriter.visit(document) as? Document ?? document
    }

    /// Where a span begins and ends across a run of siblings.
    struct Span {
        /// The child holding `[`, and the bracket itself.
        let open: Int
        let openAt: String.Index
        /// The child holding `]` and the attribute block, and the bracket itself.
        let close: Int
        let closeAt: String.Index
        /// Just past the block's closing brace, in the closing child.
        let resumeAt: String.Index
        let attributes: String
    }

    /// The first span in `children`, or nil if there is none.
    static func firstSpan(in children: [Markup]) -> Span? {
        for index in children.indices {
            guard let text = children[index] as? Text else { continue }
            var search = text.string.startIndex
            while let open = text.string[search...].firstIndex(of: "[") {
                if let span = span(in: children, openingAt: index, bracket: open) { return span }
                search = text.string.index(after: open)
                if search == text.string.endIndex { break }
            }
        }
        return nil
    }

    /// The span opened by the bracket at `bracket`, or nil if that bracket opens nothing.
    ///
    /// Bracket depth is counted so a label may contain a balanced pair of its own —
    /// `[see [1] below]{.ref}` closes at the second `]`, not the first. Depth is counted in
    /// ``Text`` only, which is right: a bracket inside a code span is that code's, and a
    /// bracket that opened a link is gone from the tree by now.
    private static func span(in children: [Markup], openingAt index: Int,
                             bracket: String.Index) -> Span? {
        var depth = 0
        var cursor: String.Index? = bracket
        for child in index..<children.count {
            guard let text = children[child] as? Text else {
                // A non-text sibling is part of the label, so it has to be something an
                // `InlineAttributes` can hold. Anything else is left as the author wrote
                // it rather than claimed and then quietly dropped by the conversion.
                guard children[child] is RecurringInlineMarkup else { return nil }
                cursor = nil
                continue
            }
            var position = cursor ?? text.string.startIndex
            cursor = nil
            while position < text.string.endIndex {
                switch text.string[position] {
                case "[": depth += 1
                case "]":
                    depth -= 1
                    if depth == 0 {
                        // The block follows the bracket immediately: `[text] {.class}` is a
                        // bracketed phrase and a brace block, which is what it looks like.
                        let after = text.string.index(after: position)
                        guard let block = AttributeBlockParser.leading(String(text.string[after...]))
                        else { return nil }
                        return Span(open: index, openAt: bracket,
                                    close: child, closeAt: position,
                                    resumeAt: text.string.index(after, offsetBy: block.length),
                                    attributes: block.attributes)
                    }
                default: break
                }
                position = text.string.index(after: position)
            }
        }
        return nil
    }

    // MARK: - The rewriter

    private struct Rewriter: MarkupRewriter {
        /// Untouched nodes are handed back untouched — see `CriticMarkupParser.Rewriter`,
        /// which explains what rebuilding one costs and why identity is the test.
        mutating func defaultVisit(_ markup: Markup) -> Markup? {
            var children: [Markup] = []
            children.reserveCapacity(markup.childCount)
            var changed = false
            for child in markup.children {
                guard let visited = visit(child) else { changed = true; continue }
                if visited.raw.markup !== child.raw.markup { changed = true }
                children.append(visited)
            }
            let claimed = claimSpans(in: children, changed: &changed)
            guard changed else { return markup }
            return markup.withUncheckedChildren(claimed)
        }

        /// A rewriter returns one node per visit and a span consumes several, so the work
        /// happens where children are rebuilt rather than in a `visitText`.
        ///
        /// Recursive on both halves: on the label, so `[the [Party]{.defined-term}]{.note}`
        /// claims the inner span as well as the outer; and on what follows the span, which
        /// is what finds the second and third spans in a sentence.
        private func claimSpans(in children: [Markup], changed: inout Bool) -> [Markup] {
            guard let span = InlineSpanParser.firstSpan(in: children),
                  let opening = children[span.open] as? Text,
                  let closing = children[span.close] as? Text else { return children }
            changed = true

            var rebuilt = Array(children[children.startIndex..<span.open])
            let head = String(opening.string[opening.string.startIndex..<span.openAt])
            if !head.isEmpty { rebuilt.append(Text(head)) }

            var label: [Markup] = []
            if span.open == span.close {
                let inner = String(opening.string[opening.string.index(after: span.openAt)..<span.closeAt])
                if !inner.isEmpty { label.append(Text(inner)) }
            } else {
                let tail = String(opening.string[opening.string.index(after: span.openAt)...])
                if !tail.isEmpty { label.append(Text(tail)) }
                label.append(contentsOf: children[(span.open + 1)..<span.close])
                let lead = String(closing.string[closing.string.startIndex..<span.closeAt])
                if !lead.isEmpty { label.append(Text(lead)) }
            }
            var nested = false
            label = claimSpans(in: label, changed: &nested)
            rebuilt.append(InlineAttributes(attributes: span.attributes,
                                            label.compactMap { $0 as? RecurringInlineMarkup }))

            var rest: [Markup] = []
            let after = String(closing.string[span.resumeAt...])
            if !after.isEmpty { rest.append(Text(after)) }
            rest.append(contentsOf: children[(span.close + 1)...])
            var more = false
            rebuilt.append(contentsOf: claimSpans(in: rest, changed: &more))
            return rebuilt
        }
    }
}
