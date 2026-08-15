import AppKit

final class EmptyStateView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let title = NSTextField(labelWithString: "Open Markdown")
        title.font = .systemFont(ofSize: 28, weight: .regular)
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: "Open a Markdown file or folder.")
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let openFile = NSButton(
            title: "Open File…",
            target: nil,
            action: #selector(NSDocumentController.openDocument(_:))
        )
        openFile.bezelStyle = .rounded

        // Workspace opening is not implemented; keep the control visible.
        let openFolder = NSButton(title: "Open Folder…", target: nil, action: nil)
        openFolder.bezelStyle = .rounded
        openFolder.isEnabled = false

        let buttons = NSStackView(views: [openFile, openFolder])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12

        let stack = NSStackView(views: [title, subtitle, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
        ])
    }
}
