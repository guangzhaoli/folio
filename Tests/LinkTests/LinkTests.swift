import XCTest
import AppKit
@testable import Folio

final class LinkTests: XCTestCase {
    func testResolvesRelativeImageWithSpaceAndPercent() {
        let base = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        guard case .localFile(let spaced, nil) = PathResolver.resolve(
            destination: "images/foo bar.png",
            baseDirectory: base
        ) else {
            return XCTFail("expected local file")
        }
        XCTAssertEqual(spaced.path, "/tmp/notes/images/foo bar.png")

        guard case .localFile(let encoded, nil) = PathResolver.resolve(
            destination: "images/foo%20bar.png",
            baseDirectory: base
        ) else {
            return XCTFail("expected decoded local file")
        }
        XCTAssertEqual(encoded.path, "/tmp/notes/images/foo bar.png")
    }

    func testParentDirectoryAndFragment() {
        let base = URL(fileURLWithPath: "/tmp/notes/docs", isDirectory: true)
        guard case .localFile(let url, let fragment) = PathResolver.resolve(
            destination: "../guide.md#install",
            baseDirectory: base
        ) else {
            return XCTFail("expected local markdown")
        }
        XCTAssertEqual(url.path, "/tmp/notes/guide.md")
        XCTAssertEqual(fragment, "install")
    }

    func testSchemesAndBareFragment() {
        XCTAssertEqual(
            PathResolver.resolve(destination: "#overview", baseDirectory: nil),
            .fragmentOnly("overview")
        )
        guard case .remote(let http) = PathResolver.resolve(
            destination: "https://example.com/a",
            baseDirectory: nil
        ) else {
            return XCTFail("expected remote")
        }
        XCTAssertEqual(http.host, "example.com")
        guard case .mail = PathResolver.resolve(destination: "mailto:a@b.com", baseDirectory: nil) else {
            return XCTFail("expected mail")
        }
        XCTAssertEqual(PathResolver.resolve(destination: "javascript:alert(1)", baseDirectory: nil), .invalid)
        XCTAssertEqual(PathResolver.resolve(destination: "docs/a.md", baseDirectory: nil), .invalid)
    }

    func testHeadingSlugMatch() {
        let items = [
            OutlineItem(id: BlockID(kindTag: 1, startLine: 1, startColumn: 1), level: 1, title: "打招呼", span: SourceSpan(startLine: 1, startColumn: 1, endLine: 1, endColumn: 4, utf16Range: NSRange(location: 0, length: 3))),
            OutlineItem(id: BlockID(kindTag: 1, startLine: 3, startColumn: 1), level: 2, title: "Install Guide", span: SourceSpan(startLine: 3, startColumn: 1, endLine: 3, endColumn: 14, utf16Range: NSRange(location: 4, length: 13))),
        ]
        XCTAssertEqual(OutlineItem.matching(fragment: "打招呼", in: items)?.title, "打招呼")
        XCTAssertEqual(OutlineItem.matching(fragment: "install-guide", in: items)?.title, "Install Guide")
    }

    func testRenderUsesLocalImageAndKeepsLinkDestination() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("dot.png")
        try makeTinyPNG().write(to: png)

        let snap = MarkdownParser.parse(
            text: "See [guide](other.md#hi) and ![](dot.png)\n",
            generation: 1
        )
        let doc = ReadingRenderer.render(snapshot: snap, baseDirectory: folder, style: .default)
        var destinations: [String] = []
        var attachments = 0
        doc.text.enumerateAttributes(in: NSRange(location: 0, length: doc.text.length)) { attrs, _, _ in
            if let dest = attrs[PathResolver.destinationKey] as? String {
                destinations.append(dest)
            }
            if attrs[.attachment] is NSTextAttachment {
                attachments += 1
            }
        }
        XCTAssertTrue(destinations.contains("other.md#hi"))
        XCTAssertGreaterThanOrEqual(attachments, 1)
    }

    private func makeTinyPNG() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }
}