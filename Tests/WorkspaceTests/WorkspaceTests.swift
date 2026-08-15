import XCTest
@testable import Folio

final class WorkspaceTests: XCTestCase {
    func testWalkerSkipsVendorAndDotfiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-ws-\(UUID().uuidString)", isDirectory: true)
        let hidden = root.appendingPathComponent(".secret.md")
        let keep = root.appendingPathComponent("keep.md")
        let vendor = root.appendingPathComponent("node_modules", isDirectory: true)
        let vendorFile = vendor.appendingPathComponent("lib.md")
        let nested = root.appendingPathComponent("docs", isDirectory: true)
        let nestedFile = nested.appendingPathComponent("guide.md")
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("# hidden\n".utf8).write(to: hidden)
        try Data("# keep\n".utf8).write(to: keep)
        try Data("# vendored\n".utf8).write(to: vendorFile)
        try Data("# guide\n".utf8).write(to: nestedFile)
        try Data("not markdown".utf8).write(to: root.appendingPathComponent("skip.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = Workspace(root: root)
        let names = Set(workspace.markdownFiles().map(\.lastPathComponent))
        XCTAssertEqual(names, ["keep.md", "guide.md"])
        XCTAssertFalse(names.contains("lib.md"))
        XCTAssertFalse(names.contains(".secret.md"))
        XCTAssertFalse(names.contains("skip.txt"))
    }

    func testNextPreviousMarkdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-nav-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("a.md")
        let b = root.appendingPathComponent("b.md")
        try Data("# a\n".utf8).write(to: a)
        try Data("# b\n".utf8).write(to: b)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = Workspace(root: root)
        XCTAssertEqual(workspace.nextMarkdown(after: a)?.lastPathComponent, "b.md")
        XCTAssertEqual(workspace.previousMarkdown(before: b)?.lastPathComponent, "a.md")
        XCTAssertNil(workspace.nextMarkdown(after: b))
    }

    func testEmptyFolderHasNoMarkdown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("plain".utf8).write(to: root.appendingPathComponent("notes.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = Workspace(root: root)
        XCTAssertFalse(workspace.containsMarkdown())
        XCTAssertTrue(workspace.markdownFiles().isEmpty)
    }
}
