/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// An editorial comment, written as CriticMarkup's `{>> … <<}`.
///
///     The term expires in 12 months.{>> RS: is that right? <<}
///
/// A comment is *about* the document rather than part of it — a reviewer's question, a note
/// to a co-author. Markdown has no way to say that, so a comment has to be either a
/// separate file, which nothing else can see, or a convention. CriticMarkup is the
/// convention, and iA Writer, Ulysses and Marked already speak it.
///
/// Requires ``ParseOptions/parseComments``. Without it, `{>> … <<}` is ordinary text — which
/// is how a document explaining the syntax quotes it.
///
/// > Note: ``plainText`` is empty, deliberately. Plain text is what a reader sees, and a
/// comment is not that — so a comment inside a heading does not reach the heading's title,
/// its anchor, a table of contents or an outline. One decision, in one place.
///
/// > Note: the body is a single run of text. A comment cannot span a line break, and cannot
/// contain live inline markup — `{>> don't use *this* <<}` is emphasis between two runs of
/// text, so no comment is recognised and the braces stay visible. Anything writing comments
/// programmatically should escape the body accordingly.
public struct InlineComment: InlineMarkup {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .inlineComment = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: InlineComment.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension InlineComment {
    /// Create a comment with the given body.
    init(_ body: String) {
        try! self.init(.inlineComment(body: body, parsedRange: nil))
    }

    /// What the comment says, without its fences and with the surrounding space trimmed:
    /// `RS: is that right?` for `{>> RS: is that right? <<}`.
    ///
    /// Stored verbatim. CriticMarkup has no notion of an author, so a convention like
    /// `initials: text` is the caller's to read — putting it here would bake one
    /// application's habit into a general parser.
    var body: String {
        get {
            guard case let .inlineComment(body) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return body
        }
        set {
            guard body != newValue else { return }
            _data = _data.replacingSelf(.inlineComment(body: newValue, parsedRange: nil))
        }
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitInlineComment(self)
    }

    // MARK: PlainTextConvertibleMarkup

    /// Empty, deliberately — see the note on ``InlineComment``. This is what keeps a comment
    /// out of a heading's title, its slug, the contents page and the PDF outline, without
    /// any of those four having to know comments exist.
    var plainText: String {
        return ""
    }
}
