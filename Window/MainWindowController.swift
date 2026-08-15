import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    // NSWindow does not retain its window controller.
    private static var openControllers: [MainWindowController] = []

    private(set) var sourceTextView: NSTextView?
    private var editorScrollView: NSScrollView?

    static var all: [MainWindowController] { openControllers }

    static func showEmpty() {
        let controller = MainWindowController()
        controller.showWindow(nil)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.title = "Folio"
        window.minSize = NSSize(width: 480, height: 320)
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "app.folio.main"
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("app.folio.main")
        window.delegate = self
        window.center()
        showEmptyState()
        Self.openControllers.append(self)
    }

    var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    func showEmptyState() {
        unbindSourceView()
        window?.contentView = EmptyStateView(frame: window?.contentView?.bounds ?? .zero)
        window?.representedURL = nil
        window?.title = "Folio"
        sourceTextView = nil
        editorScrollView = nil
    }

    func showEditor(for document: MarkdownDocument) {
        if editorScrollView == nil {
            installEditor()
        }
        bindSourceView(to: document)
        window?.representedURL = document.fileURL
        window?.title = document.displayName
        window?.makeFirstResponder(sourceTextView)
    }

    func windowWillClose(_ notification: Notification) {
        unbindSourceView()
        Self.openControllers.removeAll { $0 === self }
    }

    private func installEditor() {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        sourceTextView = textView
        editorScrollView = scrollView
        window?.contentView = scrollView
    }

    private func bindSourceView(to document: MarkdownDocument) {
        guard let textView = sourceTextView,
              let content = textView.textLayoutManager?.textContentManager as? NSTextContentStorage
        else { return }
        content.textStorage = document.textStorage
        document.attachedSourceView = textView
    }

    private func unbindSourceView() {
        guard let textView = sourceTextView,
              let content = textView.textLayoutManager?.textContentManager as? NSTextContentStorage
        else { return }
        content.textStorage = NSTextStorage()
        if let document = markdownDocument, document.attachedSourceView === textView {
            document.attachedSourceView = nil
        }
    }
}
