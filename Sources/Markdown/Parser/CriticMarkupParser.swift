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
    /// Take the comments in `document` out of the text and into ``InlineComment`` elements.
    ///
    /// `source` is the file the document was parsed from, and giving it here is what lets a
    /// claimed comment keep a real ``Markup/range``. The text run holding a comment already
    /// knows which characters of the file it came from; the comment inside it is found by
    /// reading THOSE characters rather than by counting through the parsed string, which
    /// smart punctuation has already changed the length of.
    static func claim(in document: Document, source: String? = nil) -> Document {
        var rewriter = Rewriter(index: source.map(SourceByteIndex.init))
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
        /// The file, for reading a comment's own characters back out of it. Nil when the
        /// caller did not offer one, and then a claimed comment carries no range — which is
        /// how this behaved before ranges existed at all.
        let index: SourceByteIndex?

        /// Untouched nodes are handed back untouched, which is the whole performance story
        /// of this pass.
        ///
        /// `withUncheckedChildren` rebuilds the node AND every ancestor above it, and
        /// rebuilding an ancestor copies that ancestor's entire child list. Rebuild every
        /// node in a document and each of its blocks copies the document's block list once:
        /// the cost is the document squared. A thousand one-line paragraphs took 0.8s to
        /// parse, four times what five hundred took — and a document with no comments in it
        /// anywhere paid exactly the same, because rebuilding did not depend on finding
        /// anything. Now nothing is rebuilt unless a comment was actually claimed beneath it.
        mutating func defaultVisit(_ markup: Markup) -> Markup? {
            var children: [Markup] = []
            children.reserveCapacity(markup.childCount)
            var changed = false
            for child in markup.children {
                guard let visited = visit(child) else { changed = true; continue }
                // Identity, not equality: a child that came back as the very same raw node
                // is one this pass had no interest in.
                if visited.raw.markup !== child.raw.markup { changed = true }
                children.append(visited)
            }
            let claimed = claimComments(in: children, changed: &changed)
            guard changed else { return markup }
            return markup.withUncheckedChildren(claimed)
        }

        /// A rewriter returns one node per visit, and splitting a run of text yields
        /// several — so the split happens where children are rebuilt, not in a
        /// `visitText`. Same shape as `AttributeBlockParser.claimImages`, for the same
        /// reason.
        private func claimComments(in children: [Markup], changed: inout Bool) -> [Markup] {
            var rebuilt: [Markup] = []
            for child in children {
                guard let text = child as? Text else { rebuilt.append(child); continue }
                // Where this run came from, and how far into it the search has got. The
                // markers are `{`, `>`, `<` and `}`, none of which smart punctuation
                // touches, so the nth comment in the parsed string is the nth in the source
                // — which is what makes reading the two in step exact rather than a guess.
                var window = text.range.flatMap { index?.text(in: $0) }
                var rest = text.string
                var claimed = false
                while let piece = CriticMarkupParser.split(rest) {
                    claimed = true
                    if !piece.before.isEmpty { rebuilt.append(Text(piece.before)) }
                    rebuilt.append(InlineComment(piece.body, range: sourceSpan(in: &window)))
                    rest = piece.after
                }
                // Text before, between and after all survive. An empty tail is dropped
                // rather than left as an empty `Text`, which every walker would otherwise
                // have to know to skip.
                if !claimed { rebuilt.append(child) }
                else {
                    changed = true
                    if !rest.isEmpty { rebuilt.append(Text(rest)) }
                }
            }
            return rebuilt
        }

        /// The next comment's span in the source window, advancing the window past it.
        ///
        /// Nil when there is no window — no source was offered — or when the file does not
        /// hold what the parse says it does, which would mean this code has misunderstood
        /// something and had better say so by declining rather than by pointing somewhere.
        private func sourceSpan(in window: inout Substring?) -> SourceRange? {
            guard let index, var remaining = window,
                  let open = remaining.range(of: CriticMarkupParser.opener),
                  let close = remaining.range(of: CriticMarkupParser.closer,
                                              range: open.upperBound..<remaining.endIndex)
            else { window = nil; return nil }
            remaining = remaining[close.upperBound...]
            window = remaining
            return index.range(of: open.lowerBound..<close.upperBound)
        }
    }
}
