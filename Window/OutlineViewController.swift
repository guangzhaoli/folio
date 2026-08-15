import AppKit

private final class OutlineDragRecognizer: NSPanGestureRecognizer {
    private(set) var mouseDownTime: TimeInterval = 0

    override func mouseDown(with event: NSEvent) {
        mouseDownTime = event.timestamp
        super.mouseDown(with: event)
    }

    var holdDuration: TimeInterval {
        (NSApp.currentEvent?.timestamp ?? mouseDownTime) - mouseDownTime
    }
}

final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSGestureRecognizerDelegate {
    var items: [OutlineItem] = [] {
        didSet { reload() }
    }
    var showsBreadcrumb = false {
        didSet { applyMode() }
    }
    var onSelect: ((OutlineItem) -> Void)?
    var onDockDrag: ((NSGestureRecognizer.State, NSPoint) -> Void)?
    var onChoosePlacement: ((OutlinePlacement) -> Void)?

    private let tableView = NSTableView()
    private let tableScroll = NSScrollView()
    private let crumbScroll = NSScrollView()
    private let crumbStack = NSStackView()
    private var emptyLabel: NSTextField?
    private var crumbs: [OutlineItem] = []
    private var focusedLine = 1
    private var dockDragging = false
    private var suppressClick = false

    override func loadView() {
        let empty = NSTextField(labelWithString: "No headings")
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .tertiaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel = empty

        tableScroll.drawsBackground = false
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 24
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clicked)
        tableScroll.documentView = tableView

        crumbStack.orientation = .horizontal
        crumbStack.alignment = .centerY
        crumbStack.spacing = 2
        crumbStack.translatesAutoresizingMaskIntoConstraints = false
        crumbScroll.drawsBackground = false
        crumbScroll.hasHorizontalScroller = true
        crumbScroll.hasVerticalScroller = false
        crumbScroll.autohidesScrollers = true
        crumbScroll.borderType = .noBorder
        crumbScroll.translatesAutoresizingMaskIntoConstraints = false
        crumbScroll.documentView = crumbStack
        NSLayoutConstraint.activate([
            crumbStack.leadingAnchor.constraint(equalTo: crumbScroll.contentView.leadingAnchor, constant: 8),
            crumbStack.topAnchor.constraint(equalTo: crumbScroll.contentView.topAnchor),
            crumbStack.bottomAnchor.constraint(equalTo: crumbScroll.contentView.bottomAnchor),
            crumbStack.heightAnchor.constraint(equalTo: crumbScroll.contentView.heightAnchor),
        ])

        let wrap = NSView()
        wrap.addSubview(tableScroll)
        wrap.addSubview(crumbScroll)
        wrap.addSubview(empty)
        wrap.menu = makePlacementMenu()
        NSLayoutConstraint.activate([
            tableScroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            crumbScroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            crumbScroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            crumbScroll.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor),
            crumbScroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            empty.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            empty.centerYAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.centerYAnchor),
        ])
        let drag = OutlineDragRecognizer(target: self, action: #selector(treeDragged(_:)))
        drag.delegate = self
        drag.delaysPrimaryMouseButtonEvents = false
        wrap.addGestureRecognizer(drag)
        view = wrap
        applyMode()
        reload()
    }

    func focus(sourceLine: Int) {
        focusedLine = sourceLine
        let next = OutlineItem.path(in: items, throughLine: sourceLine)
        if next.map(\.id) != crumbs.map(\.id) {
            crumbs = next
            rebuildCrumbs()
        }
        highlightCurrentRow()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("heading")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            let wrap = NSTableCellView()
            wrap.identifier = id
            wrap.addSubview(text)
            wrap.textField = text
            text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -8),
                text.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            ])
            return wrap
        }()
        let item = items[row]
        let pad = String(repeating: "  ", count: max(0, item.level - 1))
        cell.textField?.stringValue = pad + item.title
        let current = crumbs.last
        let isCurrent = current?.id == item.id
        cell.textField?.font = isCurrent || item.level <= 1
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12)
        cell.textField?.textColor = isCurrent
            ? .controlAccentColor
            : (item.level <= 2 ? .labelColor : .secondaryLabelColor)
        return cell
    }

    @objc private func clicked() {
        if suppressClick {
            suppressClick = false
            return
        }
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        onSelect?(items[row])
    }

    @objc private func crumbClicked(_ sender: NSButton) {
        guard crumbs.indices.contains(sender.tag) else { return }
        let current = crumbs[sender.tag]
        let siblings = OutlineItem.siblings(of: current, in: items)
        let menu = NSMenu()
        for (index, sibling) in siblings.enumerated() {
            let item = NSMenuItem(title: sibling.title, action: #selector(pickSibling(_:)), keyEquivalent: "")
            item.target = self
            item.tag = items.firstIndex(where: { $0.id == sibling.id }) ?? index
            item.state = sibling.id == current.id ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func pickSibling(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag])
    }

    @objc private func treeDragged(_ gesture: OutlineDragRecognizer) {
        let point = gesture.location(in: view.window?.contentView)
        let translation = gesture.translation(in: view)
        let distance = hypot(translation.x, translation.y)
        switch gesture.state {
        case .began, .changed:
            if !dockDragging {
                let held = gesture.holdDuration >= 0.16
                let sideways = abs(translation.x) >= abs(translation.y)
                guard distance > 8, held || sideways || showsBreadcrumb else { return }
                dockDragging = true
                suppressClick = true
                onDockDrag?(.began, point)
            }
            if dockDragging { onDockDrag?(.changed, point) }
        case .ended, .cancelled:
            if dockDragging { onDockDrag?(gesture.state, point) }
            dockDragging = false
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func placeBelow() { onChoosePlacement?(.belowLibrary) }
    @objc private func placeTop() { onChoosePlacement?(.top) }
    @objc private func placeTrailing() { onChoosePlacement?(.trailing) }

    private func applyMode() {
        tableScroll.isHidden = showsBreadcrumb
        crumbScroll.isHidden = !showsBreadcrumb
        rebuildCrumbs()
    }

    private func reload() {
        emptyLabel?.isHidden = !items.isEmpty
        crumbs = OutlineItem.path(in: items, throughLine: focusedLine)
        tableView.reloadData()
        rebuildCrumbs()
        highlightCurrentRow()
    }

    private func highlightCurrentRow() {
        guard !showsBreadcrumb, let current = crumbs.last,
              let row = items.firstIndex(where: { $0.id == current.id })
        else { return }
        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.reloadData()
        }
        let visible = tableView.rows(in: tableView.visibleRect)
        if !NSLocationInRange(row, visible) {
            tableView.scrollRowToVisible(row)
        }
    }

    private func rebuildCrumbs() {
        crumbStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard showsBreadcrumb else { return }
        if crumbs.isEmpty {
            emptyLabel?.isHidden = items.isEmpty
            return
        }
        emptyLabel?.isHidden = true
        for (index, crumb) in crumbs.enumerated() {
            if index > 0 {
                let sep = NSTextField(labelWithString: "›")
                sep.font = .systemFont(ofSize: 12, weight: .medium)
                sep.textColor = .tertiaryLabelColor
                sep.setContentHuggingPriority(.required, for: .horizontal)
                crumbStack.addArrangedSubview(sep)
            }
            let button = NSButton(title: crumb.title, target: self, action: #selector(crumbClicked(_:)))
            button.isBordered = false
            button.tag = index
            button.lineBreakMode = .byTruncatingTail
            button.font = index == crumbs.count - 1
                ? .systemFont(ofSize: 12, weight: .semibold)
                : .systemFont(ofSize: 12)
            button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
            button.imagePosition = .imageRight
            button.symbolConfiguration = .init(pointSize: 8, weight: .semibold)
            button.contentTintColor = index == crumbs.count - 1 ? .labelColor : .secondaryLabelColor
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            crumbStack.addArrangedSubview(button)
        }
    }

    private func makePlacementMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Below Library", action: #selector(placeBelow), keyEquivalent: "")
        menu.addItem(withTitle: "Top", action: #selector(placeTop), keyEquivalent: "")
        menu.addItem(withTitle: "Right", action: #selector(placeTrailing), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }
}