import XCTest
@testable import Folio

final class EncodingTests: XCTestCase {
    func testUTF8() throws {
        let data = Data("# Hello, Folio\n".utf8)
        let result = try EncodingDetector.decode(data)
        XCTAssertEqual(result.string, "# Hello, Folio\n")
        XCTAssertEqual(result.encoding, .utf8)
    }

    func testUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: "BOM text".utf8)
        let result = try EncodingDetector.decode(data)
        XCTAssertEqual(result.string, "BOM text")
        XCTAssertEqual(result.encoding, .utf8)
    }

    func testUTF16LEBOM() throws {
        var data = Data([0xFF, 0xFE])
        for scalar in "Hello".unicodeScalars {
            let value = UInt16(scalar.value)
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        let result = try EncodingDetector.decode(data)
        XCTAssertEqual(result.string, "Hello")
        XCTAssertEqual(result.encoding, .utf16LittleEndian)
    }

    func testUTF16BEBOM() throws {
        var data = Data([0xFE, 0xFF])
        for scalar in "Hello".unicodeScalars {
            let value = UInt16(scalar.value)
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value))
        }
        let result = try EncodingDetector.decode(data)
        XCTAssertEqual(result.string, "Hello")
        XCTAssertEqual(result.encoding, .utf16BigEndian)
    }

    func testGB18030Chinese() throws {
        let original = "中文测试"
        let data = try XCTUnwrap(original.data(using: EncodingDetector.gb18030))
        XCTAssertNil(String(data: data, encoding: .utf8), "fixture must not be valid UTF-8")
        let result = try EncodingDetector.decode(data)
        XCTAssertEqual(result.string, original)
        XCTAssertEqual(result.encoding, EncodingDetector.gb18030)
    }

    func testBig5() throws {
        let original = "繁體中文"
        let data = try XCTUnwrap(original.data(using: EncodingDetector.big5HKSCS))
        XCTAssertNil(String(data: data, encoding: .utf8), "fixture must not be valid UTF-8")
        let result = try EncodingDetector.decode(data)
        XCTAssertEqual(result.string, original)
        XCTAssertEqual(result.encoding, EncodingDetector.big5HKSCS)
    }

    func testRejectsRandomBinaryThatIsNotGB18030OrBig5() {
        // Odd-length 0xFF is invalid UTF-8, GB18030, Big5, and UTF-16.
        let data = Data(repeating: 0xFF, count: 33)
        XCTAssertThrowsError(try EncodingDetector.decode(data)) { error in
            guard case EncodingDetector.DetectionError.unrecognizedEncoding = error else {
                XCTFail("expected unrecognizedEncoding, got \(error)")
                return
            }
        }
    }

    func testRejectsLatin1Cafe() {
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        XCTAssertNil(String(data: data, encoding: .utf8))
        XCTAssertThrowsError(try EncodingDetector.decode(data)) { error in
            guard case EncodingDetector.DetectionError.unrecognizedEncoding = error else {
                XCTFail("expected unrecognizedEncoding, got \(error)")
                return
            }
        }
    }

    func testRejectsFilesOver50MB() {
        let data = Data(count: MarkdownDocument.maximumFileSize + 1)
        let document = MarkdownDocument()
        XCTAssertThrowsError(try document.read(from: data, ofType: "net.daringfireball.markdown")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, MarkdownDocument.errorDomain)
            XCTAssertEqual(nsError.code, MarkdownDocument.ErrorCode.fileTooLarge.rawValue)
        }
    }

    func testURLReadRejectsOver50MBAndAcceptsExactly50MB() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-encoding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let overURL = directory.appendingPathComponent("over.md")
        try Data(count: MarkdownDocument.maximumFileSize + 1).write(to: overURL)
        XCTAssertThrowsError(
            try MarkdownDocument().read(from: overURL, ofType: "net.daringfireball.markdown")
        ) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, MarkdownDocument.errorDomain)
            XCTAssertEqual(nsError.code, MarkdownDocument.ErrorCode.fileTooLarge.rawValue)
        }

        let exactURL = directory.appendingPathComponent("exact.md")
        try Data(count: MarkdownDocument.maximumFileSize).write(to: exactURL)
        let exact = MarkdownDocument()
        try exact.read(from: exactURL, ofType: "net.daringfireball.markdown")
        XCTAssertEqual(exact.textStorage.length, MarkdownDocument.maximumFileSize)
        XCTAssertEqual(exact.encoding, .utf8)
    }

    func testSaveIsUTF8WithoutBOM() throws {
        let document = MarkdownDocument()
        document.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "你好")
        let data = try document.data(ofType: "net.daringfireball.markdown")
        XCTAssertFalse(data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(String(data: data, encoding: .utf8), "你好")
    }

    func testGB18030RoundTripSavesUTF8() throws {
        let original = "中文测试"
        let data = try XCTUnwrap(original.data(using: EncodingDetector.gb18030))
        let document = MarkdownDocument()
        try document.read(from: data, ofType: "net.daringfireball.markdown")
        XCTAssertEqual(document.textStorage.string, original)
        XCTAssertEqual(document.encoding, EncodingDetector.gb18030)
        let saved = try document.data(ofType: "org.folio.markdown")
        XCTAssertFalse(saved.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(String(data: saved, encoding: .utf8), original)
    }

    func testAutosavePolicyAndWritableTypes() {
        XCTAssertFalse(MarkdownDocument.autosavesInPlace)
        XCTAssertTrue(MarkdownDocument.preservesVersions)
        let types = MarkdownDocument().writableTypes(for: .saveOperation)
        XCTAssertEqual(types, ["net.daringfireball.markdown", "org.folio.markdown"])
    }

    func testTypeForContentsMapsMarkdownExtensions() throws {
        let controller = FolioDocumentController.folio
        for ext in ["md", "markdown", "mdown", "mkd", "mdwn"] {
            let url = URL(fileURLWithPath: "/tmp/note.\(ext)")
            XCTAssertEqual(
                try controller.typeForContents(of: url),
                FolioDocumentController.markdownType
            )
        }
    }

    func testOpenReusesEmptyWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reuse.md")
        try Data("# reuse\n".utf8).write(to: url)

        let window = MainWindowController()
        window.showWindow(nil)
        window.window?.makeKeyAndOrderFront(nil)
        let originalWindow = window.window
        XCTAssertNotNil(originalWindow)
        XCTAssertNil(window.document)

        let opened = expectation(description: "opened")
        FolioDocumentController.folio.openMarkdown(at: url, in: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(window.markdownDocument?.textStorage.string, "# reuse\n")
            XCTAssertTrue(window.window === originalWindow)
            XCTAssertEqual(window.window?.title, "reuse.md")
            opened.fulfill()
        }
        wait(for: [opened], timeout: 5)
        window.close()
    }

    func testReplaceDocumentKeepsWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-replace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("one.md")
        let second = directory.appendingPathComponent("two.md")
        try Data("# one\n".utf8).write(to: first)
        try Data("# two\n".utf8).write(to: second)

        let window = MainWindowController()
        window.showWindow(nil)
        let originalWindow = window.window
        FolioDocumentController.folio.openWorkspace(at: directory, in: window, forceCurrentWindow: true)
        XCTAssertEqual(window.workspace?.rootURL, directory.standardizedFileURL)

        let opened = expectation(description: "replaced")
        FolioDocumentController.folio.openMarkdown(at: first, in: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            FolioDocumentController.folio.replaceDocument(in: window, with: second)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                XCTAssertEqual(window.markdownDocument?.textStorage.string, "# two\n")
                XCTAssertTrue(window.window === originalWindow)
                XCTAssertNotNil(window.workspace)
                opened.fulfill()
            }
        }
        wait(for: [opened], timeout: 5)
        window.close()
    }
}
