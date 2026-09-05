/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Mathematics set on its own, as a block:
///
///     $$
///     \int_{a}^{b} f(x)\,dx = F(b) - F(a)
///     $$
///
/// Requires ``ParseOptions/parseMath``.
///
/// ## Why position decides, and not a second delimiter
///
/// There is one delimiter, `$$ … $$`, and where it sits is what makes it display: a formula
/// standing alone as a whole paragraph is a ``DisplayMath``, and the same formula inside a
/// sentence is an ``InlineMath``. One rule rather than two, and it costs nothing that a
/// second pair of fences would buy.
///
/// The alternative everyone reaches for first is `$ … $` for inline. It is rejected here
/// because a single dollar sign is not a delimiter in the documents this parser is for —
/// it is a currency symbol. `$1,200 and $50/hour` would open a formula and close it four
/// words later, and no heuristic about surrounding spaces makes that safe rather than
/// usually-safe. Two dollars in a row mean something; one never does.
///
/// > Note: ``tex`` is the SOURCE, character for character. See ``InlineMath`` for why the
/// parsed tree cannot carry a formula and this has to read the file.
public struct DisplayMath: BlockMarkup {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .displayMath = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: DisplayMath.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension DisplayMath {
    /// Create display mathematics from TeX, and optionally where in the file it came from.
    init(_ tex: String, range: SourceRange? = nil) {
        try! self.init(.displayMath(tex: tex, parsedRange: range))
    }

    /// The TeX between the fences, with the surrounding whitespace trimmed. A formula
    /// written across several lines keeps its newlines — they are the author's layout, and
    /// TeX gives some of them meaning.
    var tex: String {
        get {
            guard case let .displayMath(tex) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return tex
        }
        set {
            guard tex != newValue else { return }
            _data = _data.replacingSelf(.displayMath(tex: newValue, parsedRange: nil))
        }
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitDisplayMath(self)
    }
}
