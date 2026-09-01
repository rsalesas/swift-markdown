/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

final class FencedDivTests: XCTestCase {

    // MARK: - Off by default

    func testOffByDefault() {
        let source = "::: warning\nText.\n:::"
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "::: warning"
               ├─ SoftBreak
               ├─ Text "Text."
               ├─ SoftBreak
               └─ Text ":::"
            """
        XCTAssertEqual(expected, Document(parsing: source).debugDescription())
    }

    // MARK: - The shape

    func testOpenerAndCloser() {
        let source = "::: warning\nText.\n:::"
        let expected = """
            Document
            └─ FencedDiv attributeText: warning
               └─ Paragraph
                  └─ Text "Text."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    func testContentIsParsedAsMarkdown() {
        let source = "::: note\nSome **bold** text.\n:::"
        let expected = """
            Document
            └─ FencedDiv attributeText: note
               └─ Paragraph
                  ├─ Text "Some "
                  ├─ Strong
                  │  └─ Text "bold"
                  └─ Text " text."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    func testNesting() {
        let source = "::: outer\n::: inner\nText.\n:::\n:::"
        let expected = """
            Document
            └─ FencedDiv attributeText: outer
               └─ FencedDiv attributeText: inner
                  └─ Paragraph
                     └─ Text "Text."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    func testSiblingsAroundADiv() {
        let source = "Before.\n\n::: note\nInside.\n:::\n\nAfter."
        let expected = """
            Document
            ├─ Paragraph
            │  └─ Text "Before."
            ├─ FencedDiv attributeText: note
            │  └─ Paragraph
            │     └─ Text "Inside."
            └─ Paragraph
               └─ Text "After."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    // MARK: - Attributes

    func testBareNameIsAClass() {
        let document = Document(parsing: "::: warning\nText.\n:::", options: .parseFencedDivs)
        let div = document.child(at: 0) as! FencedDiv
        XCTAssertEqual("warning", div.attributeText)
        XCTAssertEqual("warning", div.name)
        XCTAssertEqual(["warning"], div.classes)
        XCTAssertNil(div.identifier)
    }

    /// Pandoc leaves a multi-word bare spec undefined; a name is one class.
    func testOnlyTheFirstWordOfABareSpecIsTheName() {
        let document = Document(parsing: "::: warning and more\nText.\n:::", options: .parseFencedDivs)
        let div = document.child(at: 0) as! FencedDiv
        XCTAssertEqual(["warning"], div.classes)
        XCTAssertEqual("warning and more", div.attributeText, "the source is kept whole")
    }

    func testBraceForm() {
        let document = Document(parsing: "::: {.callout .wide #intro}\nText.\n:::", options: .parseFencedDivs)
        let div = document.child(at: 0) as! FencedDiv
        XCTAssertNil(div.name)
        XCTAssertEqual(["callout", "wide"], div.classes)
        XCTAssertEqual("intro", div.identifier)
    }

    /// Nothing an author wrote is silently dropped, even where this type has no use
    /// for it.
    func testKeyValuePairsAreKept() {
        let document = Document(parsing: "::: {.note lang=fr}\nText.\n:::", options: .parseFencedDivs)
        let div = document.child(at: 0) as! FencedDiv
        XCTAssertEqual(["note"], div.classes)
        XCTAssertEqual(1, div.keyValuePairs.count)
        XCTAssertEqual("lang", div.keyValuePairs.first?.name)
        XCTAssertEqual("fr", div.keyValuePairs.first?.value)
    }

    func testMoreThanThreeColonsOpensAndCloses() {
        let source = ":::: wide\nText.\n::::"
        let expected = """
            Document
            └─ FencedDiv attributeText: wide
               └─ Paragraph
                  └─ Text "Text."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    // MARK: - Code is content

    func testMarkerInsideAFencedCodeBlock() {
        let source = "```\n::: warning\ncode\n:::\n```"
        let expected = """
            Document
            └─ CodeBlock language: none
               ::: warning
               code
               :::
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    /// The case a line-prefix fence tracker cannot see at all, and the reason this
    /// parser asks cmark where the code is rather than tracking fences itself.
    func testMarkerInsideAnIndentedCodeBlock() {
        let source = "Example:\n\n    ::: warning\n    Body.\n    :::\n"
        let expected = """
            Document
            ├─ Paragraph
            │  └─ Text "Example:"
            └─ CodeBlock language: none
               ::: warning
               Body.
               :::
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    /// A tracker keeping only the first three characters of a fence closes this one
    /// early and rewrites the marker.
    func testMarkerInsideALongerFence() {
        let source = "````\n```\n::: warning\n```\n````"
        let document = Document(parsing: source, options: .parseFencedDivs)
        XCTAssertEqual(1, document.childCount)
        XCTAssertTrue(document.child(at: 0) is CodeBlock)
    }

    func testMarkerInsideATildeFence() {
        let source = "~~~\n::: warning\ncode\n~~~"
        let document = Document(parsing: source, options: .parseFencedDivs)
        XCTAssertEqual(1, document.childCount)
        XCTAssertTrue(document.child(at: 0) is CodeBlock)
    }

    // MARK: - Malformed input

    /// Forgiving the author beats swallowing the rest of their document.
    func testUnclosedDivRunsToTheEnd() {
        let source = "::: note\nText.\n\nMore."
        let expected = """
            Document
            └─ FencedDiv attributeText: note
               ├─ Paragraph
               │  └─ Text "Text."
               └─ Paragraph
                  └─ Text "More."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    /// A closer with nothing open closes nothing, so it is text the author wrote and it
    /// stays. Blanking it because it looks like a marker would delete a line of someone's
    /// document.
    func testStrayCloserIsContent() {
        let source = "Text.\n\n:::\n\nMore."
        let expected = """
            Document
            ├─ Paragraph
            │  └─ Text "Text."
            ├─ Paragraph
            │  └─ Text ":::"
            └─ Paragraph
               └─ Text "More."
            """
        XCTAssertEqual(expected, Document(parsing: source, options: .parseFencedDivs).debugDescription())
    }

    // MARK: - Scope that belongs to the whole document

    /// The property that rules out parsing each region on its own: a reference inside a
    /// div still finds a definition outside it.
    func testFootnoteReferenceInsideADivFindsItsDefinitionOutside() {
        let source = "::: note\nA claim.[^a]\n:::\n\n[^a]: The evidence."
        let document = Document(parsing: source, options: [.parseFencedDivs, .parseFootnotes])
        let references = document.children.flatMap { $0.children }
            .flatMap { $0.children }.compactMap { $0 as? FootnoteReference }
        XCTAssertEqual(1, references.count, "\(document.debugDescription())")
        XCTAssertEqual(1, document.children.compactMap { $0 as? FootnoteDefinition }.count)
    }

    /// cmark hoists definitions to the end of the document and their order there is
    /// their numbering. Re-nesting one by source position would undo that.
    func testFootnoteDefinitionInsideADivStaysAtTheTopLevel() {
        let source = "::: note\nA claim.[^a]\n\n[^a]: The evidence.\n:::"
        let document = Document(parsing: source, options: [.parseFencedDivs, .parseFootnotes])
        XCTAssertEqual(1, document.children.compactMap { $0 as? FootnoteDefinition }.count,
                       "\(document.debugDescription())")
    }

    func testLinkReferenceDefinitionOutsideADivStillResolves() {
        let source = "::: note\nSee [the docs][d].\n:::\n\n[d]: https://example.com"
        let document = Document(parsing: source, options: .parseFencedDivs)
        let links = document.children.flatMap { $0.children }
            .flatMap { $0.children }.compactMap { $0 as? Link }
        XCTAssertEqual("https://example.com", links.first?.destination, "\(document.debugDescription())")
    }

    // MARK: - Composition with block directives

    func testFencedDivsAndBlockDirectivesAreIndependent() {
        // Directives on, divs off: `:::` is ordinary text.
        let directivesOnly = Document(parsing: "::: note\nText.\n:::", options: .parseBlockDirectives)
        XCTAssertTrue(directivesOnly.child(at: 0) is Paragraph)

        // Divs on, directives off: `@word` is ordinary text, and keeps its whole line.
        let divsOnly = Document(parsing: "@channel please review this.", options: .parseFencedDivs)
        XCTAssertEqual("""
            Document
            └─ Paragraph
               └─ Text "@channel please review this."
            """, divsOnly.debugDescription())
    }

    // MARK: - Visitors must not drop the node

    /// `MarkupVisitor` ships a default implementation for every method, so a walker that
    /// forgets this node still compiles — and silently descends past it, losing the div
    /// while keeping its children. These are the three that ship.
    func testHTMLFormatterEmitsTheDiv() {
        let document = Document(parsing: "::: {.callout #intro}\nText.\n:::", options: .parseFencedDivs)
        let html = HTMLFormatter.format(document)
        XCTAssertTrue(html.contains("<div class=\"callout\" id=\"intro\">"), html)
        XCTAssertTrue(html.contains("</div>"), html)
    }

    func testMarkupFormatterRoundTrips() {
        let source = "::: warning\nText.\n:::"
        let document = Document(parsing: source, options: .parseFencedDivs)
        let formatted = document.format()
        let reparsed = Document(parsing: formatted, options: .parseFencedDivs)
        XCTAssertEqual(document.debugDescription(), reparsed.debugDescription(), formatted)
    }

    func testTreeDumperShowsTheAttributeText() {
        let document = Document(parsing: "::: {.a #b}\nText.\n:::", options: .parseFencedDivs)
        XCTAssertTrue(document.debugDescription().contains("attributeText: {.a #b}"),
                      document.debugDescription())
    }

    func testVisitorDispatchReachesTheNode() {
        var counter = FencedDivCounter()
        counter.visit(Document(parsing: "::: a\n::: b\nText.\n:::\n:::", options: .parseFencedDivs))
        XCTAssertEqual(2, counter.divs)
    }
}

private struct FencedDivCounter: MarkupWalker {
    var divs = 0
    mutating func visitFencedDiv(_ fencedDiv: FencedDiv) {
        divs += 1
        descendInto(fencedDiv)
    }
}
