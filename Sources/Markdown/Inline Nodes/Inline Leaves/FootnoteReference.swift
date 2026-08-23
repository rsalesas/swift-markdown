/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A reference to a footnote, written as `[^id]`.
///
/// Requires ``ParseOptions/parseFootnotes``. Without it, `[^id]` is ordinary text.
///
/// > Note: a reference with no matching ``FootnoteDefinition`` never becomes one of
/// these. cmark turns it back into the literal text the author wrote, so `[^missing]`
/// survives as ``Text`` — which is what lets a document quote the syntax without
/// having to escape it.
public struct FootnoteReference: InlineMarkup {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .footnoteReference = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: FootnoteReference.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension FootnoteReference {
    /// Create a reference to the footnote with the given identifier.
    init(footnoteID: String) {
        try! self.init(.footnoteReference(footnoteID: footnoteID, parsedRange: nil))
    }

    /// The identifier of the footnote being referenced: `note` for `[^note]`.
    var footnoteID: String {
        get {
            guard case let .footnoteReference(footnoteID) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return footnoteID
        }
        set {
            guard footnoteID != newValue else { return }
            _data = _data.replacingSelf(.footnoteReference(footnoteID: newValue, parsedRange: nil))
        }
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitFootnoteReference(self)
    }

    // MARK: PlainTextConvertibleMarkup

    var plainText: String {
        return "[^\(footnoteID)]"
    }
}
