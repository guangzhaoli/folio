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
        if typeName == "public.folder" || typeName == "public.directory" {
            return nil
        }
        return MarkdownDocument.self
    }

    /// LS often tags `.md` as public.plain-text; keep those files on MarkdownDocument.
    override func typeForContents(of url: URL) throws -> String {
        if Self.isDirectory(url) {
            return "public.folder"
        }
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
        if Self.isDirectory(url) {
            let host = preferredAttachWindow ?? currentWindow()
            openWorkspace(at: url, in: host)
            completionHandler(nil, false, nil)
            return
        }
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

    @objc func openWorkspace(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of Markdown files"
        let host = currentWindow()
        preferredAttachWindow = host
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.preferredAttachWindow = nil
                return
            }
            self.openWorkspace(at: url, in: host)
        }
        if let window = host?.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    func openWorkspace(at url: URL, in window: MainWindowController?) {
        let root = url.standardizedFileURL
        let host = window ?? currentWindow() ?? MainWindowController()
        if host.workspace?.rootURL != root {
            host.bindWorkspace(Workspace(root: root))
        } else {
            host.revealLibrary()
        }
        host.showWindow(nil)
        if host.markdownDocument == nil, let first = host.workspace?.firstMarkdown() {
            openMarkdown(at: first, in: host)
        }
    }

    @objc func openEnclosingFolder(_ sender: Any?) {
        guard let window = currentWindow(),
              let file = window.markdownDocument?.fileURL
        else { return }
        openWorkspace(at: file.deletingLastPathComponent(), in: window)
    }

    func openInNewWindow(_ url: URL, workspaceRoot: URL?) {
        let target = url.standardizedFileURL
        if let existing = document(for: target) as? MarkdownDocument {
            existing.windowControllers.first?.showWindow(nil)
            return
        }
        let window = MainWindowController()
        if let workspaceRoot {
            window.bindWorkspace(Workspace(root: workspaceRoot))
        }
        openMarkdown(at: target, in: window)
    }

    func replaceDocument(in window: MainWindowController, with url: URL) {
        let target = url.standardizedFileURL
        if window.markdownDocument?.fileURL?.standardizedFileURL == target {
            return
        }
        if let existing = document(for: target) as? MarkdownDocument {
            existing.windowControllers.first?.showWindow(nil)
            return
        }
        if window.sourceTextView?.hasMarkedText() == true {
            return
        }

        let proceed = { [weak self] in
            guard let self else { return }
            self.detachDocument(from: window, resetChrome: false)
            self.preferredAttachWindow = window
            self.openMarkdown(at: target, in: window)
        }

        guard let current = window.markdownDocument, current.isDocumentEdited else {
            proceed()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(current.displayName)”?"
        alert.informativeText = "Your edits will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        guard let sheetWindow = window.window else { return }
        alert.beginSheetModal(for: sheetWindow) { response in
            switch response {
            case .alertFirstButtonReturn:
                guard let fileURL = current.fileURL else { return }
                current.save(
                    to: fileURL,
                    ofType: current.fileType ?? FolioDocumentController.markdownType,
                    for: .saveOperation
                ) { error in
                    if error == nil { proceed() }
                }
            case .alertSecondButtonReturn:
                proceed()
            default:
                break
            }
        }
    }

    func attach(_ document: MarkdownDocument, to window: MainWindowController) {
        if window.document === document { return }
        document.addWindowController(window)
        window.showEditor(for: document)
    }

    @discardableResult
    func detachDocument(from window: MainWindowController, resetChrome: Bool = true) -> MarkdownDocument? {
        guard let document = window.markdownDocument else { return nil }
        window.prepareForDocumentSwap()
        document.removeWindowController(window)
        document.close()
        if resetChrome {
            if window.workspace == nil {
                window.showEmptyState()
            } else {
                window.showLibraryPlaceholder()
            }
        }
        return document
    }

    private func takePreferredEmptyWindow() -> MainWindowController? {
        let preferred = preferredAttachWindow
        preferredAttachWindow = nil
        guard let preferred, preferred.document == nil else { return nil }
        return preferred
    }

    func currentEmptyWindow() -> MainWindowController? {
        if let key = currentWindow(), key.document == nil { return key }
        return MainWindowController.all.first { $0.document == nil }
    }

    func currentWindow() -> MainWindowController? {
        if let key = NSApp.keyWindow?.windowController as? MainWindowController { return key }
        if let main = NSApp.mainWindow?.windowController as? MainWindowController { return main }
        return MainWindowController.all.first
    }

    static func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    // ⌘N is always a new empty window.
    override func newDocument(_ sender: Any?) {
        MainWindowController.showEmpty()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(newDocument(_:)), #selector(openDocument(_:)), #selector(openWorkspace(_:)):
            return true
        case #selector(openEnclosingFolder(_:)):
            return (NSApp.keyWindow?.windowController as? MainWindowController)?.markdownDocument?.fileURL != nil
        default:
            return super.validateUserInterfaceItem(item)
        }
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
