/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Claims CriticMarkup comments — `{>> … <<}` — as ``InlineComment`` elements.
///
/// ## Why this runs on the tree
///
/// A comment inside a code sample is a comment being *shown*, not used, and a document
/// explaining this syntax is exactly the document that must not have it applied. Scanning
/// the source text would need a hand-rolled guard for fenced code, indented code, inline
/// code and raw HTML, and would get one of them wrong. On the tree the question does not
/// arise: ``InlineCode``, ``CodeBlock``, ``InlineHTML`` and ``HTMLBlock`` hold their content
/// as strings rather than as ``Text`` children, so a rewriter that only splits ``Text`` runs
/// can never reach inside one.
///
/// ## Strictness
///
/// A comment is a closed span or it is prose. Half a marker must never swallow the rest of
/// a document, and an empty one is not a comment. The cost of being wrong is words deleted
/// from someone's writing, so every doubtful case stays as the author typed it.
enum CriticMarkupParser {

    static let opener = "{>>"
    static let closer = "<<}"

    /// Take the comments in `document` out of the text and into ``InlineComment`` elements.
    static func claim(in document: Document) -> Document {
        var rewriter = Rewriter()
        return rewriter.visit(document) as? Document ?? document
    }

    /// The first comment in `text`, as the text before it, its body, and the text after —
    /// or nil if there isn't one.
    static func split(_ text: String) -> (before: String, body: String, after: String)? {
        guard let open = text.range(of: opener),
              let close = text.range(of: closer, range: open.upperBound..<text.endIndex)
        else { return nil }                                     // no closer: prose

        let raw = String(text[open.upperBound..<close.lowerBound])
        // A body may not contain another opener. CriticMarkup does not nest, and treating
        // `{>> a {>> b <<}` as one comment would silently eat the first marker.
        guard !raw.contains(opener) else { return nil }
        // A lone `{` or `}` in a body is fine — the closer is the three-character `<<}`, so
        // `{>> fix the {x} token <<}` is unambiguous. This is deliberately looser than
        // AttributeBlockParser, whose closer is a single brace.
        let body = raw.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }                 // `{>><<}` is prose

        return (String(text[text.startIndex..<open.lowerBound]),
                body,
                String(text[close.upperBound...]))
    }

    // MARK: - The rewriter

    private struct Rewriter: MarkupRewriter {
        mutating func defaultVisit(_ markup: Markup) -> Markup? {
            markup.withUncheckedChildren(claimComments(in: markup.children.compactMap { visit($0) }))
        }

        /// A rewriter returns one node per visit, and splitting a run of text yields
        /// several — so the split happens where children are rebuilt, not in a
        /// `visitText`. Same shape as `AttributeBlockParser.claimImages`, for the same
        /// reason.
        private func claimComments(in children: [Markup]) -> [Markup] {
            var rebuilt: [Markup] = []
            for child in children {
                guard let text = child as? Text else { rebuilt.append(child); continue }
                var rest = text.string
                var claimed = false
                while let piece = CriticMarkupParser.split(rest) {
                    claimed = true
                    if !piece.before.isEmpty { rebuilt.append(Text(piece.before)) }
                    rebuilt.append(InlineComment(piece.body))
                    rest = piece.after
                }
                // Text before, between and after all survive. An empty tail is dropped
                // rather than left as an empty `Text`, which every walker would otherwise
                // have to know to skip.
                if !claimed { rebuilt.append(child) }
                else if !rest.isEmpty { rebuilt.append(Text(rest)) }
            }
            return rebuilt
        }
    }
}
