import AppKit

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var workspace: Workspace? {
        didSet {
            headerField?.stringValue = workspace?.rootURL.lastPathComponent ?? "Library"
            outline.reloadData()
            if let workspace {
                outline.expandItem(workspace.root)
            }
        }
    }
    var selectedURL: URL? {
        didSet { select(url: selectedURL) }
    }
    var onOpenFile: ((URL) -> Void)?
    var onOpenInNewWindow: ((URL) -> Void)?

    private let outline = NSOutlineView()
    private var headerField: NSTextField?

    override func loadView() {
        let header = NSTextField(labelWithString: "Library")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        outline.style = .sourceList
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.rowHeight = 26
        outline.indentationPerLevel = 14
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.doubleAction = #selector(clicked)
        outline.menu = makeContextMenu()
        scroll.documentView = outline

        let wrap = NSView()
        wrap.addSubview(header)
        wrap.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        headerField = header
        view = wrap
    }

    func setLibraryTitle(_ title: String) {
        headerField?.stringValue = title
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return workspace == nil ? 0 : 1
        }
        guard let node = item as? FileNode else { return 0 }
        return workspace?.expand(node).count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory == true
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return workspace!.root
        }
        let node = item as! FileNode
        return workspace!.expand(node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("file")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.font = .systemFont(ofSize: 13)
            let image = NSImageView()
            image.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            let wrap = NSTableCellView()
            wrap.identifier = id
            wrap.addSubview(image)
            wrap.addSubview(text)
            wrap.textField = text
            wrap.imageView = image
            image.translatesAutoresizingMaskIntoConstraints = false
            text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            ])
            return wrap
        }()
        guard let node = item as? FileNode else { return cell }
        if node.isTruncated {
            cell.textField?.stringValue = "2,000+ items, truncated"
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .tertiaryLabelColor
            cell.imageView?.image = nil
            return cell
        }
        cell.textField?.stringValue = node.url == workspace?.rootURL ? node.url.lastPathComponent : node.name
        cell.textField?.font = node.isDirectory
            ? .systemFont(ofSize: 13, weight: .medium)
            : .systemFont(ofSize: 13)
        cell.textField?.textColor = .labelColor
        cell.imageView?.image = NSImage(
            systemSymbolName: node.isDirectory ? "folder" : "doc.richtext",
            accessibilityDescription: nil
        )
        return cell
    }

    @objc private func clicked() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            if outline.isItemExpanded(node) {
                outline.collapseItem(node)
            } else {
                outline.expandItem(node)
            }
            return
        }
        guard node.isMarkdown else { return }
        onOpenFile?(node.url)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let node = menuNode, !node.isTruncated else { return false }
        switch menuItem.action {
        case #selector(revealInFinder), #selector(copyPath):
            return true
        case #selector(openInNewWindow):
            return node.isMarkdown
        default:
            return true
        }
    }

    private func select(url: URL?) {
        guard let url, let workspace else {
            outline.deselectAll(nil)
            return
        }
        expandToward(url, from: workspace.root)
        let row = outline.row(forItem: find(url, in: workspace.root))
        if row >= 0 {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }

    private func expandToward(_ url: URL, from node: FileNode) {
        let path = url.standardizedFileURL.path
        let nodePath = node.url.path
        let isAncestor = path == nodePath
            || path.hasPrefix(nodePath.hasSuffix("/") ? nodePath : nodePath + "/")
        guard isAncestor else { return }
        if node.isDirectory {
            outline.expandItem(node)
            for child in workspace?.expand(node) ?? [] {
                expandToward(url, from: child)
            }
        }
    }

    private func find(_ url: URL, in node: FileNode) -> FileNode? {
        if node.url == url.standardizedFileURL { return node }
        for child in node.children ?? [] where !child.isTruncated {
            if let match = find(url, in: child) { return match }
        }
        return nil
    }

    private var menuNode: FileNode? {
        let row = outline.clickedRow
        guard row >= 0 else { return nil }
        return outline.item(atRow: row) as? FileNode
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        reveal.target = self
        let copy = NSMenuItem(title: "Copy Path", action: #selector(copyPath), keyEquivalent: "")
        copy.target = self
        let openNew = NSMenuItem(title: "Open in New Window", action: #selector(openInNewWindow), keyEquivalent: "")
        openNew.target = self
        menu.addItem(reveal)
        menu.addItem(copy)
        menu.addItem(openNew)
        return menu
    }

    @objc private func revealInFinder() {
        guard let node = menuNode, !node.isTruncated else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func copyPath() {
        guard let node = menuNode, !node.isTruncated else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    @objc private func openInNewWindow() {
        guard let node = menuNode, node.isMarkdown else { return }
        onOpenInNewWindow?(node.url)
    }
}
