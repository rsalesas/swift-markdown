/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Turning a ``SourceLocation`` back into a position in the file it came from.
///
/// Two things make this less obvious than it looks, and both are why it is written down once
/// rather than at each call site.
///
/// **Columns are UTF-8 BYTES, not characters.** cmark counts them that way, so `Ünïcödé
/// ahead` is thirteen characters and seventeen columns. Treating a column as a character
/// offset is right for ASCII and quietly wrong for every document that is not.
///
/// **A parsed string is not the source.** Smart punctuation means `Don't -- really` comes
/// back as `Don’t – really`: shorter, and shorter by an amount that depends on what the
/// author wrote. So nothing may be located by counting through the parsed text. A node's
/// RANGE, on the other hand, is honest — it says which characters of the file the node came
/// from — which is what makes going back to the source and reading it directly the only
/// sound way to find anything.
struct SourceByteIndex {
    let source: String
    /// UTF-8 offset at which each line begins, indexed from zero for line 1.
    private let lineStarts: [Int]

    init(_ source: String) {
        self.source = source
        var starts = [0]
        for (offset, byte) in source.utf8.enumerated() where byte == 0x0A {
            starts.append(offset + 1)
        }
        self.lineStarts = starts
    }

    /// The position in `source` a parsed location refers to, or nil if it names somewhere
    /// the file does not have — or somewhere inside a character rather than between two.
    func index(of location: SourceLocation) -> String.Index? {
        guard location.line >= 1, location.line <= lineStarts.count, location.column >= 1
        else { return nil }
        let offset = lineStarts[location.line - 1] + (location.column - 1)
        guard offset <= source.utf8.count else { return nil }
        let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
        return String.Index(utf8Index, within: source)
    }

    /// The text a parsed range covers, exactly as the file has it.
    func text(in range: SourceRange) -> Substring? {
        guard let lower = index(of: range.lowerBound),
              let upper = index(of: range.upperBound),
              lower <= upper else { return nil }
        return source[lower..<upper]
    }

    /// A `SourceRange` for a span of the file, so a node claimed from the tree can say where
    /// it came from in the same terms every other node uses.
    func range(of span: Range<String.Index>) -> SourceRange? {
        guard let start = location(of: span.lowerBound),
              let end = location(of: span.upperBound) else { return nil }
        return start..<end
    }

    private func location(of index: String.Index) -> SourceLocation? {
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: index.samePosition(in: source.utf8) ?? source.utf8.startIndex)
        guard let line = lineStarts.lastIndex(where: { $0 <= offset }) else { return nil }
        return SourceLocation(line: line + 1, column: offset - lineStarts[line] + 1, source: nil)
    }
}
