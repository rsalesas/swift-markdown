/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

/// Mathematics claimed as ``InlineMath`` and ``DisplayMath``.
///
/// The property that decides this whole design is in `texSurvivesEverythingMarkdownDoesToIt`:
/// TeX is written in the characters Markdown reserves, so the parsed tree cannot carry a
/// formula and the source has to be read instead. Every other test here is downstream of
/// that one.
final class MathTests: XCTestCase {

    private func parse(_ source: String) -> Document {
        Document(parsing: source, options: .parseMath)
    }

    private func inline(_ source: String) -> [InlineMath] {
        var walker = Maths(); walker.visit(parse(source)); return walker.inline
    }

    private func display(_ source: String) -> [DisplayMath] {
        var walker = Maths(); walker.visit(parse(source)); return walker.display
    }

    // MARK: - The reason this reads the file

    /// Every one of these is destroyed by the time a rewriter sees the paragraph: cmark
    /// resolves `\,` to a comma and `\\` to one backslash, and pairs `*y*` into an emphasis
    /// node. A formula built from the parsed text would be a formula the author did not
    /// write, which is why the fences are found in the tree and the content in the source.
    func testTexSurvivesEverythingMarkdownDoesToIt() {
        XCTAssertEqual(["\\int_a^b f(x)\\,dx"], display("$$\\int_a^b f(x)\\,dx$$").map(\.tex))
        XCTAssertEqual(["\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}"],
                       display("$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$").map(\.tex))
        XCTAssertEqual(["x = *y*"], inline("A $$x = *y*$$ here.").map(\.tex))
        XCTAssertEqual(["a_1 + b_2"], inline("A $$a_1 + b_2$$ here.").map(\.tex))
        XCTAssertEqual(["\\text{don't -- really}"],
                       inline("A $$\\text{don't -- really}$$ here.").map(\.tex))
    }

    /// No source, no claim. There is no half-answer available.
    func testAClaimWithoutASourceTakesNothing() {
        let document = Document(parsing: "A $$x^2$$ here.", options: .parseMath)
        var before = Maths(); before.visit(document)
        XCTAssertEqual(1, before.inline.count)

        var after = Maths(); after.visit(MathParser.claim(in: Document(), source: nil))
        XCTAssertEqual(0, after.inline.count)
    }

    // MARK: - Inline or display

    func testAFormulaInASentenceIsInline() {
        let found = inline("The area is $$\\pi r^2$$, which is inline.")
        XCTAssertEqual(["\\pi r^2"], found.map(\.tex))
        XCTAssertEqual([], display("The area is $$\\pi r^2$$, which is inline.").map(\.tex))
    }

    func testAFormulaAloneInAParagraphIsDisplay() {
        XCTAssertEqual(["\\pi r^2"], display("$$\\pi r^2$$").map(\.tex))
        XCTAssertEqual([], inline("$$\\pi r^2$$").map(\.tex))
    }

    /// Written across lines, which is how display mathematics is usually typed. The fences
    /// are on their own lines and the formula keeps the newlines the author left in it.
    func testDisplayMathAcrossLines() {
        let found = display("$$\n\\int_{a}^{b} f(x)\\,dx\n$$")
        XCTAssertEqual(["\\int_{a}^{b} f(x)\\,dx"], found.map(\.tex))
    }

    func testAFormulaKeepsInnerNewlines() {
        let found = display("$$\n\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}\n$$")
        XCTAssertEqual(["\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}"], found.map(\.tex))
    }

    /// A heading is not a paragraph, so a formula that is all of one stays inline — there is
    /// no such thing as a heading that is display mathematics.
    func testAFormulaInAHeadingIsInline() {
        XCTAssertEqual(["\\pi r^2"], inline("# The $$\\pi r^2$$ case").map(\.tex))
        XCTAssertEqual(["E = mc^2"], inline("## $$E = mc^2$$").map(\.tex))
        XCTAssertEqual([], display("## $$E = mc^2$$").map(\.tex))
    }

    func testAFormulaInATableCellIsInline() {
        XCTAssertEqual(["x^2"], inline("| a | b |\n| --- | --- |\n| $$x^2$$ | y |").map(\.tex))
    }

    // MARK: - What must be left alone

    /// The reason this runs on the tree. A document explaining the syntax is exactly the
    /// document that must not have it applied.
    func testCodeIsUntouched() {
        XCTAssertEqual([], inline("Code: `$$x$$` stays prose.").map(\.tex))
        XCTAssertEqual([], display("```\n$$x$$\n```").map(\.tex))
        XCTAssertEqual([], display("    $$x$$").map(\.tex))
        // A raw HTML BLOCK is one string, so nothing inside it is claimed.
        XCTAssertEqual([], inline("<div>\n$$x$$\n</div>").map(\.tex))
    }

    /// Between two inline HTML tags, though, is ordinary Markdown — `<span>*x*</span>` is
    /// emphasis, and a formula there is a formula for the same reason. Only the TAGS are
    /// held as strings; what sits between them is text like any other.
    func testTextBetweenInlineHTMLTagsIsOrdinaryMarkdown() {
        XCTAssertEqual(["x^2"], inline("<span>$$x^2$$</span>").map(\.tex))
    }

    /// The whole reason `$ … $` is not a second, inline fence. These are the documents this
    /// parser is for.
    func testASingleDollarIsNeverAFence() {
        let source = "A price of $50 and $1,200, or $50/hour at $75 an hour."
        XCTAssertEqual([], inline(source).map(\.tex))
        XCTAssertEqual([], display(source).map(\.tex))
    }

    func testAnEmptyFormulaIsProse() {
        XCTAssertEqual([], inline("Empty $$$$ is prose.").map(\.tex))
        XCTAssertEqual([], inline("Spaces $$   $$ too.").map(\.tex))
    }

    /// An unclosed fence cannot leave its own block, so the worst it can do is nothing.
    func testAnUnclosedFenceClaimsNothing() {
        let source = "Unclosed $$x and then more.\n\nA second paragraph $$y$$ here."
        XCTAssertEqual(["y"], inline(source).map(\.tex))
    }

    // MARK: - Where a formula is

    /// Two formulas saying exactly the same thing. Their text cannot tell them apart and
    /// their ranges do — the same property comments and tracked changes needed.
    func testEachFormulaReportsItsOwnCharacters() {
        let source = "Take $$x^2$$ but not $$x^2$$ either."
        let found = inline(source)
        XCTAssertEqual(2, found.count)
        XCTAssertNotEqual(found[0].range, found[1].range)
        let index = SourceByteIndex(source)
        XCTAssertEqual(["$$x^2$$", "$$x^2$$"],
                       found.compactMap { $0.range }.compactMap {
                           index.text(in: $0).map(String.init)
                       })
        let starts = found.compactMap { $0.range }.compactMap { index.index(of: $0.lowerBound) }
            .map { source.distance(from: source.startIndex, to: $0) }
        XCTAssertEqual([5, 21], starts)
    }

    /// Smart punctuation shortens the parsed string and not the file; columns are UTF-8
    /// bytes. Both corrections apply here exactly as they do everywhere else.
    func testAFormulaAfterShiftingTextPointsAtItself() {
        for source in ["Don't -- really $$x^2$$ after.",
                       "Ünïcödé ahead $$x^2$$ and after.",
                       "Emoji 🎯 ahead $$x^2$$ and after."] {
            let index = SourceByteIndex(source)
            XCTAssertEqual(["$$x^2$$"],
                           inline(source).compactMap { $0.range }.compactMap {
                               index.text(in: $0).map(String.init)
                           }, source)
        }
    }

    func testAHandBuiltFormulaHasNoRange() {
        XCTAssertNil(InlineMath("x^2").range)
        XCTAssertNil(DisplayMath("x^2").range)
    }

    // MARK: - What a formula contributes

    /// The TeX, so a heading whose title is a formula still has a slug, a contents entry and
    /// an outline — and two headings differing only by their mathematics do not collide.
    func testPlainTextIsTheSource() {
        let heading = parse("# The $$\\pi r^2$$ case").child(at: 0) as? Heading
        XCTAssertEqual("The \\pi r^2 case", heading?.plainText)
    }

    // MARK: - Out and back

    func testFormattingRoundTrips() {
        for source in ["The area is $$\\pi r^2$$ here.",
                       "$$\\int_a^b f(x)\\,dx$$",
                       "A $$x = *y*$$ and $$a\\\\b$$ here."] {
            let once = parse(source).format()
            let twice = parse(once).format()
            XCTAssertEqual(once, twice, source)
            var walker = Maths(); walker.visit(parse(once))
            var original = Maths(); original.visit(parse(source))
            XCTAssertEqual(original.inline.map(\.tex), walker.inline.map(\.tex), source)
            XCTAssertEqual(original.display.map(\.tex), walker.display.map(\.tex), source)
        }
    }

    func testHTMLCarriesTheTexForATypesetter() {
        XCTAssertEqual("<p>A <span class=\"math math-inline\">x^2</span> here.</p>",
                       HTMLFormatter.format("A $$x^2$$ here.", parseOptions: .parseMath)
                           .trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual("<div class=\"math math-display\">x&lt;y</div>",
                       HTMLFormatter.format("$$x<y$$", parseOptions: .parseMath)
                           .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Off by default

    func testWithoutTheOptionItIsProse() {
        var walker = Maths()
        walker.visit(Document(parsing: "A $$x^2$$ here."))
        XCTAssertEqual(0, walker.inline.count)
        XCTAssertEqual(0, walker.display.count)
    }

    struct Maths: MarkupWalker {
        var inline: [InlineMath] = []
        var display: [DisplayMath] = []
        mutating func visitInlineMath(_ m: InlineMath) { inline.append(m) }
        mutating func visitDisplayMath(_ m: DisplayMath) { display.append(m) }
    }
}
