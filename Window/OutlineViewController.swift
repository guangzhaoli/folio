import AppKit

final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
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
    private var dockDragging = false

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
            crumbStack.leadingAnchor.constraint(equalTo: crumbScroll.contentView.leadingAnchor, constant: 22),
            crumbStack.topAnchor.constraint(equalTo: crumbScroll.contentView.topAnchor),
            crumbStack.bottomAnchor.constraint(equalTo: crumbScroll.contentView.bottomAnchor),
            crumbStack.heightAnchor.constraint(equalTo: crumbScroll.contentView.heightAnchor),
        ])

        let handle = NSView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        let grip = NSImageView()
        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Move outline")
        grip.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        grip.contentTintColor = .tertiaryLabelColor
        grip.translatesAutoresizingMaskIntoConstraints = false
        handle.addSubview(grip)

        let wrap = NSView()
        wrap.addSubview(tableScroll)
        wrap.addSubview(crumbScroll)
        wrap.addSubview(empty)
        wrap.addSubview(handle)
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
            empty.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 22),
            empty.centerYAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.centerYAnchor),
            handle.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            handle.centerYAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 20),
            handle.heightAnchor.constraint(equalToConstant: 20),
            grip.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
            grip.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 14),
            grip.heightAnchor.constraint(equalToConstant: 14),
        ])
        handle.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(headerPanned(_:))))
        view = wrap
        applyMode()
        reload()
    }

    func focus(sourceLine: Int) {
        let next = OutlineItem.path(in: items, throughLine: sourceLine)
        guard next.map(\.id) != crumbs.map(\.id) else { return }
        crumbs = next
        rebuildCrumbs()
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
        cell.textField?.font = item.level <= 1
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12)
        cell.textField?.textColor = item.level <= 2 ? .labelColor : .secondaryLabelColor
        return cell
    }

    @objc private func clicked() {
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

    @objc private func headerPanned(_ gesture: NSPanGestureRecognizer) {
        let point = gesture.location(in: view.window?.contentView)
        switch gesture.state {
        case .changed:
            if !dockDragging, hypot(gesture.translation(in: view).x, gesture.translation(in: view).y) > 6 {
                dockDragging = true
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
        tableView.reloadData()
        if showsBreadcrumb {
            if crumbs.isEmpty, let first = items.first {
                crumbs = [first]
            } else {
                crumbs = OutlineItem.path(
                    in: items,
                    throughLine: crumbs.last?.span.startLine ?? items.last?.span.startLine ?? 1
                )
            }
        }
        rebuildCrumbs()
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