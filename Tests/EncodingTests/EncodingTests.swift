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

    func testRejectsFilesOver50MB() {
        let data = Data(count: MarkdownDocument.maximumFileSize + 1)
        let document = MarkdownDocument()
        XCTAssertThrowsError(try document.read(from: data, ofType: "net.daringfireball.markdown")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, MarkdownDocument.errorDomain)
            XCTAssertEqual(nsError.code, MarkdownDocument.ErrorCode.fileTooLarge.rawValue)
        }
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
}
