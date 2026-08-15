import AppKit

final class ReadingTextView: NSTextView {
    var onAppearanceChange: (() -> Void)?
    var onMeasureChange: ((CGFloat) -> Void)?
    var baseDirectory: URL?
    var onOpenLink: ((String) -> Void)?

    private var lastUsableWidth: CGFloat = 0

    static let columnMargin: CGFloat = 36
    static let columnCap: CGFloat = 860

    var usableWidth: CGFloat {
        Self.usableWidth(in: bounds.width)
    }

    static func usableWidth(in boundsWidth: CGFloat, cap: CGFloat = columnCap, margin: CGFloat = columnMargin) -> CGFloat {
        guard boundsWidth > 1 else { return min(cap, 720) }
        return max(280, min(cap, boundsWidth - margin * 2))
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        if let dest = textStorage?.attribute(PathResolver.destinationKey, at: charIndex, effectiveRange: nil) as? String {
            onOpenLink?(dest)
            return
        }
        if let url = link as? URL, url.scheme != "folio" {
            onOpenLink?(url.absoluteString)
            return
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func layout() {
        super.layout()
        applyColumn(bounds.width)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyColumn(newSize.width)
    }

    private func applyColumn(_ width: CGFloat) {
        guard let container = textContainer else { return }
        let usable: CGFloat
        if width > 120 {
            usable = Self.usableWidth(in: width)
        } else if lastUsableWidth > 0 {
            return
        } else {
            usable = Self.usableWidth(in: 720)
        }
        container.widthTracksTextView = false
        container.containerSize = NSSize(width: usable, height: .greatestFiniteMagnitude)
        let side = max(Self.columnMargin, (max(width, usable) - usable) / 2)
        textContainerInset = NSSize(width: side, height: 36)
        guard abs(usable - lastUsableWidth) > 6 else { return }
        lastUsableWidth = usable
        onMeasureChange?(usable)
    }
}
