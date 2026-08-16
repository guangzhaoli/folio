import XCTest
@testable import Folio

final class FindTests: XCTestCase {
    func testFindsPlainAndChineseText() throws {
        let text = "Hello 标题 world 标题"
        let first = FindSupport.nextMatch(in: text, pattern: "标题", from: 0, backwards: false, wrap: false)
        XCTAssertEqual((text as NSString).substring(with: try XCTUnwrap(first)), "标题")
        let second = FindSupport.nextMatch(
            in: text,
            pattern: "标题",
            from: NSMaxRange(try XCTUnwrap(first)),
            backwards: false,
            wrap: false
        )
        XCTAssertEqual(second?.location, (text as NSString).range(of: "标题", options: [], range: NSRange(location: 8, length: text.utf16.count - 8)).location)
    }

    func testSkipsAttachmentOnlyMatches() {
        let text = "ab\u{FFFC}cd"
        XCTAssertTrue(FindSupport.isAttachmentOnly(text, range: NSRange(location: 2, length: 1)))
        XCTAssertFalse(FindSupport.isAttachmentOnly(text, range: NSRange(location: 0, length: 2)))
        let hit = FindSupport.nextMatch(in: text, pattern: "c", from: 0, backwards: false, wrap: false)
        XCTAssertEqual(hit?.location, 3)
    }

    func testWrapsAndGoesBackwards() {
        let text = "one two one"
        let last = FindSupport.nextMatch(in: text, pattern: "one", from: 11, backwards: true, wrap: false)
        XCTAssertEqual(last?.location, 8)
        let wrap = FindSupport.nextMatch(in: text, pattern: "one", from: 11, backwards: false, wrap: true)
        XCTAssertEqual(wrap?.location, 0)
    }

    func testAllMatchesSkipsAttachmentsAndIgnoresCase() {
        let text = "Hello 标题\u{FFFC}标题 hello"
        let hits = FindSupport.allMatches(in: text, pattern: "hello")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].location, 0)
        XCTAssertEqual(FindSupport.allMatches(in: text, pattern: "标题").count, 2)
        XCTAssertEqual(FindSupport.allMatches(in: text, pattern: ""), [])
    }

    func testCurrentMatchIsTheSelectedHit() {
        let matches = [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)]
        XCTAssertEqual(FindSupport.currentMatch(in: matches, selected: matches[1]), matches[1])
        XCTAssertNil(FindSupport.currentMatch(in: matches, selected: NSRange(location: 1, length: 0)))
    }
}
