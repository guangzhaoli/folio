import AppKit

final class ReadingTextView: NSTextView {
    var measure: CGFloat = ReaderStyle.default.measure
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func layout() {
        super.layout()
        if let container = textContainer {
            let usable = max(240, min(measure, bounds.width - 72))
            container.containerSize = NSSize(width: usable, height: .greatestFiniteMagnitude)
            container.widthTracksTextView = false
            textContainerInset = NSSize(width: max(28, (bounds.width - usable) / 2), height: 28)
        }
    }
}
