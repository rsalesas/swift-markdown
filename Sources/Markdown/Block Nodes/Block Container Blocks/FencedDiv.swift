/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A fenced div: a named block container written with colon fences.
///
///     ::: warning
///     Anything in here is ordinary Markdown.
///     :::
///
/// The opening fence may carry a bare name, or Pandoc's attribute block:
///
///     ::: {.callout .wide #intro}
///
/// Divs nest, and the innermost open one is what a bare `:::` closes:
///
///     ::: outer
///     ::: inner
///     :::
///     :::
///
/// Requires ``ParseOptions/parseFencedDivs``. Without it, a `:::` line is ordinary
/// paragraph text.
///
/// The syntax comes from Pandoc, where it is the general way to attach a name to a
/// region of a document so a stylesheet or a filter can act on it — a callout, a
/// signature block, a column. Markdown has no other way to say "this run of blocks
/// belongs together".
///
/// > Note: ``attributeText`` is stored verbatim, exactly as ``CodeBlock/language``
/// stores an entire info string. ``classes``, ``identifier`` and ``keyValuePairs``
/// read it. Keeping the source means nothing an author wrote is silently dropped
/// because this type did not understand it.
public struct FencedDiv: BlockMarkup, BasicBlockContainer {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .fencedDiv = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: FencedDiv.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension FencedDiv {
    /// Create a fenced div with an attribute block and block content.
    init(attributeText: String, _ children: some Sequence<BlockMarkup>) {
        self.init(attributeText: attributeText, children, inheritSourceRange: false)
    }

    init(attributeText: String, _ children: some Sequence<BlockMarkup>, inheritSourceRange: Bool) {
        let rawChildren = children.map { $0.raw.markup }
        let parsedRange = inheritSourceRange ? rawChildren.parsedRange : nil
        try! self.init(.fencedDiv(attributeText: attributeText, parsedRange: parsedRange, rawChildren))
    }

    /// Everything after the opening fence's colons, verbatim: `warning`, or
    /// `{.callout .wide #intro}`.
    var attributeText: String {
        get {
            guard case let .fencedDiv(attributeText) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return attributeText
        }
        set {
            guard attributeText != newValue else { return }
            _data = _data.replacingSelf(.fencedDiv(attributeText: newValue, parsedRange: nil, _data.raw.markup.copyChildren()))
        }
    }

    /// The bare name form: `warning` for `::: warning`, and `nil` for the brace form.
    ///
    /// Only the first word. Pandoc leaves `::: name and more words` undefined, and a
    /// name is a single class.
    var name: String? {
        let text = attributeText.trimmingCharacters(in: .whitespaces)
        guard !text.hasPrefix("{") else { return nil }
        guard let first = text.split(separator: " ").first else { return nil }
        return String(first)
    }

    /// The classes this div carries.
    ///
    /// A bare name is a class: Pandoc reads `::: warning` as `::: {.warning}`, so both
    /// spellings reach a stylesheet the same way.
    var classes: [String] {
        if let name { return [name] }
        return attributes.compactMap { token in
            token.hasPrefix(".") ? String(token.dropFirst()) : nil
        }
    }

    /// The `#id` from the attribute block, if it has one.
    var identifier: String? {
        attributes.compactMap { token in
            token.hasPrefix("#") ? String(token.dropFirst()) : nil
        }.last
    }

    /// `key=value` pairs from the attribute block, in the order written.
    ///
    /// Nothing here is interpreted — an author writing `::: {.note lang=fr}` gets the
    /// pair back rather than having it silently dropped.
    var keyValuePairs: [(name: String, value: String)] {
        attributes.compactMap { token in
            guard !token.hasPrefix("."), !token.hasPrefix("#"),
                  let equals = token.firstIndex(of: "=") else { return nil }
            var value = String(token[token.index(after: equals)...])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return (String(token[token.startIndex..<equals]), value)
        }
    }

    /// The tokens inside `{…}`, or nothing for the bare-name form.
    private var attributes: [Substring] {
        let text = attributeText.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("{"), text.hasSuffix("}") else { return [] }
        return text.dropFirst().dropLast().split(separator: " ")
    }

    // MARK: BasicBlockContainer

    init(_ children: some Sequence<BlockMarkup>) {
        self.init(attributeText: "", children)
    }

    init(_ children: some Sequence<BlockMarkup>, inheritSourceRange: Bool) {
        self.init(attributeText: "", children, inheritSourceRange: inheritSourceRange)
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitFencedDiv(self)
    }
}
