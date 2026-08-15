import AppKit

final class FolioDocumentController: NSDocumentController {
    // No document type is registered, so the default New path would error.
    override func newDocument(_ sender: Any?) {
        MainWindowController.showEmpty()
    }

    // Super uses defaultType (nil without CFBundleDocumentTypes) and greys out New.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(newDocument(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
