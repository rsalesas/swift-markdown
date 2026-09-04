/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Claims Pandoc's attribute blocks — `{.class #id key=value}` — for the element they
/// belong to.
///
///     # Preface {.unnumbered}
///     ![Chart](chart.png){width=40% .right}
///
/// Markdown has no way to say "this heading is not a section" or "this picture is half a
/// column wide", which is the first thing a document author reaches for and cannot
/// express. Pandoc settled it with a brace block, and Djot generalised it.
///
/// ## Why this runs on the tree
///
/// A block only means something where an element ends. Recognising it by scanning the
/// source text would claim one inside a code sample, and a document explaining the
/// syntax is exactly the document that must not have it applied. Reading the parsed tree
/// means a code block is a `CodeBlock` and cannot offer an attribute block at all.
///
/// It also means the block is removed **once**, in one place, from the text and into the
/// element. An element cannot then be found carrying the block in one form and not the
/// other, which is the failure this exists to prevent: a heading printed as `Preface`
/// while its own title still read `Preface {.unnumbered}`.
///
/// ## Parsing is strict
///
/// The block is claimed only when every token inside it is clearly an attribute. A bare
/// word means it is prose — `# Chapter {see note 4}` is a heading about a note, not a
/// heading with attributes — and prose that loses a brace has lost a word.
enum AttributeBlockParser {

    /// Take the attribute blocks in `document` off the text and onto the elements.
    static func claim(in document: Document) -> Document {
        var rewriter = Rewriter()
        return rewriter.visit(document) as? Document ?? document
    }

    /// The tokens inside `{…}`, or nil if this is not an attribute block.
    ///
    /// Nil for a bare word anywhere, for an empty block, and for a block whose `#id` or
    /// `.class` is not a plain name. Values are otherwise kept verbatim: an author
    /// writing `{lang=fr}` gets it back rather than having it dropped for not being
    /// understood here.
    static func isAttributeBlock(_ body: String) -> Bool {
        let tokens = tokenise(body)
        guard !tokens.isEmpty else { return false }
        for token in tokens {
            if token.hasPrefix("#") || token.hasPrefix(".") {
                guard isName(String(token.dropFirst())) else { return false }
            } else if let equals = token.firstIndex(of: "="), equals != token.startIndex {
                continue
            } else {
                return false        // a bare word: this is prose
            }
        }
        return true
    }

    /// The block at the very end of `text`, and what it occupies including the space
    /// before it, or nil.
    static func trailing(_ text: String, afterSiblings: Bool = false) -> (attributes: String, raw: String)? {
        guard let close = text.lastIndex(where: { !$0.isWhitespace }), text[close] == "}",
              let open = text[text.startIndex..<close].lastIndex(of: "{") else { return nil }
        let body = String(text[text.index(after: open)..<close])
        guard !body.contains("{"), !body.contains("}"), isAttributeBlock(body) else { return nil }
        // A block stands on its own: `Set{.x}` is a word with braces stuck to it. This
        // also refuses an element that would be left with nothing but its attributes —
        // unless something already came before this run of text. `# **Chapter** {.wide}`
        // ends in `Text " {.wide}"`, whose own content is a single space, and the heading
        // is plainly not "nothing but its attributes": the words are in the sibling before
        // it. Reading that one node in isolation refused a block the author clearly wrote.
        let before = text[text.startIndex..<open]
        guard let previous = before.last, previous.isWhitespace,
              afterSiblings || !before.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }

        var cut = open
        while cut > text.startIndex, text[text.index(before: cut)].isWhitespace {
            cut = text.index(before: cut)
        }
        return (body, String(text[cut...]))
    }

    /// The block at the very start of `text`, and how much of it the block occupies.
    ///
    /// An image's block follows the image, which puts it at the head of the next run of
    /// text rather than at the end of the image itself.
    static func leading(_ text: String) -> (attributes: String, length: Int)? {
        guard text.hasPrefix("{"), let close = text.firstIndex(of: "}") else { return nil }
        let body = String(text[text.index(after: text.startIndex)..<close])
        guard !body.contains("{"), isAttributeBlock(body) else { return nil }
        return (body, text.distance(from: text.startIndex, to: close) + 1)
    }

    private static func tokenise(_ body: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for character in body {
            if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character.isWhitespace && !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A name safe to use as a class or id. Anything else means this was never an
    /// attribute block, so it is refused rather than escaped.
    private static func isName(_ raw: String) -> Bool {
        !raw.isEmpty && raw.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    // MARK: - The rewriter

    private struct Rewriter: MarkupRewriter {
        mutating func visitHeading(_ heading: Heading) -> Markup? {
            // The image pass runs first. A heading that ends in an image carrying a
            // block — `# Figure ![](chart.png){.right}` — is the image's, not the
            // heading's: taking it for the heading would put `.right` on the h1, and a
            // `{.unnumbered}` there would silently unnumber the section.
            var changed = false
            let children = claimImages(in: visitChildren(of: heading, changed: &changed),
                                       changed: &changed)
            guard let last = children.last as? Text,
                  let found = AttributeBlockParser.trailing(last.string,
                                                            afterSiblings: children.count > 1) else {
                guard changed else { return heading }
                return heading.withUncheckedChildren(children)
            }
            var updated = children
            updated[updated.count - 1] = Text(String(last.string.dropLast(found.raw.count)))
            var result = Heading(level: heading.level, updated.compactMap { $0 as? InlineMarkup })
            result.attributes = found.attributes
            return result
        }

        /// Untouched nodes are handed back untouched.
        ///
        /// `withUncheckedChildren` rebuilds the node AND every ancestor above it, and
        /// rebuilding an ancestor copies that ancestor's entire child list — so rebuilding
        /// every node in a document costs the document squared, whether or not there was a
        /// single attribute block in it to find. See `CriticMarkupParser.Rewriter`, which
        /// had the same shape and the same cost.
        mutating func defaultVisit(_ markup: Markup) -> Markup? {
            var changed = false
            let children = claimImages(in: visitChildren(of: markup, changed: &changed),
                                       changed: &changed)
            guard changed else { return markup }
            return markup.withUncheckedChildren(children)
        }

        /// Every child visited, and whether any of them came back a different node.
        /// Identity, not equality: a child returned as the very same raw node is one
        /// neither pass had any interest in.
        private mutating func visitChildren(of markup: Markup, changed: inout Bool) -> [Markup] {
            var out: [Markup] = []
            out.reserveCapacity(markup.childCount)
            for child in markup.children {
                guard let visited = visit(child) else { changed = true; continue }
                if visited.raw.markup !== child.raw.markup { changed = true }
                out.append(visited)
            }
            return out
        }

        /// An image's block arrives as the head of the `Text` node after it, because
        /// cmark has no idea the braces belong to the image. Being siblings is the only
        /// place the pairing is visible, so it has to happen wherever children are
        /// rebuilt — not only in `defaultVisit`, or a heading's own children never see it.
        private func claimImages(in children: [Markup], changed: inout Bool) -> [Markup] {
            var rebuilt: [Markup] = []
            var index = 0
            while index < children.count {
                if let image = children[index] as? Image, index + 1 < children.count,
                   let text = children[index + 1] as? Text,
                   let found = AttributeBlockParser.leading(text.string) {
                    var updated = image
                    updated.attributes = found.attributes
                    rebuilt.append(updated)
                    rebuilt.append(Text(String(text.string.dropFirst(found.length))))
                    changed = true
                    index += 2
                    continue
                }
                rebuilt.append(children[index])
                index += 1
            }
            return rebuilt
        }
    }
}
