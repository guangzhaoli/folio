import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument, NSTextStorageDelegate {
    static let maximumFileSize = 50 * 1024 * 1024
    static let errorDomain = "app.folio.Folio"

    enum ErrorCode: Int {
        case fileTooLarge = 1
    }

    let textStorage = NSTextStorage()
    private(set) var encoding: String.Encoding = .utf8
    private var didWarnUTF8Conversion = false
    weak var attachedSourceView: NSTextView?

    override init() {
        super.init()
        textStorage.delegate = self
    }

    override class var autosavesInPlace: Bool { false }
    override class var preservesVersions: Bool { true }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        ["net.daringfireball.markdown", "org.folio.markdown"]
    }

    override func read(from url: URL, ofType typeName: String) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > Self.maximumFileSize {
            throw Self.fileTooLargeError(size: size)
        }
        try super.read(from: url, ofType: typeName)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        if data.count > Self.maximumFileSize {
            throw Self.fileTooLargeError(size: data.count)
        }

        let detected = try EncodingDetector.decode(data)
        encoding = detected.encoding
        didWarnUTF8Conversion = false

        // Avoid treating the initial load as a user edit.
        textStorage.delegate = nil
        textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.length),
            with: detected.string
        )
        textStorage.delegate = self
        updateChangeCount(.changeCleared)
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(textStorage.string.utf8)
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let isExplicitSave = saveOperation == .saveOperation || saveOperation == .saveAsOperation
            || saveOperation == .saveToOperation
        if isExplicitSave && encoding != .utf8 && !didWarnUTF8Conversion {
            presentUTF8ConversionAlert { [weak self] in
                guard let self else {
                    completionHandler(CocoaError(.userCancelled))
                    return
                }
                self.didWarnUTF8Conversion = true
                self.performSave(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            }
            return
        }
        performSave(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    private func performSave(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    // Window-owned documents: FolioDocumentController.attach creates the chrome.
    override func makeWindowControllers() {}

    override func encodeRestorableState(with coder: NSCoder) {}

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        updateChangeCount(.changeDone)
    }

    private func presentUTF8ConversionAlert(then continueSave: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Folio saves as UTF-8"
        alert.informativeText = "This file will be written as UTF-8 without a byte order mark."
        alert.addButton(withTitle: "OK")
        if let window = windowForSheet {
            alert.beginSheetModal(for: window) { _ in
                continueSave()
            }
        } else {
            alert.runModal()
            continueSave()
        }
    }

    static func fileTooLargeError(size: Int) -> NSError {
        NSError(
            domain: errorDomain,
            code: ErrorCode.fileTooLarge.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "This file is larger than 50 MB.",
                NSLocalizedRecoverySuggestionErrorKey:
                    "Folio cannot open files larger than 50 MB. Try a plain-text editor instead.",
            ]
        )
    }
}
