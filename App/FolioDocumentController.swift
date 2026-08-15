import AppKit

final class FolioDocumentController: NSDocumentController {
    override var defaultType: String? { "net.daringfireball.markdown" }

    override func documentClass(forType typeName: String) -> AnyClass? {
        MarkdownDocument.self
    }

    // ⌘N is an empty window until untitled attach exists.
    override func newDocument(_ sender: Any?) {
        MainWindowController.showEmpty()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(newDocument(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
