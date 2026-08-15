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
    private var sidebarItem: NSSplitViewItem?
    private var inspectorItem: NSSplitViewItem?
    private let fileSidebar = SidebarViewController()
    private let outlineController = OutlineViewController()
    private var libraryHost: NSViewController?
    private var editorHost: NSViewController?
    private var trailingHost: NSViewController?
    private var librarySplit: NSSplitView?
    private var belowDock: NSView?
    private var topDock: NSView?
    private var topDockHeight: NSLayoutConstraint?
    private var belowDockHeight: NSLayoutConstraint?
    private var dropOverlay: OutlineDropOverlay?
    private var outlinePlacement = OutlinePlacement.stored
    private var outlineVisible = OutlinePlacement.isVisible
    private var measureWork: DispatchWorkItem?
    private(set) var workspace: Workspace?
    private var placeholderView: NSView?
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
        prepareForDocumentSwap()
        detachOutline()
        if fileSidebar.parent != nil {
            fileSidebar.view.removeFromSuperview()
            fileSidebar.removeFromParent()
        }
        dropOverlay?.removeFromSuperview()
        dropOverlay = nil
        workspace = nil
        rootSplit = nil
        sidebarItem = nil
        inspectorItem = nil
        editorSplit = nil
        libraryHost = nil
        editorHost = nil
        trailingHost = nil
        librarySplit = nil
        belowDock = nil
        topDock = nil
        topDockHeight = nil
        belowDockHeight = nil
        placeholderView = nil
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

    func bindWorkspace(_ workspace: Workspace) {
        self.workspace = workspace
        if rootSplit == nil {
            installChrome()
        }
        fileSidebar.workspace = workspace
        fileSidebar.selectedURL = markdownDocument?.fileURL
        revealLibrary()
        if markdownDocument == nil {
            showLibraryPlaceholder()
        } else {
            setEditorVisible(true)
            window?.title = markdownDocument?.displayName ?? workspace.rootURL.lastPathComponent
        }
    }

    func revealLibrary() {
        sidebarItem?.isCollapsed = workspace == nil
        fileSidebar.setLibraryTitle(workspace?.rootURL.lastPathComponent ?? "Library")
    }

    func showLibraryPlaceholder() {
        prepareForDocumentSwap()
        setEditorVisible(false)
        fileSidebar.selectedURL = nil
        let empty = workspace?.containsMarkdown() != true
        (placeholderView as? NSTextField)?.stringValue = empty
            ? "No Markdown files in this folder"
            : "Select a Markdown file in the sidebar"
        window?.representedURL = nil
        window?.title = workspace?.rootURL.lastPathComponent ?? "Folio"
        window?.subtitle = "Library"
    }

    func prepareForDocumentSwap() {
        markdownDocument?.onSnapshot = nil
        unbindSourceView()
    }

    func showEditor(for document: MarkdownDocument) {
        if rootSplit == nil {
            installChrome()
        }
        setEditorVisible(true)
        bindSourceView(to: document)
        document.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot: snapshot)
        }
        document.scheduleParse()
        applyViewMode()
        fileSidebar.selectedURL = document.fileURL
        window?.representedURL = document.fileURL
        window?.title = document.displayName
        refreshEditorLayout()
        window?.makeFirstResponder(sourceTextView)
        DispatchQueue.main.async { [weak self] in
            self?.refreshEditorLayout()
            self?.refreshSourceDisplay()
        }
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
            menuItem.title = outlineVisible ? "Hide Outline" : "Show Outline"
            return markdownDocument != nil
        case #selector(placeOutlineBelow(_:)):
            menuItem.state = outlinePlacement == .belowLibrary ? .on : .off
            return markdownDocument != nil
        case #selector(placeOutlineTop(_:)):
            menuItem.state = outlinePlacement == .top ? .on : .off
            return markdownDocument != nil
        case #selector(placeOutlineTrailing(_:)):
            menuItem.state = outlinePlacement == .trailing ? .on : .off
            return markdownDocument != nil
        case #selector(nextFile(_:)), #selector(previousFile(_:)):
            return workspace != nil && markdownDocument?.fileURL != nil
        case #selector(closeFile(_:)):
            return workspace != nil && markdownDocument != nil
        default:
            return true
        }
    }

    @objc func showSource(_ sender: Any?) { setViewMode(.source) }
    @objc func showSplit(_ sender: Any?) { setViewMode(.split) }
    @objc func showReading(_ sender: Any?) { setViewMode(.reading) }

    @objc func toggleOutline(_ sender: Any?) {
        outlineVisible.toggle()
        OutlinePlacement.persistVisible(outlineVisible)
        applyOutlinePlacement()
    }

    @objc func placeOutlineBelow(_ sender: Any?) { setOutlinePlacement(.belowLibrary) }
    @objc func placeOutlineTop(_ sender: Any?) { setOutlinePlacement(.top) }
    @objc func placeOutlineTrailing(_ sender: Any?) { setOutlinePlacement(.trailing) }

    @objc func nextFile(_ sender: Any?) {
        guard let current = markdownDocument?.fileURL,
              let next = workspace?.nextMarkdown(after: current)
        else { return }
        FolioDocumentController.folio.replaceDocument(in: self, with: next)
    }

    @objc func previousFile(_ sender: Any?) {
        guard let current = markdownDocument?.fileURL,
              let previous = workspace?.previousMarkdown(before: current)
        else { return }
        FolioDocumentController.folio.replaceDocument(in: self, with: previous)
    }

    @objc func closeFile(_ sender: Any?) {
        FolioDocumentController.folio.detachDocument(from: self, resetChrome: true)
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
        [.toggleSidebar, .flexibleSpace, .init("folio.viewMode"), .flexibleSpace, .init("folio.outline")]
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
        if itemIdentifier.rawValue == "folio.outline" {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Outline")
            item.label = "Outline"
            item.paletteLabel = "Outline"
            item.toolTip = "Show or hide the page outline"
            item.target = self
            item.action = #selector(toggleOutline(_:))
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
        fileSidebar.onOpenFile = { [weak self] url in
            guard let self else { return }
            FolioDocumentController.folio.replaceDocument(in: self, with: url)
        }
        fileSidebar.onOpenInNewWindow = { [weak self] url in
            FolioDocumentController.folio.openInNewWindow(url, workspaceRoot: self?.workspace?.rootURL)
        }
        outlineController.onSelect = { [weak self] item in
            self?.jump(to: item)
        }
        outlineController.onDockDrag = { [weak self] state, point in
            self?.handleOutlineDockDrag(state, at: point)
        }
        outlineController.onChoosePlacement = { [weak self] placement in
            self?.setOutlinePlacement(placement)
        }

        let below = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
        belowDock = below
        let librarySplitView = NSSplitView()
        librarySplitView.isVertical = false
        librarySplitView.dividerStyle = .thin
        fileSidebar.view.frame = NSRect(x: 0, y: 0, width: 240, height: 480)
        librarySplitView.addArrangedSubview(fileSidebar.view)
        librarySplitView.addArrangedSubview(below)
        let belowHeight = below.heightAnchor.constraint(equalToConstant: 180)
        belowHeight.priority = .defaultHigh
        belowHeight.isActive = true
        belowDockHeight = belowHeight
        librarySplit = librarySplitView

        let library = NSViewController()
        library.addChild(fileSidebar)
        library.view = librarySplitView
        libraryHost = library

        let sidebar = NSSplitViewItem(sidebarWithViewController: library)
        sidebar.minimumThickness = 200
        sidebar.maximumThickness = 320
        sidebar.canCollapse = true
        sidebar.isCollapsed = workspace == nil && outlinePlacement != .belowLibrary
        sidebarItem = sidebar

        let host = NSViewController()
        let container = NSView()
        host.view = container
        editorHost = host

        let top = NSView()
        top.translatesAutoresizingMaskIntoConstraints = false
        topDock = top
        container.addSubview(top)
        let topHeight = top.heightAnchor.constraint(equalToConstant: 0)
        topDockHeight = topHeight

        let placeholder = NSTextField(labelWithString: "Select a Markdown file in the sidebar")
        placeholder.font = .systemFont(ofSize: 15)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(placeholder)
        placeholderView = placeholder

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.translatesAutoresizingMaskIntoConstraints = false
        editorSplit = split
        container.addSubview(split)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            top.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            topHeight,
            placeholder.centerXAnchor.constraint(equalTo: container.safeAreaLayoutGuide.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: container.safeAreaLayoutGuide.centerYAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.topAnchor.constraint(equalTo: top.bottomAnchor),
            split.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let sourceScroll = makeSourceScroll()
        let readingScroll = makeReadingScroll()
        sourceColumn = wrapColumn(sourceScroll)
        readingColumn = wrapColumn(readingScroll)
        split.addArrangedSubview(sourceColumn!)
        split.addArrangedSubview(readingColumn!)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        let editorItem = NSSplitViewItem(viewController: host)
        editorItem.minimumThickness = 360

        let trailing = NSViewController()
        trailing.view = NSView()
        trailingHost = trailing
        let inspector = NSSplitViewItem(inspectorWithViewController: trailing)
        inspector.minimumThickness = 168
        inspector.maximumThickness = 260
        inspector.canCollapse = true
        inspector.isCollapsed = true
        inspectorItem = inspector

        let splitController = NSSplitViewController()
        splitController.splitViewItems = [sidebar, editorItem, inspector]
        rootSplit = splitController
        window?.contentView = nil
        window?.contentViewController = splitController
        applyViewMode()
        setEditorVisible(markdownDocument != nil)
        applyOutlinePlacement()
    }

    private func setEditorVisible(_ visible: Bool) {
        editorSplit?.isHidden = !visible
        placeholderView?.isHidden = visible
        applyOutlinePlacement()
        if visible {
            refreshEditorLayout()
        }
    }

    private func setOutlinePlacement(_ placement: OutlinePlacement) {
        outlinePlacement = placement
        outlineVisible = true
        placement.persist()
        OutlinePlacement.persistVisible(true)
        applyOutlinePlacement()
        DispatchQueue.main.async { [weak self] in
            self?.refreshEditorLayout()
            self?.apply(snapshot: self?.snapshot ?? .empty)
        }
    }

    private func applyOutlinePlacement() {
        let show = outlineVisible && markdownDocument != nil
        detachOutline()
        belowDock?.isHidden = true
        topDock?.isHidden = true
        topDockHeight?.constant = 0
        belowDockHeight?.constant = 0
        inspectorItem?.isCollapsed = true
        sidebarItem?.isCollapsed = workspace == nil && !(show && outlinePlacement == .belowLibrary)

        guard show else { return }
        switch outlinePlacement {
        case .belowLibrary:
            guard let belowDock, let libraryHost else { return }
            belowDock.isHidden = false
            belowDockHeight?.constant = 200
            outlineController.showsHorizontalTree = false
            embed(outlineController, in: belowDock, parent: libraryHost)
            sidebarItem?.isCollapsed = false
        case .top:
            guard let topDock, let editorHost else { return }
            topDock.isHidden = false
            topDockHeight?.constant = 168
            outlineController.showsHorizontalTree = true
            embed(outlineController, in: topDock, parent: editorHost)
        case .trailing:
            guard let host = trailingHost else { return }
            inspectorItem?.isCollapsed = false
            outlineController.showsHorizontalTree = false
            embed(outlineController, in: host.view, parent: host)
        }
        librarySplit?.adjustSubviews()
    }

    private func embed(_ child: NSViewController, in host: NSView, parent: NSViewController) {
        if child.parent != nil {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        parent.addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: host.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }

    private func detachOutline() {
        outlineController.view.removeFromSuperview()
        if outlineController.parent != nil {
            outlineController.removeFromParent()
        }
    }

    private func handleOutlineDockDrag(_ state: NSGestureRecognizer.State, at point: NSPoint) {
        switch state {
        case .began:
            showDropOverlay()
            dropOverlay?.highlighted = dropOverlay?.placement(at: point)
        case .changed:
            dropOverlay?.highlighted = dropOverlay?.placement(at: point)
        case .ended:
            if let placement = dropOverlay?.placement(at: point) {
                setOutlinePlacement(placement)
            }
            hideDropOverlay()
        default:
            hideDropOverlay()
        }
    }

    private func showDropOverlay() {
        guard let content = window?.contentView else { return }
        let overlay = dropOverlay ?? OutlineDropOverlay(frame: content.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.frame = content.bounds
        overlay.zones = dockZones()
        overlay.highlighted = nil
        if overlay.superview == nil {
            content.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        dropOverlay = overlay
    }

    private func hideDropOverlay() {
        dropOverlay?.removeFromSuperview()
        dropOverlay = nil
    }

    private func dockZones() -> [OutlinePlacement: NSRect] {
        guard let content = window?.contentView else { return [:] }
        let bounds = content.bounds
        let safe = content.safeAreaInsets
        let sidebarWidth: CGFloat
        if sidebarItem?.isCollapsed == false {
            sidebarWidth = sidebarItem?.viewController.view.bounds.width ?? 220
        } else {
            sidebarWidth = 220
        }
        let usableHeight = max(120, bounds.height - safe.top - safe.bottom)
        return [
            .top: NSRect(
                x: sidebarWidth + 8,
                y: bounds.height - safe.top - 184,
                width: max(160, bounds.width - sidebarWidth - 16),
                height: 168
            ),
            .trailing: NSRect(
                x: bounds.width - 208,
                y: safe.bottom + 10,
                width: 196,
                height: usableHeight - 20
            ),
            .belowLibrary: NSRect(
                x: 10,
                y: 10,
                width: max(180, sidebarWidth - 20),
                height: min(220, usableHeight * 0.42)
            ),
        ]
    }

    private func wrapColumn(_ scroll: NSScrollView) -> NSView {
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        scroll.translatesAutoresizingMaskIntoConstraints = true
        scroll.autoresizingMask = [.width, .height]
        scroll.frame = box.bounds
        box.addSubview(scroll)
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
        textView.onMeasureChange = { [weak self] _ in
            guard let self else { return }
            self.measureWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.apply(snapshot: self.snapshot)
            }
            self.measureWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
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
        refreshEditorLayout()
        if markdownDocument == nil, workspace != nil {
            window?.subtitle = "Library"
        } else {
            window?.subtitle = viewMode == .reading ? "Reading" : (viewMode == .source ? "Source" : "Split")
        }
    }

    private func apply(snapshot: ParseSnapshot) {
        self.snapshot = snapshot
        outlineController.items = snapshot.outline
        var style = ReaderStyle.default
        let paneWidth = readingTextView?.bounds.width ?? 0
        if paneWidth >= 120 {
            style.measure = ReadingTextView.usableWidth(in: paneWidth)
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
        refreshSourceDisplay()
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

    private func refreshEditorLayout() {
        window?.contentView?.layoutSubtreeIfNeeded()
        guard let split = editorSplit else { return }
        split.adjustSubviews()
        if viewMode == .split, split.subviews.count == 2, split.bounds.width > 8 {
            let left = split.subviews[0].isHidden ? 0 : split.subviews[0].bounds.width
            if left < 24 || left > split.bounds.width - 24 {
                split.setPosition(split.bounds.width * 0.42, ofDividerAt: 0)
            }
        }
        sourceColumn?.needsLayout = true
        readingColumn?.needsLayout = true
        sourceTextView?.needsDisplay = true
        readingTextView?.needsDisplay = true
        readingTextView?.needsLayout = true
    }

    private func refreshSourceDisplay() {
        guard let textView = sourceTextView else { return }
        textView.needsLayout = true
        textView.needsDisplay = true
        if let layout = textView.textLayoutManager {
            layout.ensureLayout(for: layout.documentRange)
            layout.textViewportLayoutController.layoutViewport()
        }
        if let scroll = editorScrollView {
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.tile()
        }
    }
}
