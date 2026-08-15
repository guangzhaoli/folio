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
}
