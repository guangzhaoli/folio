import AppKit

/// One-line “On this page” control above the document. Distinct from the file library.
final class HeadingJumpBar: NSView {
    var items: [OutlineItem] = [] {
        didSet { rebuild() }
    }
    var onSelect: ((OutlineItem) -> Void)?

    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "On This Page")
    private let pathLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let button = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    private func setup() {
        wantsLayer = true
        icon.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "On This Page")
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .labelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor

        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = #selector(showMenu)

        let stack = NSStackView(views: [icon, titleLabel, pathLabel, chevron])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.setCustomSpacing(14, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(button)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rebuild()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        let line = NSBezierPath()
        line.lineWidth = 1
        line.move(to: NSPoint(x: 0, y: 0.5))
        line.line(to: NSPoint(x: bounds.width, y: 0.5))
        line.stroke()
    }

    private func rebuild() {
        if items.isEmpty {
            pathLabel.stringValue = "No headings"
            pathLabel.textColor = .tertiaryLabelColor
        } else {
            pathLabel.stringValue = items.prefix(3).map(\.title).joined(separator: "  ·  ")
                + (items.count > 3 ? "  ·  …" : "")
            pathLabel.textColor = .labelColor
        }
        needsDisplay = true
    }

    @objc func showMenu() {
        guard !items.isEmpty else { return }
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let pad = String(repeating: "    ", count: max(0, item.level - 1))
            let entry = NSMenuItem(title: pad + item.title, action: #selector(picked(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 12, y: bounds.height), in: self)
    }

    @objc private func picked(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag])
    }
}
