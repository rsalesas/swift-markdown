/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Parses Pandoc's fenced divs — `::: name` … `:::` — into ``FencedDiv`` elements.
///
/// ## Why two passes
///
/// A `:::` line means nothing inside a code block, and knowing where the code blocks are
/// is most of the problem. Tracking fences by scanning line prefixes gets it wrong in
/// several ways at once: an indented code block has no fence to track, a ```` ``` ````
/// inside a `~~~` block looks like a close, and a fence longer than three characters is
/// closed early by a shorter one inside it.
///
/// So this asks cmark instead. Pass one parses the document as it stands and notes which
/// lines belong to a code block; pass two parses it again with the marker lines blanked,
/// and the markers are re-applied as containers. cmark is the authority on what is code,
/// which is exactly the knowledge a line scanner does not have.
///
/// ## Why the whole document, twice
///
/// The obvious alternative — parse each region between markers on its own and nest the
/// results — breaks anything whose scope is the document. A footnote reference inside a
/// div would be parsed in a sub-document with no matching definition and turn back into
/// literal text; link reference definitions would go the same way. Parsing the whole
/// document in one piece keeps every such scope exactly as it is without the feature.
///
/// Only whole lines are blanked, so every other line keeps its number and its columns:
/// source locations are exact rather than adjusted after the fact.
enum FencedDivParser {

    /// An opening or closing marker found in the source.
    private struct Marker {
        /// 1-based.
        var line: Int
        /// The text after the colons. Empty means a closer.
        var attributeText: String
        var isOpener: Bool { !attributeText.isEmpty }
    }

    static func parse(_ input: String, source: URL?, options: ParseOptions) -> Document {
        // Pass one. Also the answer for a document with no divs in it: one parse, and no
        // cost paid by documents that don't use the feature.
        let first = MarkupParser.parseString(input, source: source, options: options)
        guard input.contains(":::") else { return first }

        let opaque = opaqueLines(of: first)
        var lines = input.components(separatedBy: "\n")
        var candidates: [Marker] = []
        for index in lines.indices {
            let number = index + 1
            guard !opaque.contains(number), let marker = self.marker(on: lines[index], line: number)
            else { continue }
            candidates.append(marker)
        }

        // A closer with nothing open closes nothing — it is text the author wrote, and
        // it has to survive into the document. Work out which markers actually do
        // something BEFORE blanking any line, or a stray `:::` is silently deleted.
        var depth = 0
        let markers = candidates.filter { marker in
            if marker.isOpener {
                depth += 1
                return true
            }
            guard depth > 0 else { return false }
            depth -= 1
            return true
        }
        guard !markers.isEmpty else { return first }

        // Blank the whole line. A blank line is a block separator, which is what the
        // marker was standing in for anyway, and it leaves every other line's number
        // and columns untouched.
        for marker in markers { lines[marker.line - 1] = "" }

        let second = MarkupParser.parseString(lines.joined(separator: "\n"), source: source, options: options)
        return nest(second, by: markers)
    }

    /// Line numbers that belong to a code block or a raw HTML block, and so cannot carry
    /// a marker.
    ///
    /// `HTMLBlock` is in here for the same reason as `CodeBlock`: a `:::` inside an
    /// author's own `<div>…</div>` is part of that block's text, and rewriting it would
    /// break the block.
    private static func opaqueLines(of document: Document) -> Set<Int> {
        var lines: Set<Int> = []
        func walk(_ markup: Markup) {
            if markup is CodeBlock || markup is HTMLBlock, let range = markup.range {
                for line in range.lowerBound.line...range.upperBound.line { lines.insert(line) }
            }
            for child in markup.children { walk(child) }
        }
        walk(document)
        return lines
    }

    /// A marker line, or nil.
    ///
    /// Three or more colons, then either a spec (an opener) or nothing (a closer).
    private static func marker(on line: String, line number: Int) -> Marker? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(":::") else { return nil }
        let spec = trimmed.drop(while: { $0 == ":" }).trimmingCharacters(in: .whitespaces)
        return Marker(line: number, attributeText: spec)
    }

    /// Re-apply the markers, wrapping the blocks between each opener and its closer.
    private static func nest(_ document: Document, by markers: [Marker]) -> Document {
        var blocks = Array(document.children.map { $0.raw.markup })
        // Footnote definitions are hoisted to the end of the document by cmark, and a
        // definition's position among the children IS its number. Wrapping one inside a
        // div by its source position would undo that: the definition would move, the
        // numbering would shift, and a renderer looking for definitions at the top level
        // would find nothing. They stay where cmark put them.
        var pinned: [RawMarkup] = []
        blocks.removeAll { block in
            guard case .footnoteDefinition = block.data else { return false }
            pinned.append(block)
            return true
        }

        var openers: [(marker: Marker, collected: [RawMarkup])] = []
        var top: [RawMarkup] = []
        var next = 0

        /// Blocks that begin before `line`, in order.
        func take(before line: Int) -> [RawMarkup] {
            var taken: [RawMarkup] = []
            while next < blocks.count {
                guard let start = blocks[next].parsedRange?.lowerBound.line, start < line else { break }
                taken.append(blocks[next])
                next += 1
            }
            return taken
        }

        func append(_ children: [RawMarkup]) {
            if openers.isEmpty { top += children } else { openers[openers.count - 1].collected += children }
        }

        for marker in markers {
            append(take(before: marker.line))
            if marker.isOpener {
                openers.append((marker, []))
            } else if let open = openers.popLast() {
                append([.fencedDiv(attributeText: open.marker.attributeText,
                                   parsedRange: nil, open.collected)])
            }
            // Every closer reaching here matches an opener: the stray ones were filtered
            // out above and left in the text as the content they are.
        }
        append(take(before: Int.max))

        // An unclosed div runs to the end of the document rather than being dropped —
        // forgiving the author is better than swallowing their text.
        while let open = openers.popLast() {
            let div = RawMarkup.fencedDiv(attributeText: open.marker.attributeText,
                                          parsedRange: nil, open.collected)
            if openers.isEmpty { top.append(div) } else { openers[openers.count - 1].collected.append(div) }
        }

        return try! Document(.document(parsedRange: document.range, top + pinned))
    }
}
