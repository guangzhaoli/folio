import Foundation

enum EncodingDetector {
    struct Result {
        let string: String
        let encoding: String.Encoding
    }

    enum DetectionError: LocalizedError {
        case unrecognizedEncoding

        var errorDescription: String? {
            "Folio could not detect a text encoding for this file."
        }

        var recoverySuggestion: String? {
            "The file may be binary or use an unsupported encoding."
        }
    }

    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    static let big5HKSCS = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)
        )
    )

    static let eucKR = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )

    static func decode(_ data: Data) throws -> Result {
        if data.starts(with: utf8BOM) {
            if let string = String(data: data, encoding: .utf8) {
                return Result(string: stripBOM(string), encoding: .utf8)
            }
        } else if data.starts(with: utf16LEBOM) {
            if let string = String(data: data, encoding: .utf16LittleEndian) {
                return Result(string: stripBOM(string), encoding: .utf16LittleEndian)
            }
        } else if data.starts(with: utf16BEBOM) {
            if let string = String(data: data, encoding: .utf16BigEndian) {
                return Result(string: stripBOM(string), encoding: .utf16BigEndian)
            }
        } else if let string = String(data: data, encoding: .utf8) {
            // Strict UTF-8 only — never fall back to Latin-1.
            return Result(string: string, encoding: .utf8)
        }

        // GB18030 decodes most Big5 byte pairs, so do not take the first
        // lossless String(data:) hit. Rank CJK first, then let Foundation pick.
        var converted: NSString?
        var usedLossy = ObjCBool(false)
        let detectedRaw = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: candidateRawEncodings,
                .useOnlySuggestedEncodingsKey: true,
                .allowLossyKey: false,
            ],
            convertedString: &converted,
            usedLossyConversion: &usedLossy
        )
        if detectedRaw != 0 && !usedLossy.boolValue {
            let encoding = String.Encoding(rawValue: detectedRaw)
            if let string = String(data: data, encoding: encoding) {
                return Result(string: string, encoding: encoding)
            }
        }

        throw DetectionError.unrecognizedEncoding
    }

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEBOM: [UInt8] = [0xFE, 0xFF]

    // GB18030 and Big5-HKSCS stay at the front of Foundation's candidate list.
    private static var candidateRawEncodings: [UInt] {
        [
            gb18030.rawValue,
            big5HKSCS.rawValue,
            String.Encoding.shiftJIS.rawValue,
            eucKR.rawValue,
            String.Encoding.utf16LittleEndian.rawValue,
            String.Encoding.utf16BigEndian.rawValue,
        ]
    }

    private static func stripBOM(_ string: String) -> String {
        string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
    }
}
