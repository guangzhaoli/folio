import AppKit
import UniformTypeIdentifiers

final class FolioDocumentController: NSDocumentController {
    static let markdownType = "net.daringfireball.markdown"
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdwn"]

    static var folio: FolioDocumentController {
        shared as! FolioDocumentController
    }

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
    // A Debug Folio is usually not the default .md handler, so the panel
    // hands the file to Typora / VS Code / TextEdit instead.
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = Self.openPanelContentTypes
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.openMarkdown(at: url)
            }
        }
    }

    func openMarkdown(at url: URL) {
        openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error {
                self?.presentError(error)
            }
        }
    }

    // ⌘N is an empty window until untitled attach exists.
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
