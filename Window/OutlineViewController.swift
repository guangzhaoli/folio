import AppKit

final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var items: [OutlineItem] = [] {
        didSet { reload() }
    }
    var showsHorizontalTree = false {
        didSet { applyMode() }
    }
    var onSelect: ((OutlineItem) -> Void)?
    var onDockDrag: ((NSGestureRecognizer.State, NSPoint) -> Void)?
    var onChoosePlacement: ((OutlinePlacement) -> Void)?

    private let tableView = NSTableView()
    private let tableScroll = NSScrollView()
    private let treeScroll = NSScrollView()
    private let treeHost = NSView()
    private var emptyLabel: NSTextField?
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

        treeScroll.drawsBackground = false
        treeScroll.hasVerticalScroller = true
        treeScroll.hasHorizontalScroller = true
        treeScroll.autohidesScrollers = true
        treeScroll.borderType = .noBorder
        treeScroll.translatesAutoresizingMaskIntoConstraints = false
        treeHost.translatesAutoresizingMaskIntoConstraints = false
        treeScroll.documentView = treeHost
        NSLayoutConstraint.activate([
            treeHost.leadingAnchor.constraint(equalTo: treeScroll.contentView.leadingAnchor),
            treeHost.topAnchor.constraint(equalTo: treeScroll.contentView.topAnchor),
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
        wrap.addSubview(treeScroll)
        wrap.addSubview(empty)
        wrap.addSubview(handle)
        wrap.menu = makePlacementMenu()
        NSLayoutConstraint.activate([
            tableScroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            treeScroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            treeScroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            treeScroll.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor),
            treeScroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            empty.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            empty.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor, constant: 10),
            handle.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            handle.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor),
            handle.widthAnchor.constraint(equalToConstant: 22),
            handle.heightAnchor.constraint(equalToConstant: 20),
            grip.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
            grip.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 14),
            grip.heightAnchor.constraint(equalToConstant: 14),
        ])
        let pan = NSPanGestureRecognizer(target: self, action: #selector(headerPanned(_:)))
        handle.addGestureRecognizer(pan)
        view = wrap
        applyMode()
        reload()
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

    @objc private func treeClicked(_ sender: NSButton) {
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
        tableScroll.isHidden = showsHorizontalTree
        treeScroll.isHidden = !showsHorizontalTree
        rebuildTree()
    }

    private func reload() {
        emptyLabel?.isHidden = !items.isEmpty
        tableView.reloadData()
        rebuildTree()
    }

    private func rebuildTree() {
        treeHost.subviews.forEach { $0.removeFromSuperview() }
        guard showsHorizontalTree, !items.isEmpty else { return }
        let forest = Self.forest(from: items)
        let indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let rootStack = NSStackView(views: forest.map { makeHorizontalNode($0, indexByID: indexByID) })
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        treeHost.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: treeHost.leadingAnchor, constant: 22),
            rootStack.topAnchor.constraint(equalTo: treeHost.topAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: treeHost.trailingAnchor, constant: -12),
            rootStack.bottomAnchor.constraint(equalTo: treeHost.bottomAnchor, constant: -8),
        ])
    }

    private func makeHorizontalNode(_ node: HeadingNode, indexByID: [BlockID: Int]) -> NSView {
        let button = NSButton(title: node.item.title, target: self, action: #selector(treeClicked(_:)))
        button.isBordered = false
        button.alignment = .left
        button.tag = indexByID[node.item.id] ?? 0
        button.lineBreakMode = .byTruncatingTail
        button.font = node.item.level <= 1
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12)
        button.contentTintColor = node.item.level <= 2 ? .labelColor : .secondaryLabelColor
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true

        guard !node.children.isEmpty else { return button }

        let children = NSStackView(views: node.children.map { makeHorizontalNode($0, indexByID: indexByID) })
        children.orientation = .vertical
        children.alignment = .leading
        children.spacing = 2

        let connector = NSTextField(labelWithString: "›")
        connector.font = .systemFont(ofSize: 11, weight: .medium)
        connector.textColor = .tertiaryLabelColor
        connector.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [button, connector, children])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 6
        return row
    }

    private struct HeadingNode {
        var item: OutlineItem
        var children: [HeadingNode] = []
    }

    private static func forest(from items: [OutlineItem]) -> [HeadingNode] {
        var roots: [HeadingNode] = []
        var stack: [(level: Int, path: [Int])] = []
        for item in items {
            while let last = stack.last, last.level >= item.level {
                stack.removeLast()
            }
            if stack.isEmpty {
                roots.append(HeadingNode(item: item))
                stack.append((item.level, [roots.count - 1]))
            } else {
                let path = stack[stack.count - 1].path
                append(item, to: &roots, path: path)
                var next = path
                next.append(childCount(roots, path: path) - 1)
                stack.append((item.level, next))
            }
        }
        return roots
    }

    private static func append(_ item: OutlineItem, to roots: inout [HeadingNode], path: [Int]) {
        func insert(_ node: inout HeadingNode, remaining: ArraySlice<Int>) {
            if remaining.isEmpty {
                node.children.append(HeadingNode(item: item))
                return
            }
            insert(&node.children[remaining[remaining.startIndex]], remaining: remaining.dropFirst())
        }
        if path.count == 1 {
            roots[path[0]].children.append(HeadingNode(item: item))
        } else {
            insert(&roots[path[0]], remaining: path.dropFirst())
        }
    }

    private static func childCount(_ roots: [HeadingNode], path: [Int]) -> Int {
        var node = roots[path[0]]
        for index in path.dropFirst() {
            node = node.children[index]
        }
        return node.children.count
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
