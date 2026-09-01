/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A run of blank lines an author left between two blocks, beyond the one that separates
/// them.
///
///     Yours sincerely,
///
///
///
///     Robert Salesas
///
/// Three blank lines there is a `BlankLines` with a ``count`` of two: the first is the
/// paragraph break, and the rest is the space left for a signature.
///
/// Requires ``ParseOptions/preserveBlankLines``. Without it — and in every other Markdown
/// renderer — one blank line and five mean the same thing.
///
/// > Note: This is a *presentational* element, and the only one in this library. It
/// carries no content and says nothing about what the document means; it records that the
/// author left a gap, for a renderer that is laying pages out rather than reflowing them.
/// A renderer that does not care may ignore it entirely.
public struct BlankLines: BlockMarkup {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .blankLines = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: BlankLines.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension BlankLines {
    /// Create a run of blank lines.
    init(count: Int) {
        try! self.init(.blankLines(count: count, parsedRange: nil))
    }

    /// How many blank lines the author left beyond the one that separates the blocks.
    var count: Int {
        get {
            guard case let .blankLines(count) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return count
        }
        set {
            guard count != newValue else { return }
            _data = _data.replacingSelf(.blankLines(count: newValue, parsedRange: nil))
        }
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitBlankLines(self)
    }
}
