/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The content of a footnote, written as `[^id]: text`.
///
/// Footnote definitions hold block content, so a note can be several paragraphs,
/// a list, or a code block — anything indented under the definition line:
///
///     [^note]: The first paragraph.
///
///         A second paragraph, still part of the note.
///
/// Requires ``ParseOptions/parseFootnotes``. Without it, a definition line is
/// ordinary paragraph text.
///
/// > Note: cmark moves every definition to the end of the document and orders them
/// by first reference, dropping any that are never referenced. A definition's
/// position among the document's children is therefore its footnote number:
/// ```swift
/// let numbering = document.children
///     .compactMap { $0 as? FootnoteDefinition }
///     .enumerated()
///     .reduce(into: [String: Int]()) { $0[$1.element.footnoteID] = $1.offset + 1 }
/// ```
public struct FootnoteDefinition: BlockMarkup, BasicBlockContainer {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .footnoteDefinition = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: FootnoteDefinition.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension FootnoteDefinition {
    /// Create a footnote definition with an identifier and block content.
    init(footnoteID: String, _ children: some Sequence<BlockMarkup>) {
        self.init(footnoteID: footnoteID, children, inheritSourceRange: false)
    }

    init(footnoteID: String, _ children: some Sequence<BlockMarkup>, inheritSourceRange: Bool) {
        let rawChildren = children.map { $0.raw.markup }
        let parsedRange = inheritSourceRange ? rawChildren.parsedRange : nil
        try! self.init(.footnoteDefinition(footnoteID: footnoteID, parsedRange: parsedRange, rawChildren))
    }

    /// The footnote's identifier: `note` for `[^note]: text`.
    ///
    /// This is the author's label, not the number it renders as — see the note on
    /// ``FootnoteDefinition`` for how numbering falls out of document order.
    var footnoteID: String {
        get {
            guard case let .footnoteDefinition(footnoteID) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return footnoteID
        }
        set {
            guard footnoteID != newValue else { return }
            _data = _data.replacingSelf(.footnoteDefinition(footnoteID: newValue, parsedRange: nil, _data.raw.markup.copyChildren()))
        }
    }

    // MARK: BasicBlockContainer

    init(_ children: some Sequence<BlockMarkup>) {
        self.init(footnoteID: "", children)
    }

    init(_ children: some Sequence<BlockMarkup>, inheritSourceRange: Bool) {
        self.init(footnoteID: "", children, inheritSourceRange: inheritSourceRange)
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitFootnoteDefinition(self)
    }
}
