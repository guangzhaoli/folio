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
            "folio.viewMode": ViewMode.split.rawValue,
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

    func application(_ sender: NSApplication, open urls: [URL]) {
        open(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open([URL(fileURLWithPath: filename)])
        return true
    }

    private func open(_ urls: [URL]) {
        let host = FolioDocumentController.folio.currentWindow()
        for url in urls {
            if FolioDocumentController.isDirectory(url) {
                FolioDocumentController.folio.openWorkspace(at: url, in: host)
            } else {
                FolioDocumentController.folio.openMarkdown(at: url, in: host)
            }
        }
    }
}
