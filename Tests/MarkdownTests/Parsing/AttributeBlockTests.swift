/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

final class AttributeBlockTests: XCTestCase {
    private func parse(_ source: String) -> Document {
        Document(parsing: source, options: .parseAttributes)
    }

    private func heading(_ source: String) -> Heading {
        parse(source).child(at: 0) as! Heading
    }

    // MARK: - Off by default

    func testOffByDefault() {
        let document = Document(parsing: "# Preface {.unnumbered}")
        let heading = document.child(at: 0) as! Heading
        XCTAssertNil(heading.attributes)
        XCTAssertEqual("Preface {.unnumbered}", heading.plainText)
    }

    // MARK: - Headings

    func testHeadingClaimsItsBlock() {
        let heading = self.heading("# Preface {.unnumbered}")
        XCTAssertEqual(".unnumbered", heading.attributes)
        XCTAssertEqual("Preface", heading.plainText, "the block comes off the text")
    }

    func testHeadingWithIdentifierAndClasses() {
        XCTAssertEqual("#sec-intro .wide", heading("# Introduction {#sec-intro .wide}").attributes)
    }

    /// Formatting is kept: the block is a suffix of the last run of text, not of the
    /// heading as a whole.
    func testHeadingKeepsItsFormatting() {
        let heading = self.heading("# The **bold** truth {.wide}")
        XCTAssertEqual(".wide", heading.attributes)
        XCTAssertEqual("The bold truth", heading.plainText)
        XCTAssertEqual(1, heading.children.compactMap { $0 as? Strong }.count)
    }

    /// The block is removed exactly once, so the element cannot be found carrying it in
    /// one form and not the other.
    func testTheBlockIsRemovedFromTheTextExactlyOnce() {
        let heading = self.heading("# Preface {.unnumbered}")
        XCTAssertFalse(heading.plainText.contains("{"), heading.plainText)
        XCTAssertFalse(HTMLFormatter.format(heading).contains("{"), HTMLFormatter.format(heading))
    }

    // MARK: - Images

    func testImageClaimsItsBlock() {
        let document = parse("![Chart](chart.png){width=40% .right}")
        let image = document.child(at: 0)?.child(at: 0) as! Image
        XCTAssertEqual("width=40% .right", image.attributes)
        XCTAssertEqual("chart.png", image.source)
    }

    func testTextAfterAnImageBlockSurvives() {
        let document = parse("![Chart](chart.png){.right} and then some words.")
        let paragraph = document.child(at: 0) as! Paragraph
        XCTAssertEqual("Chart and then some words.", paragraph.plainText)
    }

    func testImageWithoutABlockIsUntouched() {
        let document = parse("![Chart](chart.png)")
        let image = document.child(at: 0)?.child(at: 0) as! Image
        XCTAssertNil(image.attributes)
    }

    // MARK: - Prose keeps its braces

    /// The refusals matter more than the claims: prose that loses a brace has lost a
    /// word, and nobody reads a diff of their own document that closely.
    func testBareWordsAreProse() {
        XCTAssertNil(heading("# Chapter {see note 4}").attributes)
        XCTAssertEqual("Chapter {see note 4}", heading("# Chapter {see note 4}").plainText)
    }

    func testABlockMustStandOnItsOwn() {
        XCTAssertNil(heading("# Set{.x}").attributes, "no space: the braces are part of the word")
        XCTAssertEqual("Set{.x}", heading("# Set{.x}").plainText)
    }

    func testAHeadingMustKeepSomeWords() {
        XCTAssertNil(heading("# {.unnumbered}").attributes)
        XCTAssertEqual("{.unnumbered}", heading("# {.unnumbered}").plainText)
    }

    func testEmptyAndNestedBracesAreRefused() {
        XCTAssertNil(heading("# Chapter {}").attributes)
        XCTAssertNil(heading("# Chapter {a {b} c}").attributes)
    }

    func testABlockMustBeAtTheEnd() {
        XCTAssertNil(heading("# The {x} problem").attributes)
        XCTAssertEqual("The {x} problem", heading("# The {x} problem").plainText)
    }

    func testPunctuationInANameIsRefused() {
        XCTAssertNil(heading("# Chapter {.not/a/class}").attributes)
    }

    // MARK: - Code samples are never claimed

    /// The reason this reads the tree rather than the source: a document explaining the
    /// syntax is exactly the document that must not have it applied.
    func testABlockInAFencedCodeSampleIsLeftAlone() {
        let document = parse("```md\n# Preface {.unnumbered}\n```")
        let code = document.child(at: 0) as! CodeBlock
        XCTAssertEqual("# Preface {.unnumbered}\n", code.code)
    }

    func testABlockInAnIndentedCodeSampleIsLeftAlone() {
        let document = parse("Example:\n\n    ![a](b.png){width=40%}\n")
        let code = document.child(at: 1) as! CodeBlock
        XCTAssertTrue(code.code.contains("{width=40%}"), code.code)
    }

    func testABlockInInlineCodeIsLeftAlone() {
        let heading = self.heading("# Preface `{.unnumbered}`")
        XCTAssertNil(heading.attributes)
        XCTAssertEqual(1, heading.children.compactMap { $0 as? InlineCode }.count)
    }

    // MARK: - An image inside a heading owns its own block

    /// `# Figure ![](chart.png){.right}` — the block belongs to the image. Taking it for
    /// the heading would put `.right` on the h1, and `{.unnumbered}` there would silently
    /// unnumber the section.
    func testAnImageEndingAHeadingKeepsItsOwnBlock() {
        let document = parse("# Figure ![](chart.png){.right}")
        let heading = document.child(at: 0) as! Heading
        XCTAssertNil(heading.attributes, "the heading must not take it")
        let image = heading.children.compactMap { $0 as? Image }.first
        XCTAssertEqual(".right", image?.attributes)
        XCTAssertEqual("Figure", heading.plainText.trimmingCharacters(in: .whitespaces),
                       "and the block is off the heading's text either way")
    }

    func testAHeadingEndingInWordsStillClaimsItsOwnBlock() {
        let document = parse("# Figure ![](c.png) and more {.wide}")
        let heading = document.child(at: 0) as! Heading
        XCTAssertEqual(".wide", heading.attributes)
        XCTAssertNil(heading.children.compactMap { $0 as? Image }.first?.attributes)
    }

    // MARK: - Composition

    func testHeadingsInsideFencedDivsAreClaimedToo() {
        let document = Document(parsing: "::: note\n## Inside {.wide}\n:::",
                                options: [.parseFencedDivs, .parseAttributes])
        let div = document.child(at: 0) as! FencedDiv
        let heading = div.child(at: 0) as! Heading
        XCTAssertEqual(".wide", heading.attributes)
        XCTAssertEqual("Inside", heading.plainText)
    }

    func testAttributesSurviveAValueRoundTrip() {
        var heading = self.heading("# Preface {.unnumbered}")
        XCTAssertEqual(".unnumbered", heading.attributes)
        heading.attributes = ".frontmatter"
        XCTAssertEqual(".frontmatter", heading.attributes)
        XCTAssertEqual("Preface", heading.plainText, "changing them does not disturb the text")
    }
}
