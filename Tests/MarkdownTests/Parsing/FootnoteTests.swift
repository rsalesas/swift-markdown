/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

class FootnoteTests: XCTestCase {
    func testFootnotesAreOffByDefault() {
        let source = "Text[^a].\n\n[^a]: A note."
        let expected = """
            Document
            ├─ Paragraph
            │  └─ Text "Text[^a]."
            └─ Paragraph
               └─ Text "[^a]: A note."
            """
        XCTAssertEqual(expected, Document(parsing: source).debugDescription())
    }

    func testReferenceAndDefinition() {
        let source = "Text[^a].\n\n[^a]: A note."
        let expected = """
            Document @1:1-3:14
            ├─ Paragraph @1:1-1:10
            │  ├─ Text @1:1-1:5 "Text"
            │  ├─ FootnoteReference @1:5-1:9 footnoteID: a
            │  └─ Text @1:9-1:10 "."
            └─ FootnoteDefinition @3:7-3:14 footnoteID: a
               └─ Paragraph @3:7-3:14
                  └─ Text @3:7-3:14 "A note."
            """
        let document = Document(parsing: source, options: .parseFootnotes)
        XCTAssertEqual(expected, document.debugDescription(options: .printSourceLocations))
    }

    /// A definition can hold any block content, not just one line of text.
    func testDefinitionHoldsBlockContent() {
        let source = """
        Text[^a].

        [^a]: First paragraph.

            - a list item

            ```
            and a code block
            ```
        """
        let document = Document(parsing: source, options: .parseFootnotes)
        let definition = try! XCTUnwrap(document.child(at: 1) as? FootnoteDefinition)
        XCTAssertEqual(3, definition.childCount)
        XCTAssertTrue(definition.child(at: 0) is Paragraph)
        XCTAssertTrue(definition.child(at: 1) is UnorderedList)
        XCTAssertTrue(definition.child(at: 2) is CodeBlock)
    }

    /// cmark moves definitions to the end and orders them by first reference, so a
    /// definition's position among the document's children is its footnote number.
    func testDefinitionsAreOrderedByFirstReference() {
        let source = "One[^b] two[^a].\n\n[^a]: A\n[^b]: B"
        let document = Document(parsing: source, options: .parseFootnotes)
        let ids = document.children.compactMap { ($0 as? FootnoteDefinition)?.footnoteID }
        XCTAssertEqual(["b", "a"], ids)
    }

    func testUnreferencedDefinitionIsDropped() {
        let source = "No references here.\n\n[^unused]: Never mentioned."
        let document = Document(parsing: source, options: .parseFootnotes)
        XCTAssertTrue(document.children.compactMap { $0 as? FootnoteDefinition }.isEmpty)
        XCTAssertEqual(1, document.childCount)
    }

    /// A reference with no definition is the author quoting the syntax, and stays
    /// exactly as written.
    func testUnmatchedReferenceStaysLiteral() {
        let source = "See[^missing] here."
        let expected = """
            Document
            └─ Paragraph
               └─ Text "See[^missing] here."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFootnotes).debugDescription())
    }

    func testRepeatedReferencesShareOneDefinition() {
        let source = "A[^x] B[^x].\n\n[^x]: note"
        let document = Document(parsing: source, options: .parseFootnotes)
        var counter = FootnoteReferenceCounter()
        counter.visit(document)
        XCTAssertEqual(2, counter.references)
        XCTAssertEqual(1, document.children.compactMap { $0 as? FootnoteDefinition }.count)
    }

    // MARK: - Construction

    func testConstructAndMutate() {
        var reference = FootnoteReference(footnoteID: "a")
        XCTAssertEqual("a", reference.footnoteID)
        XCTAssertEqual("[^a]", reference.plainText)
        XCTAssertEqual(0, reference.childCount)

        let original = reference
        reference.footnoteID = "b"
        XCTAssertEqual("b", reference.footnoteID)
        XCTAssertFalse(original.isIdentical(to: reference))

        var definition = FootnoteDefinition(footnoteID: "a", [Paragraph(Text("A note."))])
        XCTAssertEqual("a", definition.footnoteID)
        XCTAssertEqual(1, definition.childCount)
        definition.footnoteID = "b"
        XCTAssertEqual("b", definition.footnoteID)
        XCTAssertEqual(1, definition.childCount, "Changing the identifier must keep the note's content")
    }

    // MARK: - Formatting

    func testRoundTripFormatting() {
        let source = """
        Ref[^a] and[^b].

        [^a]: First note.

            Still the first note.

        [^b]: Second note.
        """
        let document = Document(parsing: source, options: .parseFootnotes)
        let reparsed = Document(parsing: document.format(), options: .parseFootnotes)
        XCTAssertEqual(document.debugDescription(), reparsed.debugDescription())
    }

    func testHTMLFormatting() {
        let source = "A[^x] B[^x].\n\n[^x]: The note."
        let expected = """
            <p>A<sup class="footnote-ref"><a href="#fn-1" id="fnref-1" data-footnote-ref>1</a></sup> \
            B<sup class="footnote-ref"><a href="#fn-1" id="fnref-1-2" data-footnote-ref>1</a></sup>.</p>
            <section class="footnotes" data-footnotes>
            <ol>
            <li id="fn-1">
            <p>The note.</p>
            <a href="#fnref-1" class="footnote-backref" data-footnote-backref>↩</a>
            <a href="#fnref-1-2" class="footnote-backref" data-footnote-backref>↩</a>
            </li>
            </ol>
            </section>

            """
        XCTAssertEqual(expected, HTMLFormatter.format(source, parseOptions: .parseFootnotes))
    }
}

/// Counts the footnote references in a tree, which also exercises visitor dispatch
/// for the new element types.
private struct FootnoteReferenceCounter: MarkupWalker {
    var references = 0
    mutating func visitFootnoteReference(_ footnoteReference: FootnoteReference) {
        references += 1
    }
}
