import AppKit

final class OutlineDropOverlay: NSView {
    var zones: [OutlinePlacement: NSRect] = [:]
    var highlighted: OutlinePlacement? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        for placement in OutlinePlacement.allCases {
            guard let rect = zones[placement], rect.width > 8, rect.height > 8 else { continue }
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 12, yRadius: 12)
            if placement == highlighted {
                NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
                NSColor.controlAccentColor.setStroke()
            } else {
                NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
                NSColor.separatorColor.setStroke()
            }
            path.lineWidth = 1.5
            path.fill()
            path.stroke()

            let label = placement.title as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: placement == highlighted ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }

    func placement(at point: NSPoint) -> OutlinePlacement? {
        for (placement, rect) in zones where rect.contains(point) {
            return placement
        }
        return nil
    }
}