/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

/// A claimed comment knows where in the file it came from.
///
/// This is the property an editor needs and the words cannot give it: two comments may say
/// exactly the same thing, so only a position tells them apart. Everything here checks it
/// the same way — take the range the comment reports, cut those characters out of the
/// source, and see whether they are the comment.
///
/// The two cases that decide the design are the smart-punctuation one and the Unicode one.
/// Parsing turns `Don't -- really` into `Don’t – really`, which is shorter, so nothing can
/// be located by counting through the parsed string; and cmark counts columns in UTF-8
/// bytes, so anything above ASCII moves them. A node's RANGE is honest through both, which
/// is why the comment inside a run of text is found by reading the source that run came
/// from rather than the string the parse produced.
final class CommentSourceRangeTests: XCTestCase {

    /// The whole claim, checked the only way worth checking it: take the range the comment
    /// reports, cut those exact characters out of the source, and see whether they are the
    /// comment.
    func testAClaimedCommentReportsItsOwnCharacters() {
        let cases = [
            "A {>> RS: note <<} B",
            // Smart punctuation shortens the parsed string and not the file, which is the
            // case that rules out counting through the parse.
            "Don't -- really -- {>> RS: note <<} after",
            // Columns are UTF-8 bytes, so anything above ASCII moves them.
            "Ünïcödé ahead {>> RS: note <<} and after",
            "A *b* {>> RS: note <<} c",
            "- item {>> RS: note <<}",
            "# Heading {>> RS: note <<}",
            "| a | b |\n| --- | --- |\n| x {>> RS: note <<} | y |",
            "> quoted {>> RS: note <<}",
            "Line one\nLine two {>> RS: note <<} end",
        ]
        for source in cases {
            let document = Document(parsing: source, options: .parseComments)
            var walker = Comments()
            walker.visit(document)
            XCTAssertEqual(1, walker.found.count, source)
            guard let comment = walker.found.first, let range = comment.range else {
                XCTFail("no range for \(source)"); continue
            }
            let index = SourceByteIndex(source)
            XCTAssertEqual("{>> RS: note <<}", index.text(in: range).map(String.init), source)
        }
    }

    /// Two comments saying exactly the same thing, in one run of text. Their words cannot
    /// tell them apart and their ranges do — which is the entire point.
    func testIdenticalCommentsHaveDifferentRanges() {
        let source = "A {>> RS: same <<} and B {>> RS: same <<} end"
        let document = Document(parsing: source, options: .parseComments)
        var walker = Comments()
        walker.visit(document)
        XCTAssertEqual(2, walker.found.count)
        let index = SourceByteIndex(source)
        XCTAssertNotEqual(walker.found[0].range, walker.found[1].range)
        // …and each points at its own marker, not at the other one.
        for (n, comment) in walker.found.enumerated() {
            guard let range = comment.range, let text = index.text(in: range) else {
                XCTFail("no range"); continue
            }
            XCTAssertEqual("{>> RS: same <<}", String(text))
            let start = source.distance(from: source.startIndex,
                                        to: index.index(of: range.lowerBound)!)
            XCTAssertEqual(n == 0 ? 2 : 25, start, "comment \(n) is at the wrong place")
        }
    }

    /// Several comments in one run, with smart punctuation between them moving every parsed
    /// offset. Each still reports its own characters.
    func testSeveralCommentsAcrossShiftingText() {
        let source = "It's {>> RS: one <<} -- and {>> RS: two <<} -- done"
        let document = Document(parsing: source, options: .parseComments)
        var walker = Comments()
        walker.visit(document)
        let index = SourceByteIndex(source)
        XCTAssertEqual(["{>> RS: one <<}", "{>> RS: two <<}"],
                       walker.found.compactMap { $0.range }.compactMap {
                           index.text(in: $0).map(String.init)
                       })
    }

    /// A comment built by hand belongs to no file, so it reports no range rather than a
    /// misleading one.
    func testAHandBuiltCommentHasNoRange() {
        XCTAssertNil(InlineComment("RS: note").range)
    }

    struct Comments: MarkupWalker {
        var found: [InlineComment] = []
        mutating func visitInlineComment(_ c: InlineComment) { found.append(c) }
    }
}
