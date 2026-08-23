/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

/// Capabilities cmark-gfm has always had, which this library previously kept to itself.
class ExposedOptionsTests: XCTestCase {

    // MARK: - Autolinks

    func testAutolinksAreOffByDefault() {
        let expected = """
            Document
            └─ Paragraph
               └─ Text "Visit https://example.com now"
            """
        XCTAssertEqual(expected, Document(parsing: "Visit https://example.com now").debugDescription())
    }

    func testAutolinkExtension() {
        let expected = """
            Document
            └─ Paragraph
               ├─ Text "Visit "
               ├─ Link destination: "https://example.com"
               │  └─ Text "https://example.com"
               └─ Text " now"
            """
        let document = Document(parsing: "Visit https://example.com now", options: .parseAutolinks)
        XCTAssertEqual(expected, document.debugDescription())
    }

    func testAutolinkExtensionCoversWWWAndEmail() {
        let document = Document(parsing: "www.example.com and a@example.com", options: .parseAutolinks)
        let destinations = document.children.flatMap { $0.children }.compactMap { ($0 as? Link)?.destination }
        XCTAssertEqual(["http://www.example.com", "mailto:a@example.com"], destinations)
    }

    // MARK: - Strikethrough

    func testSingleTildeStrikesThroughByDefault() {
        let document = Document(parsing: "a ~single~ tilde")
        XCTAssertEqual(1, document.children.flatMap { $0.children }.compactMap { $0 as? Strikethrough }.count)
    }

    func testStrikethroughCanRequireTwoTildes() {
        let single = Document(parsing: "a ~single~ tilde", options: .strikethroughRequiresTwoTildes)
        XCTAssertTrue(single.children.flatMap { $0.children }.compactMap { $0 as? Strikethrough }.isEmpty)

        let double = Document(parsing: "a ~~double~~ tilde", options: .strikethroughRequiresTwoTildes)
        XCTAssertEqual(1, double.children.flatMap { $0.children }.compactMap { $0 as? Strikethrough }.count)
    }

    // MARK: - Line breaks in HTML

    func testSoftBreakRenderingOptions() {
        let source = "one\ntwo"
        XCTAssertEqual("<p>one\ntwo</p>\n", HTMLFormatter.format(source))
        XCTAssertEqual("<p>one<br />\ntwo</p>\n", HTMLFormatter.format(source, options: .hardBreaks))
        XCTAssertEqual("<p>one two</p>\n", HTMLFormatter.format(source, options: .noBreaks))
    }

    // MARK: - Code fence info strings

    func testLanguageIsTheWholeInfoString() {
        let source = "```swift title=\"Example\"\ncode()\n```"
        let codeBlock = try! XCTUnwrap(Document(parsing: source).child(at: 0) as? CodeBlock)
        XCTAssertEqual("swift title=\"Example\"", codeBlock.language)
        XCTAssertEqual("swift", codeBlock.languageName)
    }

    func testLanguageNameWithoutInfoString() {
        let codeBlock = try! XCTUnwrap(Document(parsing: "```\ncode()\n```").child(at: 0) as? CodeBlock)
        XCTAssertNil(codeBlock.language)
        XCTAssertNil(codeBlock.languageName)
    }
}
