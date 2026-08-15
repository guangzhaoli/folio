import XCTest
@testable import Folio

final class ParseTests: XCTestCase {
    func testHeadingsAndOutline() {
        let snap = MarkdownParser.parse(text: "# Title\n\n## Child\n\nParagraph.\n", generation: 1)
        XCTAssertEqual(snap.outline.map(\.title), ["Title", "Child"])
        XCTAssertEqual(snap.outline.map(\.level), [1, 2])
        XCTAssertTrue(snap.nodes.contains { if case .heading(1) = $0.kind { return true }; return false })
    }

    func testChineseAndEmphasis() {
        let snap = MarkdownParser.parse(text: "这是 **你好** 世界\n", generation: 1)
        XCTAssertFalse(snap.nodes.isEmpty)
        let text = MarkdownParser.plainText(snap.nodes.first?.inlines ?? [])
        XCTAssertTrue(text.contains("你好"))
        XCTAssertTrue(text.contains("世界"))
    }

    func testTaskListAndTable() {
        let md = """
        - [x] done
        - [ ] todo

        | a | b |
        | --- | --- |
        | 1 | 2 |
        """
        let snap = MarkdownParser.parse(text: md, generation: 1)
        let tasks = snap.nodes.flatMap(\.children).compactMap { node -> Bool? in
            if case .item(let checked) = node.kind { return checked }
            return nil
        }
        XCTAssertEqual(tasks, [true, false])
        XCTAssertTrue(snap.nodes.contains { if case .table = $0.kind { return true }; return false })
    }

    func testSourceMapChineseRange() {
        let text = "中文"
        let snap = MarkdownParser.parse(text: text + "\n", generation: 1)
        guard let para = snap.nodes.first else {
            return XCTFail("missing paragraph")
        }
        let range = para.source.utf16Range
        XCTAssertNotEqual(range.location, NSNotFound)
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: NSIntersectionRange(range, NSRange(location: 0, length: ns.length))), "中文")
    }

    func testRenderIncludesHeading() {
        let snap = MarkdownParser.parse(text: "# Hello\n\nBody\n", generation: 1)
        let doc = ReadingRenderer.render(snapshot: snap, baseDirectory: nil, style: .default)
        XCTAssertTrue(doc.text.string.contains("Hello"))
        XCTAssertTrue(doc.text.string.contains("Body"))
        XCTAssertFalse(doc.blockCharRanges.isEmpty)
    }

    func testTableAndQuoteUseBlockChrome() {
        let md = """
        > A quoted line.

        | Name | Value |
        | --- | --- |
        | α | 1 |
        """
        let snap = MarkdownParser.parse(text: md, generation: 1)
        let doc = ReadingRenderer.render(snapshot: snap, baseDirectory: nil, style: .default)
        var count = 0
        doc.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: doc.text.length)) { value, _, _ in
            if value is NSTextAttachment { count += 1 }
        }
        XCTAssertGreaterThanOrEqual(count, 2, "quote and table should be native block attachments")
    }

    func testHeadingPathFollowsDepth() throws {
        let snap = MarkdownParser.parse(
            text: "# Title\n\n## Overview\n\n### Hello\n\n## Other\n",
            generation: 1
        )
        let hello = try XCTUnwrap(snap.outline.first { $0.title == "Hello" })
        let other = try XCTUnwrap(snap.outline.first { $0.title == "Other" })
        XCTAssertEqual(
            OutlineItem.path(in: snap.outline, throughLine: hello.span.startLine).map(\.title),
            ["Title", "Overview", "Hello"]
        )
        XCTAssertEqual(
            OutlineItem.path(in: snap.outline, throughLine: other.span.startLine).map(\.title),
            ["Title", "Other"]
        )
        XCTAssertEqual(
            OutlineItem.siblings(of: hello, in: snap.outline).map(\.title),
            ["Hello"]
        )
        XCTAssertEqual(
            OutlineItem.siblings(of: other, in: snap.outline).map(\.title),
            ["Overview", "Other"]
        )
    }

    func testReadingMeasureFillsNarrowPane() {
        XCTAssertEqual(ReadingTextView.usableWidth(in: 400), 328)
        XCTAssertEqual(ReadingTextView.usableWidth(in: 1000), 860)
        XCTAssertGreaterThan(ReadingTextView.usableWidth(in: 480), 380)
    }

    func testListUsesHangingIndent() {
        let snap = MarkdownParser.parse(text: "- first item that wraps\n- second\n", generation: 1)
        let doc = ReadingRenderer.render(snapshot: snap, baseDirectory: nil, style: .default)
        var foundHang = false
        doc.text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: doc.text.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            if style.headIndent > style.firstLineHeadIndent {
                foundHang = true
            }
        }
        XCTAssertTrue(foundHang)
    }
}
