import AppKit

final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var items: [OutlineItem] = [] {
        didSet {
            emptyLabel?.isHidden = !items.isEmpty
            tableView.reloadData()
        }
    }
    var onSelect: ((OutlineItem) -> Void)?
    var onDockDrag: ((NSGestureRecognizer.State, NSPoint) -> Void)?
    var onChoosePlacement: ((OutlinePlacement) -> Void)?

    private let tableView = NSTableView()
    private var emptyLabel: NSTextField?
    private var dockDragging = false

    override func loadView() {
        let grip = NSImageView()
        grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to move outline")
        grip.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        grip.contentTintColor = .tertiaryLabelColor
        grip.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "On This Page")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(grip)
        headerBar.addSubview(header)
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            grip.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 14),
            header.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 6),
            header.trailingAnchor.constraint(lessThanOrEqualTo: headerBar.trailingAnchor, constant: -10),
            header.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 28),
        ])
        let pan = NSPanGestureRecognizer(target: self, action: #selector(headerPanned(_:)))
        headerBar.addGestureRecognizer(pan)
        headerBar.menu = makePlacementMenu()

        let empty = NSTextField(labelWithString: "No headings")
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .tertiaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel = empty

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
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
        scroll.documentView = tableView

        let wrap = NSView()
        wrap.addSubview(headerBar)
        wrap.addSubview(scroll)
        wrap.addSubview(empty)
        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            headerBar.topAnchor.constraint(equalTo: wrap.safeAreaLayoutGuide.topAnchor, constant: 4),
            scroll.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            empty.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            empty.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 8),
        ])
        view = wrap
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

    private func makePlacementMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Below Library", action: #selector(placeBelow), keyEquivalent: "")
        menu.addItem(withTitle: "Top", action: #selector(placeTop), keyEquivalent: "")
        menu.addItem(withTitle: "Right", action: #selector(placeTrailing), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }
}