import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    // NSWindow does not retain its window controller.
    private static var openControllers: [MainWindowController] = []

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
        window.contentView = EmptyStateView(frame: window.contentView?.bounds ?? .zero)
        window.delegate = self
        window.center()
        Self.openControllers.append(self)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }
}
