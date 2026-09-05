/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Mathematics written in a line of prose, as `$$ … $$`.
///
///     The area of a circle is $$\pi r^2$$, which is inline.
///
/// Requires ``ParseOptions/parseMath``. Without it the dollar signs are ordinary text —
/// which is how a document explaining the syntax quotes it.
///
/// > Note: ``tex`` is the SOURCE, character for character, and it has to be. TeX is written
/// in exactly the characters Markdown reserves: `\\` ends a row of a matrix, `\,` is a thin
/// space, `*` multiplies, `_` subscripts. cmark resolves an escape and pairs an emphasis
/// long before anything looks for a formula, so `$$f(x)\,dx$$` reaches a rewriter as
/// `f(x),dx` and `$$x = *y*$$` reaches it as three separate nodes. The parsed tree cannot
/// carry a formula, whatever delimiters are chosen. Reading the file is the only sound way,
/// and it is why a claim without a source declines rather than guessing.
///
/// > Note: ``plainText`` is the TeX. A heading whose title is a formula has to contribute
/// SOMETHING to a slug, a contents entry and an outline — two headings differing only by
/// their mathematics would otherwise collide into one anchor — and the source is the one
/// answer that is stable, searchable and the author's own words.
public struct InlineMath: RecurringInlineMarkup {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .inlineMath = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: InlineMath.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension InlineMath {
    /// Create inline mathematics from TeX, and optionally where in the file it came from.
    ///
    /// A formula claimed from a parse carries its source range, which is what lets an editor
    /// find the characters again — two formulas may say the same thing, and only a position
    /// tells them apart. One built by hand has none, because there is no file for it to be in.
    init(_ tex: String, range: SourceRange? = nil) {
        try! self.init(.inlineMath(tex: tex, parsedRange: range))
    }

    /// The TeX between the fences, with the surrounding space trimmed: `\pi r^2` for
    /// `$$\pi r^2$$`. Exactly as the file has it — see the note on this type.
    var tex: String {
        get {
            guard case let .inlineMath(tex) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return tex
        }
        set {
            guard tex != newValue else { return }
            _data = _data.replacingSelf(.inlineMath(tex: newValue, parsedRange: nil))
        }
    }

    /// The TeX, so a formula in a heading still reaches that heading's slug, its contents
    /// entry and the PDF outline. See the note on this type for why it is the source rather
    /// than nothing or a rendered approximation.
    var plainText: String { tex }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitInlineMath(self)
    }
}
