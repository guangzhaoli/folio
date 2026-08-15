import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSSplitViewDelegate {
    private static var openControllers: [MainWindowController] = []

    private(set) var sourceTextView: NSTextView?
    private var editorScrollView: NSScrollView?
    private var readingTextView: ReadingTextView?
    private var readingScrollView: NSScrollView?
    private var sourceColumn: NSView?
    private var readingColumn: NSView?
    private var editorSplit: NSSplitView?
    private var rootSplit: NSSplitViewController?
    private let outlineController = OutlineViewController()
    private var viewMode: ViewMode = .stored
    private var snapshot = ParseSnapshot.empty
    private var readingRanges: [BlockID: NSRange] = [:]
    private var programmaticScroll = false

    static var all: [MainWindowController] { openControllers }

    static func showEmpty() {
        MainWindowController().showWindow(nil)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.title = "Folio"
        window.minSize = NSSize(width: 640, height: 400)
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "app.folio.main"
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("app.folio.main")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.delegate = self
        window.center()
        installToolbar()
        showEmptyState()
        Self.openControllers.append(self)
    }

    var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    func showEmptyState() {
        unbindSourceView()
        markdownDocument?.onSnapshot = nil
        rootSplit = nil
        editorSplit = nil
        sourceTextView = nil
        editorScrollView = nil
        readingTextView = nil
        readingScrollView = nil
        sourceColumn = nil
        readingColumn = nil
        window?.contentViewController = nil
        window?.contentView = EmptyStateView(frame: window?.contentView?.bounds ?? .zero)
        window?.representedURL = nil
        window?.title = "Folio"
        window?.subtitle = ""
    }

    func showEditor(for document: MarkdownDocument) {
        if rootSplit == nil {
            installChrome()
        }
        bindSourceView(to: document)
        document.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot: snapshot)
        }
        document.scheduleParse()
        applyViewMode()
        window?.representedURL = document.fileURL
        window?.title = document.displayName
        window?.makeFirstResponder(sourceTextView)
    }

    func windowWillClose(_ notification: Notification) {
        markdownDocument?.onSnapshot = nil
        unbindSourceView()
        Self.openControllers.removeAll { $0 === self }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showSource(_:)):
            menuItem.state = viewMode == .source ? .on : .off
            return markdownDocument != nil
        case #selector(showSplit(_:)):
            menuItem.state = viewMode == .split ? .on : .off
            return markdownDocument != nil
        case #selector(showReading(_:)):
            menuItem.state = viewMode == .reading ? .on : .off
            return markdownDocument != nil
        case #selector(toggleOutline(_:)):
            return markdownDocument != nil
        default:
            return true
        }
    }

    @objc func showSource(_ sender: Any?) { setViewMode(.source) }
    @objc func showSplit(_ sender: Any?) { setViewMode(.split) }
    @objc func showReading(_ sender: Any?) { setViewMode(.reading) }

    @objc func toggleOutline(_ sender: Any?) {
        guard let item = rootSplit?.splitViewItems.first else { return }
        item.animator().isCollapsed.toggle()
    }

    @objc private func viewModeToolbarChanged(_ sender: NSSegmentedControl) {
        setViewMode(ViewMode(rawValue: sender.selectedSegment) ?? .split)
    }

    private func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        mode.persist()
        applyViewMode()
        refreshToolbarSelection()
    }

    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "folio.main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, .init("folio.viewMode")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .toggleSidebar {
            return NSToolbarItem(itemIdentifier: .toggleSidebar)
        }
        if itemIdentifier.rawValue == "folio.viewMode" {
            let control = NSSegmentedControl()
            control.segmentCount = 3
            control.trackingMode = .selectOne
            control.segmentStyle = .automatic
            control.setImage(NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Source"), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Split"), forSegment: 1)
            control.setImage(NSImage(systemSymbolName: "book", accessibilityDescription: "Reading"), forSegment: 2)
            control.setToolTip("Source", forSegment: 0)
            control.setToolTip("Split", forSegment: 1)
            control.setToolTip("Reading", forSegment: 2)
            control.target = self
            control.action = #selector(viewModeToolbarChanged(_:))
            control.selectedSegment = viewMode.rawValue
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = control
            item.label = "View"
            item.paletteLabel = "View"
            return item
        }
        return nil
    }

    private func refreshToolbarSelection() {
        guard let item = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "folio.viewMode" }),
              let control = item.view as? NSSegmentedControl
        else { return }
        control.selectedSegment = viewMode.rawValue
    }

    private func installChrome() {
        let outlineItem = NSSplitViewItem(sidebarWithViewController: outlineController)
        outlineItem.minimumThickness = 168
        outlineItem.maximumThickness = 280
        outlineItem.canCollapse = true
        outlineController.onSelect = { [weak self] item in
            self?.jump(to: item)
        }

        let editorHost = NSViewController()
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        editorSplit = split

        let sourceScroll = makeSourceScroll()
        let readingScroll = makeReadingScroll()
        sourceColumn = wrapColumn(sourceScroll)
        readingColumn = wrapColumn(readingScroll)
        split.addArrangedSubview(sourceColumn!)
        split.addArrangedSubview(readingColumn!)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        editorHost.view = split
        let editorItem = NSSplitViewItem(viewController: editorHost)
        editorItem.minimumThickness = 360

        let splitController = NSSplitViewController()
        splitController.splitViewItems = [outlineItem, editorItem]
        rootSplit = splitController
        window?.contentView = nil
        window?.contentViewController = splitController
        applyViewMode()
    }

    private func wrapColumn(_ scroll: NSScrollView) -> NSView {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let box = NSView()
        box.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: box.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    private func makeSourceScroll() -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .textBackgroundColor
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        sourceTextView = textView
        editorScrollView = scroll
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sourceScrolled),
            name: NSScrollView.didLiveScrollNotification,
            object: scroll
        )
        return scroll
    }

    private func makeReadingScroll() -> NSScrollView {
        let textView = ReadingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 36, height: 28)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        readingTextView = textView
        readingScrollView = scroll
        textView.onAppearanceChange = { [weak self] in
            guard let self else { return }
            self.apply(snapshot: self.snapshot)
        }
        textView.onMeasureChange = { [weak self] width in
            guard let self else { return }
            self.readingTextView?.measure = width
            self.apply(snapshot: self.snapshot)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readingScrolled),
            name: NSScrollView.didLiveScrollNotification,
            object: scroll
        )
        return scroll
    }

    private func applyViewMode() {
        sourceColumn?.isHidden = viewMode == .reading
        readingColumn?.isHidden = viewMode == .source
        editorSplit?.adjustSubviews()
        if viewMode == .split, let split = editorSplit, split.subviews.count == 2 {
            let mid = split.bounds.width / 2
            split.setPosition(mid, ofDividerAt: 0)
        }
        window?.subtitle = viewMode == .reading ? "Reading" : (viewMode == .source ? "Source" : "Split")
    }

    private func apply(snapshot: ParseSnapshot) {
        self.snapshot = snapshot
        outlineController.items = snapshot.outline
        var style = ReaderStyle.default
        if let width = readingTextView?.bounds.width, width > 0 {
            style.measure = max(240, min(style.measure, width - 72))
        }
        let rendered = ReadingRenderer.render(
            snapshot: snapshot,
            baseDirectory: markdownDocument?.fileURL?.deletingLastPathComponent(),
            style: style
        )
        readingRanges = rendered.blockCharRanges
        if let storage = readingTextView?.textStorage {
            storage.setAttributedString(rendered.text)
        }
        if let source = sourceTextView, source.hasMarkedText() == false {
            SourceHighlighter.apply(snapshot: snapshot, to: source)
        }
    }

    private func jump(to item: OutlineItem) {
        programmaticScroll = true
        defer { programmaticScroll = false }
        if let range = item.span.utf16Range.location != NSNotFound ? item.span.utf16Range : nil {
            sourceTextView?.scrollRangeToVisible(range)
            sourceTextView?.setSelectedRange(NSRange(location: range.location, length: 0))
        }
        if let reading = readingRanges[item.id] {
            readingTextView?.scrollRangeToVisible(reading)
        }
    }

    @objc private func sourceScrolled() {
        syncScroll(fromSource: true)
    }

    @objc private func readingScrolled() {
        syncScroll(fromSource: false)
    }

    private func syncScroll(fromSource: Bool) {
        guard viewMode == .split, !programmaticScroll else { return }
        programmaticScroll = true
        defer { programmaticScroll = false }

        if fromSource {
            guard let source = sourceTextView else { return }
            let y = source.visibleRect.minY + source.visibleRect.height * 0.15
            let char = source.characterIndexForInsertion(at: NSPoint(x: source.visibleRect.midX, y: y))
            let line = snapshot.sourceMap.original.prefix(char).reduce(1) { $1 == "\n" || $1 == "\r" ? $0 + 1 : $0 }
            if let id = snapshot.sourceMap.blockID(containingSourceLine: line, in: snapshot.nodes),
               let range = readingRanges[id] {
                readingTextView?.scrollRangeToVisible(range)
            }
        } else {
            guard let reading = readingTextView else { return }
            let y = reading.visibleRect.minY + reading.visibleRect.height * 0.15
            let char = reading.characterIndexForInsertion(at: NSPoint(x: reading.visibleRect.midX, y: y))
            if let id = readingRanges.first(where: { NSLocationInRange(char, $0.value) })?.key,
               let node = findBlock(id, in: snapshot.nodes),
               node.source.utf16Range.location != NSNotFound {
                sourceTextView?.scrollRangeToVisible(node.source.utf16Range)
            }
        }
    }

    private func findBlock(_ id: BlockID, in nodes: [BlockNode]) -> BlockNode? {
        for node in nodes {
            if node.id == id { return node }
            if let child = findBlock(id, in: node.children) { return child }
        }
        return nil
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
