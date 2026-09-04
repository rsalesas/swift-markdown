/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

/// Pandoc's bracketed span, `[text]{.class}`, as ``InlineAttributes``.
final class InlineSpanTests: XCTestCase {

    private func parse(_ source: String,
                       _ options: ParseOptions = .parseInlineSpans) -> Document {
        Document(parsing: source, options: options)
    }

    private func spans(_ source: String,
                       _ options: ParseOptions = .parseInlineSpans) -> [InlineAttributes] {
        var found: [InlineAttributes] = []
        func walk(_ markup: Markup) {
            if let span = markup as? InlineAttributes { found.append(span) }
            for child in markup.children { walk(child) }
        }
        walk(parse(source, options))
        return found
    }

    // MARK: - Off by default

    func testSpansAreProseWithoutTheOption() {
        let document = Document(parsing: "The [Contracting Party]{.defined-term} shall.")
        let paragraph = document.child(at: 0) as! Paragraph
        XCTAssertTrue(paragraph.children.allSatisfy { !($0 is InlineAttributes) })
        XCTAssertTrue(paragraph.plainText.contains("{.defined-term}"), paragraph.plainText)
    }

    // MARK: - The shape

    func testASingleSpan() {
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "The "
               ├─ InlineAttributes attributes: `.defined-term`
               │  └─ Text "Contracting Party"
               └─ Text " shall provide notice."
            """
        XCTAssertEqual(expected, parse("The [Contracting Party]{.defined-term} shall provide notice.")
            .debugDescription())
    }

    func testSeveralSpansInOneSentence() {
        XCTAssertEqual([".defined-term", ".emphasis-figure"],
                       spans("The [Contracting Party]{.defined-term} shall provide "
                             + "[30 days]{.emphasis-figure} notice.").map(\.attributes))
    }

    func testASpanCarriesAnIdAndSeveralClasses() {
        XCTAssertEqual(["#hero .lead .wide"],
                       spans("A [headline]{#hero .lead .wide} here.").map(\.attributes))
    }

    /// The whole point of the feature: a run of words inside a line, which no block-level
    /// wrapper can reach.
    func testASpanMayBeTheWholeParagraph() {
        XCTAssertEqual([".shout"], spans("[Everything]{.shout}").map(\.attributes))
    }

    // MARK: - A label that is not one run of text

    /// cmark parsed the emphasis long before anything looked for a span, so the construct
    /// arrives as three siblings. A defined term set in bold is the ordinary case here.
    func testALabelMayContainInlineMarkup() {
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "The "
               ├─ InlineAttributes attributes: `.defined-term`
               │  └─ Strong
               │     └─ Text "Contracting Party"
               └─ Text " shall."
            """
        XCTAssertEqual(expected, parse("The [**Contracting Party**]{.defined-term} shall.")
            .debugDescription())
    }

    func testALabelMayMixTextAndMarkup() {
        let expected = """
            Document
            └─ Paragraph
               └─ InlineAttributes attributes: `.term`
                  ├─ Text "the "
                  ├─ Emphasis
                  │  └─ Text "second"
                  └─ Text " tranche"
            """
        XCTAssertEqual(expected, parse("[the *second* tranche]{.term}").debugDescription())
    }

    /// Balanced brackets inside a label are the label's, so the span closes at the outer
    /// one rather than the first one it meets.
    func testALabelMayContainBalancedBrackets() {
        XCTAssertEqual([".ref"], spans("[see [1] below]{.ref}").map(\.attributes))
        XCTAssertEqual("see [1] below", spans("[see [1] below]{.ref}").first?.plainText)
    }

    func testASpanInsideASpanIsClaimedToo() {
        XCTAssertEqual([".note", ".defined-term"],
                       spans("[the [Party]{.defined-term} named]{.note}").map(\.attributes))
    }

    // MARK: - Prose keeps its brackets

    func testABlockThatIsNotAttributesIsProse() {
        for source in ["[see note]{4}",
                       "[a]{width}",                    // a bare word is not an attribute
                       "[a]{.x y}",
                       "[text] {.class}",               // the block must follow immediately
                       "[unclosed{.class}",
                       "[a]{.x",
                       "no brackets {.class} at all"] {
            XCTAssertTrue(spans(source).isEmpty, source)
        }
    }

    /// An ordinary link is a link, not a span with a strange block.
    func testLinksAreUntouched() {
        XCTAssertTrue(spans("A [link](https://example.com) here.").isEmpty)
        XCTAssertEqual(1, parse("A [link](https://example.com) here.")
            .child(at: 0)!.children.compactMap { $0 as? Link }.count)
    }

    func testAnEmptyLabelIsStillASpan() {
        // Nothing to say about it either way — but it must not crash or eat the line.
        XCTAssertEqual([".marker"], spans("Before []{.marker} after.").map(\.attributes))
        XCTAssertEqual("Before  after.",
                       (parse("Before []{.marker} after.").child(at: 0) as! Paragraph).plainText)
    }

    // MARK: - Code is content

    func testCodeSamplesAreNeverClaimed() {
        XCTAssertTrue(spans("`[text]{.class}`").isEmpty)
        XCTAssertTrue(spans("```\n[text]{.class}\n```").isEmpty)
        XCTAssertTrue(spans("    [text]{.class}").isEmpty)
        // A raw HTML *block* holds its content as a string, so nothing inside it is Text
        // and nothing in it can be claimed. Inline tags are different and deliberately so:
        // `<b>[text]{.class}</b>` is a span in ordinary prose that happens to sit between
        // two raw tags, and claiming it is right.
        XCTAssertTrue(spans("<div>\n[text]{.class}\n</div>").isEmpty)
        XCTAssertEqual([".class"], spans("<b>[text]{.class}</b>").map(\.attributes))
    }

    // MARK: - Composition

    /// The ordering test. Spans are claimed before attribute blocks: the other way round,
    /// a heading ending in a span sees a trailing brace block, takes `.defined-term` for
    /// itself, and leaves `[Contracting Party]` as literal text.
    func testAHeadingEndingInASpanKeepsItsSpan() {
        let heading = parse("# The [Contracting Party]{.defined-term}",
                            [.parseInlineSpans, .parseAttributes]).child(at: 0) as! Heading
        XCTAssertNil(heading.attributes)
        XCTAssertEqual([".defined-term"],
                       heading.children.compactMap { ($0 as? InlineAttributes)?.attributes })
    }

    /// …and a heading with both still gets both, which is what the sibling-aware guard in
    /// `AttributeBlockParser.trailing` is for.
    func testAHeadingCanCarryBothASpanAndItsOwnBlock() {
        let heading = parse("# The [Contracting Party]{.defined-term} {.unnumbered}",
                            [.parseInlineSpans, .parseAttributes]).child(at: 0) as! Heading
        XCTAssertEqual(".unnumbered", heading.attributes)
        XCTAssertEqual([".defined-term"],
                       heading.children.compactMap { ($0 as? InlineAttributes)?.attributes })
        XCTAssertFalse(heading.plainText.contains("{"), heading.plainText)
    }

    /// An image's own block is claimed by `AttributeBlockParser`, and the two grammars are
    /// the same one — so the span pass must not mistake `![alt](x.png){.right}` for a span
    /// on the strength of the `]` in the middle of it.
    func testAnImageBlockIsNotASpan() {
        let document = parse("![alt](chart.png){.right}", [.parseInlineSpans, .parseAttributes])
        XCTAssertTrue(spans("![alt](chart.png){.right}", [.parseInlineSpans, .parseAttributes]).isEmpty)
        XCTAssertEqual(".right",
                       (document.child(at: 0)?.child(at: 0) as? Image)?.attributes)
    }

    func testASpanMayHoldAComment() {
        let source = "[the Party {>> RS: check <<}]{.defined-term}"
        let document = parse(source, [.parseInlineSpans, .parseComments])
        let span = document.child(at: 0)?.child(at: 0) as? InlineAttributes
        XCTAssertEqual(".defined-term", span?.attributes)
        XCTAssertEqual(["RS: check"], span?.children.compactMap { ($0 as? InlineComment)?.body })
    }

    // MARK: - Walkers must not drop the node

    func testHTMLFormatterEmitsTheSpan() {
        let html = HTMLFormatter.format(parse("[a]{.x}"))
        XCTAssertTrue(html.contains("<span"), html)
        XCTAssertTrue(html.contains(">a<"), html)
    }

    /// Round-trips in the spelling it was written in. Formatting a Pandoc span as cmark's
    /// `^[a](.x)` would hand back a document the author did not write, and one that says
    /// something different to a reader parsing with only the other option on.
    func testMarkupFormatterRoundTripsInPandocSpelling() {
        let source = "The [Contracting Party]{.defined-term} shall."
        let formatted = parse(source).format()
        XCTAssertEqual(source, formatted.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(parse(source).debugDescription(),
                       parse(formatted).debugDescription())
    }

    /// The other dialect is cmark's own, and it keeps its own spelling.
    func testMarkupFormatterStillRoundTripsJSON5Attributes() {
        let source = "^[Hello](rainbow: 'extreme')"
        XCTAssertEqual(source, Document(parsing: source).format()
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testTreeDumperShowsTheAttributes() {
        XCTAssertTrue(parse("[a]{.x}").debugDescription().contains("attributes: `.x`"))
    }

    func testVisitorDispatchReachesTheNode() {
        struct Counter: MarkupWalker {
            var count = 0
            mutating func visitInlineAttributes(_ attributes: InlineAttributes) {
                count += 1
                descendInto(attributes)
            }
        }
        var counter = Counter()
        counter.visit(parse("[a]{.x} and [b]{.y}"))
        XCTAssertEqual(2, counter.count)
    }
}
