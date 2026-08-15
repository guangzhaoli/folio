import AppKit
import UniformTypeIdentifiers

final class FolioDocumentController: NSDocumentController {
    static let markdownType = "net.daringfireball.markdown"
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdwn"]

    static var folio: FolioDocumentController {
        shared as! FolioDocumentController
    }

    /// Window that presented the open panel; first file attaches here.
    private var preferredAttachWindow: MainWindowController?

    override var defaultType: String? { Self.markdownType }

    override func documentClass(forType typeName: String) -> AnyClass? {
        MarkdownDocument.self
    }

    /// LS often tags `.md` as public.plain-text; keep those files on MarkdownDocument.
    override func typeForContents(of url: URL) throws -> String {
        if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
            return Self.markdownType
        }
        return try super.typeForContents(of: url)
    }

    // Default `openDocument:` asks Launch Services who should open the file.
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = Self.openPanelContentTypes

        let hostController = (NSApp.keyWindow?.windowController as? MainWindowController)
            ?? currentEmptyWindow()
        preferredAttachWindow = hostController

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK else {
                self.preferredAttachWindow = nil
                return
            }
            for url in panel.urls {
                self.openMarkdown(at: url)
            }
        }
        if let host = hostController?.window {
            panel.beginSheetModal(for: host, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        if let existing = document(for: url) as? MarkdownDocument {
            existing.windowControllers.first?.showWindow(nil)
            completionHandler(existing, true, nil)
            return
        }

        // display: false so NSDocument does not create its own window.
        super.openDocument(withContentsOf: url, display: false) { document, alreadyOpen, error in
            if let error {
                completionHandler(nil, alreadyOpen, error)
                return
            }
            guard let document = document as? MarkdownDocument else {
                completionHandler(document, alreadyOpen, error)
                return
            }
            if displayDocument {
                let window = self.takePreferredEmptyWindow()
                    ?? self.currentEmptyWindow()
                    ?? MainWindowController()
                self.attach(document, to: window)
                window.showWindow(nil)
            }
            completionHandler(document, alreadyOpen, error)
        }
    }

    func openMarkdown(at url: URL, in window: MainWindowController? = nil) {
        if let window, window.document == nil {
            preferredAttachWindow = window
        }
        openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error {
                self?.presentError(error)
            }
        }
    }

    func attach(_ document: MarkdownDocument, to window: MainWindowController) {
        if window.document === document { return }
        document.addWindowController(window)
        window.showEditor(for: document)
    }

    @discardableResult
    func detachDocument(from window: MainWindowController) -> MarkdownDocument? {
        guard let document = window.markdownDocument else { return nil }
        document.removeWindowController(window)
        document.close()
        window.showEmptyState()
        return document
    }

    private func takePreferredEmptyWindow() -> MainWindowController? {
        let preferred = preferredAttachWindow
        preferredAttachWindow = nil
        guard let preferred, preferred.document == nil else { return nil }
        return preferred
    }

    func currentEmptyWindow() -> MainWindowController? {
        if let key = NSApp.keyWindow?.windowController as? MainWindowController, key.document == nil {
            return key
        }
        if let main = NSApp.mainWindow?.windowController as? MainWindowController, main.document == nil {
            return main
        }
        return MainWindowController.all.first { $0.document == nil }
    }

    // ⌘N is always a new empty window.
    override func newDocument(_ sender: Any?) {
        MainWindowController.showEmpty()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(newDocument(_:)) || item.action == #selector(openDocument(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    private static var openPanelContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(markdownType) {
            types.insert(markdown, at: 0)
        }
        for ext in markdownExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
