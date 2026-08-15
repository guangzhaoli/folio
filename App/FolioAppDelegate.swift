import AppKit

@main
final class FolioAppDelegate: NSObject, NSApplicationDelegate {
    // First instance becomes NSDocumentController.shared; must exist before AppKit creates the default.
    private static let documentController = FolioDocumentController()
    private let updateChecker: UpdateChecking = NoOpUpdateChecker()

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = Self.documentController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "defaultViewMode": "split",
            "readingFontSize": 17.0,
            "showSidebarWhenOpeningFolder": true,
            "appearance": "followSystem",
        ])
        updateChecker.start()
        if NSApp.windows.isEmpty {
            MainWindowController.showEmpty()
        }
    }

    // Empty launch is an empty-state window, not Untitled.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // Drops must not crash before document types exist.
    func application(_ application: NSApplication, open urls: [URL]) {}
}
