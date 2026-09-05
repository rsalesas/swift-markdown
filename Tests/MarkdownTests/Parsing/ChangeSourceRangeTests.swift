/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

/// A claimed tracked change knows where in the file it came from.
///
/// The property an editor needs, and the one the words cannot give it: two changes may
/// propose exactly the same thing, so only a position tells them apart — and what a position
/// decides here is which characters get replaced when somebody accepts one.
///
/// Everything below checks it the same way: take the range the change reports, cut those
/// characters out of the source, and see whether they are the change.
final class ChangeSourceRangeTests: XCTestCase {

    private func changes(_ source: String) -> [TrackedChange] {
        var walker = Changes()
        walker.visit(Document(parsing: source, options: .parseTrackedChanges))
        return walker.found
    }

    private func spans(_ source: String) -> [String] {
        let index = SourceByteIndex(source)
        return changes(source).compactMap { $0.range }
            .compactMap { index.text(in: $0).map(String.init) }
    }

    func testEachKindReportsItsOwnCharacters() {
        XCTAssertEqual(["{++added++}"], spans("Text {++added++} after."))
        XCTAssertEqual(["{--gone--}"], spans("Text {--gone--} after."))
        XCTAssertEqual(["{~~old~>new~~}"], spans("Text {~~old~>new~~} after."))
        XCTAssertEqual(["{==marked==}"], spans("Text {==marked==} after."))
    }

    /// A deletion is the awkward one: smart punctuation has already turned its `--` into an
    /// en dash by the time the tree exists, so the parsed run and the file do not even spell
    /// the marker the same way. The range still points at what the author typed.
    func testADeletionPointsAtTheDashesTheAuthorTyped() {
        let source = "Text {--gone--} after."
        XCTAssertEqual(["{--gone--}"], spans(source))
        let range = changes(source).first?.range
        XCTAssertEqual(SourceLocation(line: 1, column: 6, source: nil), range?.lowerBound)
    }

    /// Smart punctuation shortens the parsed string and not the file, so nothing can be
    /// located by counting through the parse.
    func testAChangeAfterCurledPunctuationPointsAtItself() {
        XCTAssertEqual(["{++added++}"], spans("Don't -- really -- {++added++} after."))
    }

    /// Columns are UTF-8 bytes, so anything above ASCII moves them.
    func testAChangeAfterNonASCIIPointsAtItself() {
        XCTAssertEqual(["{++added++}"], spans("Ünïcödé ahead {++added++} and after."))
        XCTAssertEqual(["{--gone--}"], spans("Emoji 🎯 ahead {--gone--} and after."))
    }

    /// The content can hold markup, which means the change spans three siblings: the run
    /// before the emphasis, the emphasis, and the run after. The opening fence is in the
    /// first and the closing fence is in the third.
    func testAChangeSpanningSiblingsReportsTheWholeSpan() {
        XCTAssertEqual(["{++some *emphasised* words++}"],
                       spans("A {++some *emphasised* words++} here."))
        XCTAssertEqual(["{--one *two* three--}"], spans("A {--one *two* three--} here."))
    }

    /// The case the whole thing is for: two changes proposing exactly the same words. Their
    /// text cannot tell them apart and their ranges do.
    func testIdenticalChangesHaveDifferentRanges() {
        let source = "Take {--this--} but not {--this--} either."
        let found = changes(source)
        XCTAssertEqual(2, found.count)
        XCTAssertNotEqual(found[0].range, found[1].range)
        XCTAssertEqual(["{--this--}", "{--this--}"], spans(source))
        let index = SourceByteIndex(source)
        let starts = found.compactMap { $0.range }.compactMap { index.index(of: $0.lowerBound) }
            .map { source.distance(from: source.startIndex, to: $0) }
        XCTAssertEqual([5, 24], starts)
    }

    func testSeveralKindsOnOneLineEachPointAtItself() {
        XCTAssertEqual(["{--12--}", "{++18++}", "{==check==}"],
                       spans("The term is {--12--}{++18++} months, {==check==} it."))
    }

    func testChangesOnLaterLinesPointAtThemselves() {
        XCTAssertEqual(["{++one++}", "{--two--}"],
                       spans("Ünïcödé first\n\nSecond {++one++} line\n\nThird {--two--} line"))
    }

    func testAHandBuiltChangeHasNoRange() {
        XCTAssertNil(TrackedChange(kind: .insertion, Text("x")).range)
    }

    // MARK: - What is left beside a change

    /// Claiming a change splits the run of text it was in, and the pieces left either side
    /// keep saying which characters of the file they came from.
    ///
    /// Not a nicety: this parser runs before `CriticMarkupParser`, and that one finds a
    /// comment by reading the source a run of text came from. Runs handed on without a range
    /// left it nothing to read, so a comment sharing a paragraph with a change was found and
    /// could not be placed — see `CommentSourceRangeTests`. The parsed string and the source
    /// span are different lengths wherever smart punctuation has been, which is why each case
    /// below reads the file rather than the parse.
    func testTheTextEitherSideOfAChangeKnowsWhereItCameFrom() {
        let cases: [(String, [String])] = [
            ("The term is {--12--} months.", ["The term is ", " months."]),
            ("The term is {--12--}{++18++} months.", ["The term is ", " months."]),
            // Smart punctuation: the parsed run says `Don’t – really`, the file does not.
            ("Don't -- really {--gone--} after.", ["Don't -- really ", " after."]),
            // Columns are UTF-8 bytes.
            ("Ünïcödé ahead {--gone--} and after.", ["Ünïcödé ahead ", " and after."]),
            ("Emoji 🎯 ahead {--gone--} and after.", ["Emoji 🎯 ahead ", " and after."]),
        ]
        for (source, expected) in cases {
            let document = Document(parsing: source, options: .parseTrackedChanges)
            var walker = Runs()
            walker.visit(document)
            let index = SourceByteIndex(source)
            XCTAssertEqual(expected,
                           walker.found.compactMap { $0.range }
                               .compactMap { index.text(in: $0).map(String.init) },
                           source)
        }
    }

    /// A change's own content is cut from the run the fences were in, and a change claimed
    /// inside another is cut from pieces this rewriter already built. None of it belongs to
    /// the file as a span this parser can name, so all of it reports no range rather than a
    /// misleading one — the same answer the nested change itself gives.
    func testTextInsideAChangeHasNoRange() {
        let document = Document(parsing: "A {==keep {++added++} it==} here.",
                                options: .parseTrackedChanges)
        var walker = Runs()
        walker.visit(document)
        XCTAssertEqual(["keep ", "added", " it"],
                       walker.found.filter { $0.range == nil }.map(\.string))
        // What is outside it still does.
        XCTAssertEqual(["A ", " here."], walker.found.filter { $0.range != nil }.map(\.string))
    }

    /// Every run of text, changes included — so the ones a change was cut out of are seen.
    struct Runs: MarkupWalker {
        var found: [Text] = []
        mutating func visitText(_ text: Text) { found.append(text) }
    }

    struct Changes: MarkupWalker {
        var found: [TrackedChange] = []
        mutating func visitTrackedChange(_ change: TrackedChange) {
            found.append(change)
            descendInto(change)
        }
    }
}
