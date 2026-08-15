import AppKit

final class FolioDocumentController: NSDocumentController {
    override var defaultType: String? { "net.daringfireball.markdown" }

    override func documentClass(forType typeName: String) -> AnyClass? {
        MarkdownDocument.self
    }

    // New is still an empty window; untitled attach lands in PR-02b.
    override func newDocument(_ sender: Any?) {
        MainWindowController.showEmpty()
    }

    // New still opens an empty window rather than Untitled.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(newDocument(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
