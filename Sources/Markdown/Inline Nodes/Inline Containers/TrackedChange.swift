/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A tracked change, written in CriticMarkup: an insertion, a deletion, a substitution or
/// a highlight.
///
///     The term expires in {--12--}{++18++} months.
///     The term expires in {~~12~>18~~} months.
///     {==Check this clause==} before signing.
///
/// Where an ``InlineComment`` is *about* the document, a tracked change is a proposal to
/// change it — and the text inside one is real content, which is the whole difference. A
/// comment renders to nothing and contributes nothing to a heading's title; an insertion
/// contributes its words to the finished document, or does not, depending on whether the
/// change is taken. Deciding that is the caller's: this type records what was proposed.
///
/// Requires ``ParseOptions/parseTrackedChanges``. Without it the markers are ordinary text,
/// which is how a document explaining the syntax quotes them.
///
/// > Note: unlike a comment, the content is CHILDREN rather than a string, so
/// `{++some *emphasised* text++}` keeps its emphasis — an insertion that lost its markup
/// on the way in could not be accepted into the document it was written for.
///
/// > Note: a substitution's replaced text is a plain string, in ``replaced``. Its
/// replacement is the node's children. CriticMarkup's `~>` separator makes the old half a
/// run of text and nothing more, and treating it as markup would mean a second child list
/// for a half that is on its way out of the document.
public struct TrackedChange: RecurringInlineMarkup, InlineContainer {
    /// What is being proposed.
    public enum Kind: String, Sendable, CaseIterable {
        /// `{++text++}` — text to be added.
        case insertion
        /// `{--text--}` — text to be taken out.
        case deletion
        /// `{~~old~>new~~}` — text to be swapped. The old half is ``replaced``.
        case substitution
        /// `{==text==}` — text marked for attention. Nothing is proposed; accepting and
        /// rejecting leave the same document.
        case highlight
    }

    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .trackedChange = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: TrackedChange.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension TrackedChange {
    /// Create a tracked change of `kind` over zero or more child inline elements.
    init<Children: Sequence>(kind: Kind, replaced: String = "", _ children: Children)
    where Children.Element == RecurringInlineMarkup {
        try! self.init(.trackedChange(kind: kind.rawValue, replaced: replaced,
                                      parsedRange: nil, children.map { $0.raw.markup }))
    }

    /// Create a tracked change of `kind` over zero or more child inline elements.
    init(kind: Kind, replaced: String = "", _ children: RecurringInlineMarkup...) {
        self.init(kind: kind, replaced: replaced, children)
    }

    /// What is being proposed here.
    var kind: Kind {
        guard case let .trackedChange(rawKind, _) = _data.raw.markup.data,
              let kind = Kind(rawValue: rawKind) else {
            fatalError("\(self) markup wrapped unexpected \(_data.raw)")
        }
        return kind
    }

    /// For a ``Kind/substitution``, the text on its way out; empty for every other kind.
    ///
    /// The replacement is the node's children, so `{~~12~>18~~}` has `replaced == "12"` and
    /// a single `Text` child `"18"`.
    var replaced: String {
        guard case let .trackedChange(_, replaced) = _data.raw.markup.data else {
            fatalError("\(self) markup wrapped unexpected \(_data.raw)")
        }
        return replaced
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitTrackedChange(self)
    }
}
