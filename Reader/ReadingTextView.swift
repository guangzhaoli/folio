import AppKit

final class ReadingTextView: NSTextView {
    var measure: CGFloat = ReaderStyle.default.measure
    var onAppearanceChange: (() -> Void)?
    var onMeasureChange: ((CGFloat) -> Void)?
    private var lastUsableWidth: CGFloat = 0

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func layout() {
        super.layout()
        if let container = textContainer {
            let usable = max(240, min(measure, bounds.width - 88))
            container.containerSize = NSSize(width: usable, height: .greatestFiniteMagnitude)
            container.widthTracksTextView = false
            textContainerInset = NSSize(width: max(32, (bounds.width - usable) / 2), height: 36)
            if abs(usable - lastUsableWidth) > 12 {
                lastUsableWidth = usable
                onMeasureChange?(usable)
            }
        }
    }
}
