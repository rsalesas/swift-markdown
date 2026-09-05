/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Claims mathematics — `$$ … $$` — as ``InlineMath`` and ``DisplayMath`` elements.
///
/// ## Why this runs on the tree
///
/// The same reason `CriticMarkupParser` does: ``InlineCode``, ``CodeBlock``, ``InlineHTML``
/// and ``HTMLBlock`` hold their content as strings rather than as ``Text`` children, so a
/// rewriter that only splits ``Text`` cannot reach inside one. A document explaining this
/// syntax is exactly the document that must not have it applied to its examples.
///
/// ## Why the TeX comes from the FILE and not from the tree
///
/// This is the difference from every other claim in this library, and it is not a detail.
/// TeX is written in the characters Markdown reserves. By the time a rewriter sees a
/// paragraph, cmark has already:
///
/// - resolved backslash escapes, so `f(x)\,dx` is `f(x),dx` — the thin space is gone, and
///   `\\`, which ends a row of a matrix, has become a single backslash;
/// - paired emphasis, so `x = *y*` is three nodes and not one;
/// - curled quotes and dashes, if smart punctuation is on, which it usually is.
///
/// So the parsed tree cannot carry a formula, whatever delimiters are chosen — the question
/// is not which fences survive but whether the CONTENT does, and it does not. The fences are
/// found in the tree, because that is what keeps code samples safe; the TeX between them is
/// then read out of the file, character for character.
///
/// A claim with no source therefore takes nothing. There is no half-answer available: a
/// formula built from the parsed text would be a formula the author did not write.
///
/// ## Inline or display
///
/// One delimiter, and position decides. A paragraph that is nothing but one formula is a
/// ``DisplayMath``; a formula inside a sentence is an ``InlineMath``. See ``DisplayMath``
/// for why `$ … $` is not offered as a second, inline fence.
///
/// ## Strictness
///
/// A formula is a closed span or it is prose. An empty one (`$$$$`) is not a formula. A span
/// may cross a soft line break, because display mathematics is written across lines — but it
/// cannot leave its own block, so an unclosed `$$` can never swallow more than the paragraph
/// it was typed in.
enum MathParser {

    static let fence = "$$"

    /// Take the mathematics in `document` into ``InlineMath`` and ``DisplayMath`` elements.
    ///
    /// `source` is the file the document was parsed from, and without it nothing is claimed
    /// — see the note on this type.
    static func claim(in document: Document, source: String? = nil) -> Document {
        guard let source else { return document }
        var rewriter = Rewriter(index: SourceByteIndex(source))
        return rewriter.visit(document) as? Document ?? document
    }

    /// Where a formula begins and ends across a run of siblings.
    struct Fenced {
        let open: Int
        let openAt: Range<String.Index>
        let close: Int
        let closeAt: Range<String.Index>
    }

    /// The first `$$ … $$` in `children`, or nil.
    ///
    /// Unlike `TrackedChangeParser.firstMarked` this crosses a soft break, because a display
    /// formula is written across lines. It cannot cross anything else: the search runs over
    /// one inline container's children, so it stops where the block does.
    static func firstFenced(in children: [Markup]) -> Fenced? {
        for index in children.indices {
            guard let text = children[index] as? Text,
                  let open = text.string.range(of: fence) else { continue }
            var from: String.Index? = open.upperBound
            for candidate in index..<children.count {
                guard let inner = children[candidate] as? Text else {
                    // Anything else is content the formula spans — an emphasis cmark paired
                    // inside it, say. The TeX is read from the file, so whatever the parse
                    // made of those characters does not matter here.
                    from = nil
                    continue
                }
                let start = from ?? inner.string.startIndex
                from = nil
                guard let close = inner.string.range(of: fence, range: start..<inner.string.endIndex)
                else { continue }
                return Fenced(open: index, openAt: open, close: candidate, closeAt: close)
            }
            return nil          // this opener never closes, and no later one can be first
        }
        return nil
    }

    // MARK: - The rewriter

    private struct Rewriter: MarkupRewriter {
        let index: SourceByteIndex

        /// Untouched nodes are handed back untouched — see `CriticMarkupParser.Rewriter`
        /// for what rebuilding one costs and why identity is the test.
        mutating func defaultVisit(_ markup: Markup) -> Markup? {
            var children: [Markup] = []
            children.reserveCapacity(markup.childCount)
            var changed = false
            for child in markup.children {
                guard let visited = visit(child) else { changed = true; continue }
                if visited.raw.markup !== child.raw.markup { changed = true }
                children.append(visited)
            }
            // Each run's own window on the file. Only original runs have one; anything an
            // earlier pass built belongs to no file, and a formula inside one cannot be read.
            let windows = children.map { child -> Substring? in
                guard let text = child as? Text, let range = text.range else { return nil }
                return index.text(in: range)
            }
            let claimed = claimMath(in: children, windows: windows, changed: &changed)
            guard changed else { return markup }
            return markup.withUncheckedChildren(claimed)
        }

        /// A paragraph that is nothing but one formula is display mathematics.
        ///
        /// Decided after the children are claimed, so the question is simply whether one
        /// `InlineMath` is all that is left. Blank text and the soft breaks around a formula
        /// written across lines do not count against it — they are how the author laid it
        /// out, not content beside it.
        mutating func visitParagraph(_ paragraph: Paragraph) -> Markup? {
            guard let visited = defaultVisit(paragraph) as? Paragraph else { return nil }
            let meaningful = visited.children.filter { child in
                if child is SoftBreak || child is LineBreak { return false }
                if let text = child as? Text {
                    return !text.string.trimmingCharacters(in: .whitespaces).isEmpty
                }
                return true
            }
            guard meaningful.count == 1, let math = meaningful.first as? InlineMath else {
                return visited
            }
            return DisplayMath(math.tex, range: math.range)
        }

        /// Recursive on the tail, which is what finds the second formula in a sentence.
        private func claimMath(in children: [Markup], windows: [Substring?],
                               changed: inout Bool) -> [Markup] {
            guard let span = MathParser.firstFenced(in: children),
                  let opening = children[span.open] as? Text,
                  let closing = children[span.close] as? Text,
                  let located = sourceSpan(of: span, opening: opening, closing: closing,
                                           openWindow: windows[span.open],
                                           closeWindow: windows[span.close])
            else { return children }
            // `$$$$` is prose, and so is a fence pair holding only space.
            let tex = located.tex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tex.isEmpty else { return children }
            changed = true

            var rebuilt = Array(children[children.startIndex..<span.open])
            let head = String(opening.string[opening.string.startIndex..<span.openAt.lowerBound])
            if !head.isEmpty { rebuilt.append(text(head, from: located.head)) }
            rebuilt.append(InlineMath(tex, range: index.range(of: located.span)))

            // What follows, with the rest of the file it came from — which is how a second
            // formula on the same line still knows where it is.
            var rest: [Markup] = []
            var restWindows: [Substring?] = []
            let after = String(closing.string[span.closeAt.upperBound...])
            if !after.isEmpty {
                rest.append(text(after, from: located.remaining))
                restWindows.append(located.remaining)
            }
            rest.append(contentsOf: children[(span.close + 1)...])
            restWindows.append(contentsOf: windows[(span.close + 1)...])
            var more = false
            rebuilt.append(contentsOf: claimMath(in: rest, windows: restWindows, changed: &more))
            return rebuilt
        }

        /// Where in the file this formula's fences are, and the TeX between them.
        ///
        /// `$$` is two ASCII characters smart punctuation never touches, so the nth `$$` in a
        /// parsed run is the nth in the source that run came from. Counting them is therefore
        /// exact across a run whose parsed text is a different length from its source — which,
        /// for a run with TeX in it, is every one of them.
        ///
        /// Nil when either end has no window: the runs were built by an earlier pass and
        /// belong to no file, so there is no TeX to read and nothing is claimed.
        private func sourceSpan(of span: Fenced, opening: Text, closing: Text,
                                openWindow: Substring?, closeWindow: Substring?)
            -> (head: Substring, span: Range<String.Index>, tex: String, remaining: Substring)? {
            guard let openWindow, let closeWindow,
                  let start = nth(fencesBefore: span.openAt.lowerBound, in: opening.string,
                                  within: openWindow, takingEnd: false),
                  let end = nth(fencesBefore: span.closeAt.lowerBound, in: closing.string,
                                within: closeWindow, takingEnd: true),
                  start < end else { return nil }
            let source = index.source
            let afterOpen = source.index(start, offsetBy: MathParser.fence.count)
            let beforeClose = source.index(end, offsetBy: -MathParser.fence.count)
            guard afterOpen <= beforeClose else { return nil }
            return (openWindow[..<start], start..<end,
                    String(source[afterOpen..<beforeClose]), closeWindow[end...])
        }

        /// The same occurrence of `$$` in `window` as the one at `position` in `parsed`.
        private func nth(fencesBefore position: String.Index, in parsed: String,
                         within window: Substring, takingEnd: Bool) -> String.Index? {
            var count = 0
            var cursor = parsed.startIndex
            while let found = parsed.range(of: MathParser.fence, range: cursor..<parsed.endIndex),
                  found.lowerBound < position {
                count += 1
                cursor = found.upperBound
            }
            var remaining = window
            var found: Range<Substring.Index>?
            for _ in 0...count {
                guard let next = remaining.range(of: MathParser.fence) else { return nil }
                found = next
                remaining = remaining[next.upperBound...]
            }
            return found.map { takingEnd ? $0.upperBound : $0.lowerBound }
        }

        /// A run of text this rewriter built, keeping the piece of the file it came from —
        /// so a later pass, and a second formula, can still read the source.
        private func text(_ string: String, from window: Substring?) -> Text {
            guard let window,
                  let range = index.range(of: window.startIndex..<window.endIndex),
                  let located = try? Text(.text(parsedRange: range, string: string))
            else { return Text(string) }
            return located
        }
    }
}
