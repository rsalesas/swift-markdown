/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

final class BlankLinesTests: XCTestCase {
    private func parse(_ source: String) -> Document {
        Document(parsing: source, options: .preserveBlankLines)
    }

    private func counts(_ source: String) -> [Int] {
        parse(source).children.compactMap { ($0 as? BlankLines)?.count }
    }

    // MARK: - Off by default

    func testOffByDefault() {
        let document = Document(parsing: "A.\n\n\n\nB.")
        XCTAssertTrue(document.children.compactMap { $0 as? BlankLines }.isEmpty)
        XCTAssertEqual(2, document.childCount)
    }

    // MARK: - The count

    /// The first blank line is the paragraph break itself. Only what the author added
    /// beyond it is space.
    func testOneBlankLineIsAnOrdinaryBreak() {
        XCTAssertEqual([], counts("A.\n\nB."))
    }

    func testEachExtraBlankLineCounts() {
        XCTAssertEqual([1], counts("A.\n\n\nB."))
        XCTAssertEqual([2], counts("A.\n\n\n\nB."))
        XCTAssertEqual([4], counts("A.\n\n\n\n\n\nB."))
    }

    func testSeveralRuns() {
        XCTAssertEqual([1, 2], counts("A.\n\n\nB.\n\n\n\nC."))
    }

    func testTheShape() {
        let expected = """
            Document
            ├─ Paragraph
            │  └─ Text "A."
            ├─ BlankLines count: 1
            └─ Paragraph
               └─ Text "B."
            """
        XCTAssertEqual(expected, parse("A.\n\n\nB.").debugDescription())
    }

    // MARK: - Code is content

    /// The gaps come from the parsed tree, so a blank line inside a block is never
    /// between two of them. That holds for every kind of code block, which a line
    /// scanner has to handle case by case and gets wrong.
    func testBlankLinesInsideFencedCodeAreContent() {
        XCTAssertEqual([], counts("```\na\n\n\nb\n```"))
        let code = parse("```\na\n\n\nb\n```").child(at: 0) as! CodeBlock
        XCTAssertEqual("a\n\n\nb\n", code.code)
    }

    func testBlankLinesInsideTildeFencedCodeAreContent() {
        XCTAssertEqual([], counts("~~~\na\n\n\nb\n~~~"))
    }

    func testBlankLinesInsideALongFenceAreContent() {
        XCTAssertEqual([], counts("````\n```\na\n\n\nb\n```\n````"))
    }

    func testBlankLinesInsideIndentedCodeAreContent() {
        let source = "Before.\n\n    a\n\n\n    b\n\nAfter."
        XCTAssertEqual([], counts(source))
        let code = parse(source).child(at: 1) as! CodeBlock
        XCTAssertTrue(code.code.contains("a\n\n\nb"), code.code)
    }

    // MARK: - Edges

    func testLeadingAndTrailingRunsRecordNothing() {
        XCTAssertEqual([], counts("\n\n\nA."), "nothing to space away from")
        XCTAssertEqual([], counts("A.\n\n\n\n"), "no following block")
    }

    func testInsideABlockQuote() {
        let quote = parse("> A.\n>\n>\n> B.").child(at: 0) as! BlockQuote
        XCTAssertEqual([1], quote.children.compactMap { ($0 as? BlankLines)?.count })
    }

    func testInsideAFencedDiv() {
        let document = Document(parsing: "::: party\nName:\n\n\nSignature:\n:::",
                                options: [.parseFencedDivs, .preserveBlankLines])
        let div = document.child(at: 0) as! FencedDiv
        XCTAssertEqual([1], div.children.compactMap { ($0 as? BlankLines)?.count })
    }

    // MARK: - Walkers must not drop it

    func testHTMLFormatterEmitsNothingForIt() {
        XCTAssertFalse(HTMLFormatter.format(parse("A.\n\n\nB.")).contains("BlankLines"))
    }

    /// Formatting a document must not quietly close up the gaps the author left.
    func testMarkupFormatterRoundTrips() {
        let document = parse("A.\n\n\n\nB.")
        let reparsed = Document(parsing: document.format(), options: .preserveBlankLines)
        XCTAssertEqual([2], reparsed.children.compactMap { ($0 as? BlankLines)?.count },
                       document.format().debugDescription)
    }

    func testVisitorDispatchReachesTheNode() {
        var counter = BlankLinesCounter()
        counter.visit(parse("A.\n\n\nB.\n\n\n\nC."))
        XCTAssertEqual(2, counter.runs)
    }
}

private struct BlankLinesCounter: MarkupWalker {
    var runs = 0
    mutating func visitBlankLines(_ blankLines: BlankLines) {
        runs += 1
    }
}
