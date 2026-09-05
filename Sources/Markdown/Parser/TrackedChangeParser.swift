/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Claims CriticMarkup's tracked changes — `{++ins++}`, `{--del--}`, `{~~old~>new~~}` and
/// `{==highlight==}` — as ``TrackedChange`` elements.
///
/// ## Why this runs on the tree
///
/// The same reason `CriticMarkupParser` does: ``InlineCode``, ``CodeBlock``, ``InlineHTML``
/// and ``HTMLBlock`` hold their content as strings rather than as ``Text`` children, so a
/// rewriter that only splits ``Text`` cannot reach inside one. A document explaining this
/// syntax is exactly the document that must not have it applied to its examples.
///
/// ## The difference from a comment
///
/// A comment's body is a string. A tracked change's content is CHILDREN, because it is real
/// document text: `{++some *emphasised* words++}` has to keep its emphasis, since accepting
/// the change puts those words into the document. That is what makes this a container and
/// what makes the scan cross siblings — cmark parsed the emphasis long before anything
/// looked for a marker, so `{++a *b* c++}` arrives as three siblings with the markers at
/// either end of the run.
///
/// ## Strictness
///
/// A change is a closed span or it is prose, and half a marker must never swallow the rest
/// of a document. Markers do not nest: a body containing another opener of the same kind is
/// refused rather than guessed at. The cost of being wrong is words changed in somebody's
/// writing, so every doubtful case stays as it was typed.
enum TrackedChangeParser {

    /// The fences, by kind. `MarkupFormatter` reads these back, so the round-trip cannot
    /// drift from the parse.
    static let fences: [TrackedChange.Kind: (open: String, close: String)] = [
        .insertion: ("{++", "++}"),
        .deletion: ("{--", "--}"),
        .substitution: ("{~~", "~~}"),
        .highlight: ("{==", "==}"),
    ]

    /// What separates a substitution's two halves.
    static let arrow = "~>"

    /// How a fence can appear in a PARSED TREE, which is not the source.
    ///
    /// Smart punctuation is on, so `{--deleted--}` reaches this rewriter as `{–deleted–}`:
    /// cmark turned each `--` into an en dash long before anything looked for a marker.
    /// Both spellings are accepted — the en dash is what a document actually contains — and
    /// `fences` above is what gets written back out, so a round-trip restores the plain
    /// one the author typed. The other three kinds use characters smart punctuation does
    /// not touch, and are their own single spelling.
    static let spellings: [TrackedChange.Kind: [(open: String, close: String)]] = [
        .insertion: [("{++", "++}")],
        .deletion: [("{--", "--}"), ("{\u{2013}", "\u{2013}}")],
        .substitution: [("{~~", "~~}")],
        .highlight: [("{==", "==}")],
    ]

    /// Take the tracked changes in `document` into ``TrackedChange`` elements.
    ///
    /// `source` is the file the document was parsed from, and giving it here is what lets a
    /// claimed change keep a real ``Markup/range``. The runs of text a change sits between
    /// already know which characters of the file they came from; the fences are found by
    /// reading THOSE characters rather than by counting through the parsed string, whose
    /// length smart punctuation has already changed.
    static func claim(in document: Document, source: String? = nil) -> Document {
        var rewriter = Rewriter(index: source.map(SourceByteIndex.init))
        return rewriter.visit(document) as? Document ?? document
    }

    /// Where a marked span begins and ends across a run of siblings.
    struct Marked {
        let kind: TrackedChange.Kind
        let open: Int
        let openAt: Range<String.Index>      // the opening fence
        let close: Int
        let closeAt: Range<String.Index>     // the closing fence
    }

    /// The first marked span in `children`, or nil.
    ///
    /// Earliest in the text wins, whatever its kind: `{--a--} {++b++}` claims the deletion
    /// first and the insertion on the pass over what follows it, rather than whichever kind
    /// a dictionary happened to offer first. Without that the tree would depend on hash
    /// order, which is the sort of thing that is right in every test and wrong one morning.
    static func firstMarked(in children: [Markup]) -> Marked? {
        var best: Marked?
        func isEarlier(_ candidate: Marked, than found: Marked) -> Bool {
            candidate.open != found.open
                ? candidate.open < found.open
                : candidate.openAt.lowerBound < found.openAt.lowerBound
        }
        for index in children.indices {
            guard let text = children[index] as? Text else { continue }
            for (kind, alternatives) in spellings {
                for pair in alternatives {
                    var from = text.string.startIndex
                    while let open = text.string.range(of: pair.open,
                                                       range: from..<text.string.endIndex) {
                        if let span = marked(kind: kind, closing: pair.close, in: children,
                                             openingAt: index, fence: open) {
                            if best == nil || isEarlier(span, than: best!) { best = span }
                            break
                        }
                        from = open.upperBound
                        if from == text.string.endIndex { break }
                    }
                }
            }
            // A span opening in this child cannot be beaten by one opening in a later one.
            if let best, best.open == index { return best }
        }
        return best
    }

    /// The span opened by `fence`, or nil if it is never closed.
    private static func marked(kind: TrackedChange.Kind, closing: String, in children: [Markup],
                               openingAt index: Int, fence open: Range<String.Index>) -> Marked? {
        var cursor: String.Index? = open.upperBound
        for child in index..<children.count {
            guard let text = children[child] as? Text else {
                // A change ends with the line it began on: cmark never puts a newline in a
                // `Text` node, so a marker still open at a break was never closed. Without
                // this the scan crosses the break and takes the next line with it.
                if children[child] is SoftBreak || children[child] is LineBreak { return nil }
                // Otherwise it is part of the content, so it has to be something a
                // `TrackedChange` can hold.
                guard children[child] is RecurringInlineMarkup else { return nil }
                cursor = nil
                continue
            }
            let from = cursor ?? text.string.startIndex
            cursor = nil
            guard let close = text.string.range(of: closing, range: from..<text.string.endIndex)
            else { continue }
            // A second opener of the same kind before the closer means this opener is not
            // the one that closer belongs to. Refusing it rather than reading across lets
            // the scan move on and find the well-formed span inside — `{++a {++b++}` is a
            // stray marker followed by an insertion, not an insertion of `a {++b`.
            if let opener = spellings[kind]?.first(where: { $0.close == closing })?.open,
               text.string.range(of: opener, range: from..<close.lowerBound) != nil { return nil }
            return Marked(kind: kind, open: index, openAt: open, close: child, closeAt: close)
        }
        return nil
    }

    // MARK: - The rewriter

    private struct Rewriter: MarkupRewriter {
        /// The file, for reading a change's own characters back out of it. Nil when the
        /// caller offered none, and then a claimed change carries no range.
        let index: SourceByteIndex?

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
            // Each run's own window on the file, so a change claimed between two of them can
            // say where it is. Only the original runs have one; anything this rewriter built
            // belongs to no file and carries nil.
            let windows = children.map { child -> Substring? in
                guard let text = child as? Text, let range = text.range else { return nil }
                return index?.text(in: range)
            }
            let claimed = claimChanges(in: children, windows: windows, changed: &changed)
            guard changed else { return markup }
            return markup.withUncheckedChildren(claimed)
        }

        /// Recursive on the tail, which is what finds the second and third change in a
        /// sentence, and on the content, so a highlight around an insertion works.
        private func claimChanges(in children: [Markup], windows: [Substring?],
                                  changed: inout Bool) -> [Markup] {
            guard let span = TrackedChangeParser.firstMarked(in: children),
                  let opening = children[span.open] as? Text,
                  let closing = children[span.close] as? Text else { return children }
            changed = true

            var rebuilt = Array(children[children.startIndex..<span.open])
            let head = String(opening.string[opening.string.startIndex..<span.openAt.lowerBound])
            if !head.isEmpty { rebuilt.append(Text(head)) }

            var content: [Markup] = []
            if span.open == span.close {
                let inner = String(opening.string[span.openAt.upperBound..<span.closeAt.lowerBound])
                if !inner.isEmpty { content.append(Text(inner)) }
            } else {
                let tail = String(opening.string[span.openAt.upperBound...])
                if !tail.isEmpty { content.append(Text(tail)) }
                content.append(contentsOf: children[(span.open + 1)..<span.close])
                let lead = String(closing.string[closing.string.startIndex..<span.closeAt.lowerBound])
                if !lead.isEmpty { content.append(Text(lead)) }
            }

            // A substitution's two halves are split on the first `~>`, and only when the
            // old half is one run of text — `{~~a~>b~~}` where the arrow falls between
            // siblings is not something this reading can express, so it stays prose.
            var replaced = ""
            if span.kind == .substitution {
                guard let first = content.first as? Text,
                      let arrow = first.string.range(of: TrackedChangeParser.arrow) else {
                    return children
                }
                replaced = String(first.string[first.string.startIndex..<arrow.lowerBound])
                let rest = String(first.string[arrow.upperBound...])
                content.removeFirst()
                if !rest.isEmpty { content.insert(Text(rest), at: 0) }
            }

            // A change inside a change is claimed from pieces this rewriter built, which
            // belong to no file — so it carries no range. They are the rarest thing here, and
            // an application that needs a position is better told there is not one.
            var nested = false
            content = claimChanges(in: content, windows: Array(repeating: nil, count: content.count),
                                   changed: &nested)
            let located = sourceSpan(of: span, opening: opening, closing: closing,
                                     openWindow: windows[span.open],
                                     closeWindow: windows[span.close])
            rebuilt.append(TrackedChange(kind: span.kind, replaced: replaced,
                                         range: located.range,
                                         content.compactMap { $0 as? RecurringInlineMarkup }))

            // What follows the change, with the rest of the file it came from — which is how
            // a second change on the same line still knows where it is.
            var rest: [Markup] = []
            var restWindows: [Substring?] = []
            let after = String(closing.string[span.closeAt.upperBound...])
            if !after.isEmpty {
                rest.append(Text(after))
                restWindows.append(located.remaining)
            }
            rest.append(contentsOf: children[(span.close + 1)...])
            restWindows.append(contentsOf: windows[(span.close + 1)...])
            var more = false
            rebuilt.append(contentsOf: claimChanges(in: rest, windows: restWindows, changed: &more))
            return rebuilt
        }

        /// Where in the file this change's markers are.
        ///
        /// The fences are ASCII that smart punctuation never touches, so the nth occurrence
        /// of one in a parsed run is the nth in the source that run came from. Counting the
        /// occurrences is therefore exact, and is what keeps this honest across a run whose
        /// parsed text is a different length from its source — which is most of them.
        ///
        /// Nil for a change claimed inside another: the pieces it sits between were built by
        /// this rewriter and belong to no file. Nested changes are the rarest thing here and
        /// an application that needs a position is better told there isn't one.
        private func sourceSpan(of span: Marked, opening: Text, closing: Text,
                                openWindow: Substring?, closeWindow: Substring?)
            -> (range: SourceRange?, remaining: Substring?) {
            guard let index, let openWindow, let closeWindow,
                  let fence = TrackedChangeParser.spellings[span.kind]
            else { return (nil, nil) }
            // Which spelling of this kind's opener actually matched, since a deletion has two.
            let opened = String(opening.string[span.openAt.lowerBound..<span.openAt.upperBound])
            let closed = String(closing.string[span.closeAt.lowerBound..<span.closeAt.upperBound])
            guard fence.contains(where: { $0.open == opened && $0.close == closed })
            else { return (nil, nil) }
            guard let start = nth(occurrencesOf: opened, before: span.openAt.lowerBound,
                                  in: opening.string, within: openWindow,
                                  spelled: fence.map(\.open), takingEnd: false),
                  let end = nth(occurrencesOf: closed, before: span.closeAt.lowerBound,
                                in: closing.string, within: closeWindow,
                                spelled: fence.map(\.close), takingEnd: true),
                  start < end else { return (nil, nil) }
            return (index.range(of: start..<end), closeWindow[end...])
        }

        /// The same occurrence of a fence in `window` as the one at `position` in `parsed`.
        ///
        /// `spelled` is every way this kind's fence can be written, and it exists for the
        /// deletion. Smart punctuation turns each `--` into an en dash, so the run reaching
        /// this rewriter says `{–gone–}` while the file says `{--gone--}`: searching the file
        /// for the spelling the PARSE used would find nothing at all. Counting openers of
        /// the kind, whichever way each is written, keeps the two in step — and it has to
        /// count them together, since a file may hold both spellings and the parse will have
        /// flattened them to one.
        private func nth(occurrencesOf needle: String, before position: String.Index,
                         in parsed: String, within window: Substring,
                         spelled: [String], takingEnd: Bool) -> String.Index? {
            var count = 0
            var cursor = parsed.startIndex
            while let found = parsed.range(of: needle, range: cursor..<parsed.endIndex),
                  found.lowerBound < position {
                count += 1
                cursor = found.upperBound
            }
            var remaining = window
            var found: Range<Substring.Index>?
            for _ in 0...count {
                guard let next = earliest(of: spelled, in: remaining) else { return nil }
                found = next
                remaining = remaining[next.upperBound...]
            }
            return found.map { takingEnd ? $0.upperBound : $0.lowerBound }
        }

        /// The first place any of these spellings appears.
        private func earliest(of spellings: [String],
                              in text: Substring) -> Range<Substring.Index>? {
            spellings.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        }
    }
}
