/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

final class CriticMarkupTests: XCTestCase {
    private func parse(_ source: String) -> Document {
        Document(parsing: source, options: .parseComments)
    }

    private func comments(_ source: String) -> [String] {
        var walker = CommentCollector()
        walker.visit(parse(source))
        return walker.bodies
    }

    // MARK: - Off by default

    func testOffByDefault() {
        let expected = """
            Document
            └─ Paragraph
               └─ Text "Text {>> RS: note <<} more."
            """
        XCTAssertEqual(expected, Document(parsing: "Text {>> RS: note <<} more.").debugDescription())
    }

    // MARK: - The shape

    func testASingleComment() {
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "Before "
               ├─ InlineComment body: RS: check this
               └─ Text " after."
            """
        XCTAssertEqual(expected, parse("Before {>> RS: check this <<} after.").debugDescription())
    }

    func testSeveralCommentsInOneRun() {
        XCTAssertEqual(["one", "two"], comments("a {>>one<<} b {>>two<<} c"))
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "a "
               ├─ InlineComment body: one
               ├─ Text " b "
               ├─ InlineComment body: two
               └─ Text " c"
            """
        XCTAssertEqual(expected, parse("a {>>one<<} b {>>two<<} c").debugDescription())
    }

    /// No empty `Text` nodes left behind at either end.
    func testACommentAtTheStartAndEnd() {
        XCTAssertEqual("""
            Document
            └─ Paragraph
               ├─ InlineComment body: note
               └─ Text " after"
            """, parse("{>>note<<} after").debugDescription())
        XCTAssertEqual("""
            Document
            └─ Paragraph
               ├─ Text "before "
               └─ InlineComment body: note
            """, parse("before {>>note<<}").debugDescription())
    }

    func testFormattingAroundACommentSurvives() {
        let document = parse("The **bold** {>> RS: really? <<} truth.")
        XCTAssertEqual(1, document.child(at: 0)!.children.compactMap { $0 as? Strong }.count)
        XCTAssertEqual(["RS: really?"], comments("The **bold** {>> RS: really? <<} truth."))
    }

    // MARK: - A comment is not what a reader sees

    /// One decision in one place: an empty `plainText` is what keeps a comment out of a
    /// heading's title, its slug, a contents page and an outline.
    func testACommentIsNotInThePlainText() {
        let heading = parse("# Terms {>> RS: check <<}").child(at: 0) as! Heading
        XCTAssertEqual("Terms ", heading.plainText)
        XCTAssertFalse(heading.plainText.contains("{"), heading.plainText)
    }

    // MARK: - Prose keeps its braces

    func testNoCloserIsProse() {
        let source = "A {>> RS: unfinished, and then the rest of the document."
        XCTAssertEqual([], comments(source))
        XCTAssertEqual(source, (parse(source).child(at: 0) as! Paragraph).plainText)
    }

    func testAnEmptyBodyIsProse() {
        XCTAssertEqual([], comments("A {>><<} B"))
        XCTAssertEqual([], comments("A {>>   <<} B"))
    }

    func testANestedOpenerIsProse() {
        XCTAssertEqual([], comments("A {>> a {>> b <<} B"))
    }

    /// Deliberately looser than an attribute block, whose closer is a single brace. The
    /// closer here is three characters, so a brace in the body is unambiguous.
    func testABraceInTheBodyIsFine() {
        XCTAssertEqual(["RS: fix the {x} token"], comments("A {>> RS: fix the {x} token <<} B"))
    }

    // MARK: - Code samples are never claimed

    func testInAFencedCodeSample() {
        let code = parse("```md\nA {>> RS: note <<} B\n```").child(at: 0) as! CodeBlock
        XCTAssertEqual("A {>> RS: note <<} B\n", code.code)
    }

    func testInAnIndentedCodeSample() {
        let code = parse("Example:\n\n    A {>> RS: note <<} B\n").child(at: 1) as! CodeBlock
        XCTAssertTrue(code.code.contains("{>> RS: note <<}"), code.code)
    }

    func testInInlineCode() {
        XCTAssertEqual([], comments("Write `{>> RS: note <<}` to comment."))
    }

    func testInARawHTMLBlock() {
        let source = "<div>\n{>> RS: note <<}\n</div>"
        XCTAssertEqual([], comments(source))
    }

    // MARK: - Limits, pinned so they are decisions rather than surprises

    /// cmark never puts a newline inside a `Text` node — a line break is a `SoftBreak`
    /// sibling — so a comment written across two lines is three siblings and no comment.
    func testACommentCannotSpanALineBreak() {
        XCTAssertEqual([], comments("A {>> RS: this runs\nover two lines <<} B"))
    }

    /// `*this*` is emphasis between two runs of text, so the braces never meet. Anything
    /// writing comments programmatically escapes the body; a hand-typed one fails visibly.
    func testACommentSplitByEmphasisIsNotRecognised() {
        XCTAssertEqual([], comments("A {>> RS: don't use *this* <<} B"))
    }

    // MARK: - Composition

    /// The ordering test. Attributes are claimed before comments: the other way round, the
    /// comment splits the heading's text and the attribute block — which must be preceded
    /// by the heading's own words — is refused, leaving `{.unnumbered}` visible.
    func testAHeadingCanCarryBothAnAttributeBlockAndAComment() {
        let document = Document(parsing: "# Chapter {>> RS: check <<} {.unnumbered}",
                                options: [.parseAttributes, .parseComments])
        let heading = document.child(at: 0) as! Heading
        XCTAssertEqual(".unnumbered", heading.attributes)
        XCTAssertEqual(["RS: check"], heading.children.compactMap { ($0 as? InlineComment)?.body })
        XCTAssertFalse(heading.plainText.contains("{"), heading.plainText)
    }

    func testInsideAFencedDiv() {
        let document = Document(parsing: "::: note\nA {>> RS: check <<} B\n:::",
                                options: [.parseFencedDivs, .parseComments])
        var walker = CommentCollector()
        walker.visit(document)
        XCTAssertEqual(["RS: check"], walker.bodies)
    }

    // MARK: - Walkers must not drop it

    func testMarkupFormatterRoundTrips() {
        let document = parse("Before {>> RS: check this <<} after.")
        let formatted = document.format()
        XCTAssertTrue(formatted.contains("{>> RS: check this <<}"), formatted)
        XCTAssertEqual(document.debugDescription(),
                       Document(parsing: formatted, options: .parseComments).debugDescription(),
                       formatted)
    }

    /// Dropped on purpose, not by the visitor default nobody implemented.
    func testHTMLFormatterEmitsNothing() {
        let html = HTMLFormatter.format(parse("Before {>> RS: secret <<} after."))
        XCTAssertFalse(html.contains("secret"), html)
        XCTAssertFalse(html.contains("{>>"), html)
        XCTAssertTrue(html.contains("Before"), html)
        XCTAssertTrue(html.contains("after."), html)
    }

    func testTreeDumperShowsTheBody() {
        XCTAssertTrue(parse("A {>>note<<}").debugDescription().contains("InlineComment body: note"))
    }

    func testVisitorDispatchReachesTheNode() {
        XCTAssertEqual(["one", "two"], comments("a {>>one<<}\n\nb {>>two<<}"))
    }

    // MARK: - Source ranges
    //
    // A claimed comment carries a real one, which is what lets an application find the
    // characters again — and the words cannot, since two comments may say the same thing.
    // It used to carry none: the rewriter synthesises the node, and a synthesised node has
    // no position. What changed is where the position is read from. The run of text holding
    // a comment already knows which characters of the file it came from, so the comment
    // inside it is found by reading THOSE characters, rather than by counting through a
    // parsed string that smart punctuation has already changed the length of.

    func testAClaimedCommentCarriesItsSourceRange() {
        let source = "Before {>> RS: check <<} after."
        let document = parse(source)
        let comment = document.child(at: 0)!.children.compactMap { $0 as? InlineComment }.first
        let range = try? XCTUnwrap(comment?.range)
        XCTAssertEqual(SourceLocation(line: 1, column: 8, source: nil), range?.lowerBound)
        XCTAssertEqual(SourceLocation(line: 1, column: 25, source: nil), range?.upperBound)
        // The claim in full: those characters, cut out of the file, are the comment.
        XCTAssertEqual("{>> RS: check <<}",
                       range.flatMap { SourceByteIndex(source).text(in: $0) }.map(String.init))
    }
}

private struct CommentCollector: MarkupWalker {
    var bodies: [String] = []
    mutating func visitInlineComment(_ inlineComment: InlineComment) {
        bodies.append(inlineComment.body)
    }
}
