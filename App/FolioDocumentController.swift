import AppKit

final class FolioDocumentController: NSDocumentController {
    // No document type is registered, so the default New path would error.
    override func newDocument(_ sender: Any?) {
        MainWindowController.showEmpty()
    }

    @objc func openWorkspace(_ sender: Any?) {}
}
