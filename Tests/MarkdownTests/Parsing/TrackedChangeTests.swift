/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

/// CriticMarkup's tracked changes as ``TrackedChange``.
final class TrackedChangeTests: XCTestCase {

    private func parse(_ source: String,
                       _ options: ParseOptions = .parseTrackedChanges) -> Document {
        Document(parsing: source, options: options)
    }

    private func changes(_ source: String,
                         _ options: ParseOptions = .parseTrackedChanges) -> [TrackedChange] {
        var found: [TrackedChange] = []
        func walk(_ markup: Markup) {
            if let change = markup as? TrackedChange { found.append(change) }
            for child in markup.children { walk(child) }
        }
        walk(parse(source, options))
        return found
    }

    // MARK: - Off by default

    func testChangesAreProseWithoutTheOption() {
        let document = Document(parsing: "The term is {--12--}{++18++} months.")
        let paragraph = document.child(at: 0) as! Paragraph
        XCTAssertTrue(paragraph.children.allSatisfy { !($0 is TrackedChange) })
        XCTAssertTrue(paragraph.plainText.contains("{++18++}"), paragraph.plainText)
        // Note the en dashes. Smart punctuation turned `{--12--}` into `{\u{2013}12\u{2013}}`
        // before anything looked at it, which is why the parser accepts that spelling too.
        XCTAssertTrue(paragraph.plainText.contains("{\u{2013}12\u{2013}}"), paragraph.plainText)
    }

    // MARK: - The shape

    func testAnInsertionAndADeletion() {
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "The term is "
               ├─ TrackedChange kind: deletion
               │  └─ Text "12"
               ├─ TrackedChange kind: insertion
               │  └─ Text "18"
               └─ Text " months."
            """
        XCTAssertEqual(expected, parse("The term is {--12--}{++18++} months.").debugDescription())
    }

    func testASubstitution() {
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "The term is "
               ├─ TrackedChange kind: substitution replaced: 12
               │  └─ Text "18"
               └─ Text " months."
            """
        XCTAssertEqual(expected, parse("The term is {~~12~>18~~} months.").debugDescription())
    }

    func testAHighlight() {
        let change = changes("{==Check this clause==} before signing.").first
        XCTAssertEqual(.highlight, change?.kind)
        XCTAssertEqual("Check this clause", change?.plainText)
        XCTAssertEqual("", change?.replaced)
    }

    /// Earliest in the text wins, whatever its kind — otherwise the tree would depend on
    /// the order a dictionary happened to hand back its keys.
    func testTheEarliestMarkerIsClaimedFirst() {
        XCTAssertEqual([.deletion, .insertion, .highlight],
                       changes("{--a--} {++b++} {==c==}").map(\.kind))
        XCTAssertEqual([.insertion, .deletion],
                       changes("{++b++} {--a--}").map(\.kind))
    }

    // MARK: - Content is content

    /// The whole difference from a comment: this text becomes the document if the change is
    /// taken, so it has to keep its markup on the way in.
    func testContentKeepsItsInlineMarkup() {
        let expected = """
            Document
            └─ Paragraph
               └─ TrackedChange kind: insertion
                  ├─ Text "some "
                  ├─ Emphasis
                  │  └─ Text "emphasised"
                  └─ Text " words"
            """
        XCTAssertEqual(expected, parse("{++some *emphasised* words++}").debugDescription())
    }

    func testAChangeMayContainAnother() {
        XCTAssertEqual([.highlight, .insertion],
                       changes("{==look at {++this++}==}").map(\.kind))
    }

    func testPlainTextIsTheContent() {
        // Unlike a comment, whose plainText is empty: this is document text.
        XCTAssertEqual("18", changes("{~~12~>18~~}").first?.plainText)
        XCTAssertEqual("gone", changes("{--gone--}").first?.plainText)
    }

    // MARK: - Prose keeps its braces

    func testMalformedMarkersAreProse() {
        for source in ["{++ unclosed",
                       "{-- unclosed",
                       "{++a--}",                    // mismatched fences
                       "{~~no arrow~~}",             // a substitution needs its `~>`
                       "{+ +not a marker+ +}"] {
            XCTAssertTrue(changes(source).isEmpty, source)
        }
    }

    /// A stray opener does not swallow what follows it: the well-formed span inside is
    /// claimed and the loose marker stays on the page as the text it is.
    func testAStrayOpenerLeavesTheSpanInsideItAlone() {
        let changes = self.changes("{++outer {++inner++}")
        XCTAssertEqual([.insertion], changes.map(\.kind))
        XCTAssertEqual("inner", changes.first?.plainText)
        XCTAssertTrue(parse("{++outer {++inner++}").child(at: 0)!
            .format().contains("{++outer "), "the stray marker is still text")
    }

    func testAChangeCannotSpanALineBreak() {
        XCTAssertTrue(changes("{++one\ntwo++}").isEmpty)
    }

    // MARK: - Code is content

    func testCodeSamplesAreNeverClaimed() {
        XCTAssertTrue(changes("`{++text++}`").isEmpty)
        XCTAssertTrue(changes("```\n{++text++}\n```").isEmpty)
        XCTAssertTrue(changes("    {++text++}").isEmpty)
        XCTAssertTrue(changes("<div>\n{++text++}\n</div>").isEmpty)
    }

    // MARK: - Composition

    func testChangesAndCommentsTogether() {
        let document = parse("The term is {~~12~>18~~} months.{>> RS: check <<}",
                             [.parseTrackedChanges, .parseComments])
        let paragraph = document.child(at: 0) as! Paragraph
        XCTAssertEqual(1, paragraph.children.compactMap { $0 as? TrackedChange }.count)
        XCTAssertEqual(["RS: check"], paragraph.children.compactMap { ($0 as? InlineComment)?.body })
    }

    func testAHeadingMayCarryAChangeAndItsOwnBlock() {
        let heading = parse("# The {++New ++}Title {.unnumbered}",
                            [.parseTrackedChanges, .parseAttributes]).child(at: 0) as! Heading
        XCTAssertEqual(".unnumbered", heading.attributes)
        XCTAssertEqual([.insertion], heading.children.compactMap { ($0 as? TrackedChange)?.kind })
    }

    // MARK: - Walkers must not drop the node

    func testHTMLFormatterEmitsInsAndDel() {
        XCTAssertEqual("<p><del>12</del><ins>18</ins></p>",
                       HTMLFormatter.format(parse("{~~12~>18~~}")).trimmingCharacters(in: .newlines))
        XCTAssertTrue(HTMLFormatter.format(parse("{==hl==}")).contains("<mark>hl</mark>"))
    }

    func testMarkupFormatterRoundTrips() {
        for source in ["The term is {--12--}{++18++} months.",
                       "The term is {~~12~>18~~} months.",
                       "{==Check this==} before signing.",
                       "{++some *emphasised* words++}"] {
            let formatted = parse(source).format().trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(source, formatted)
            XCTAssertEqual(parse(source).debugDescription(), parse(formatted).debugDescription())
        }
    }

    func testTreeDumperShowsTheKind() {
        XCTAssertTrue(parse("{--x--}").debugDescription().contains("kind: deletion"))
        XCTAssertTrue(parse("{~~a~>b~~}").debugDescription().contains("replaced: a"))
    }

    func testVisitorDispatchReachesTheNode() {
        struct Counter: MarkupWalker {
            var count = 0
            mutating func visitTrackedChange(_ change: TrackedChange) {
                count += 1
                descendInto(change)
            }
        }
        var counter = Counter()
        counter.visit(parse("{++a++} and {--b--} and {==c==}"))
        XCTAssertEqual(3, counter.count)
    }
}
