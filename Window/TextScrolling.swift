import AppKit
import QuartzCore

enum TextScrolling {
    static let duration: TimeInterval = 0.22

    static func scroll(_ textView: NSTextView, to range: NSRange, completion: (() -> Void)? = nil) {
        ensureLayout(textView)
        let length = (textView.string as NSString).length
        guard length > 0, let scroll = textView.enclosingScrollView else {
            textView.scrollRangeToVisible(range)
            completion?()
            return
        }
        let location = min(max(range.location, 0), length - 1)
        let query = NSRange(location: location, length: min(max(range.length, 1), length - location))
        guard let origin = origin(for: query, in: textView, scroll: scroll) else {
            textView.scrollRangeToVisible(query)
            completion?()
            return
        }
        animate(scroll, to: origin, completion: completion)
    }

    private static func animate(_ scroll: NSScrollView, to origin: NSPoint, completion: (() -> Void)?) {
        let clip = scroll.contentView
        let current = scroll.documentVisibleRect.origin
        if hypot(current.x - origin.x, current.y - origin.y) < 2 {
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = false
            clip.animator().setBoundsOrigin(origin)
        }, completionHandler: {
            scroll.reflectScrolledClipView(clip)
            completion?()
        })
    }

    private static func origin(for range: NSRange, in textView: NSTextView, scroll: NSScrollView) -> NSPoint? {
        let docRect: NSRect
        if let fallback = layoutRect(for: range, in: textView), fallback.height > 0 || fallback.width > 0 {
            docRect = fallback
        } else {
            var actual = NSRange()
            let screen = textView.firstRect(forCharacterRange: range, actualRange: &actual)
            guard screen.width + screen.height > 0, let window = textView.window else { return nil }
            docRect = textView.convert(window.convertFromScreen(screen), from: nil)
        }
        let visible = scroll.documentVisibleRect
        let maxY = max(0, (scroll.documentView?.bounds.height ?? textView.bounds.height) - visible.height)
        let y = min(max(0, docRect.minY - 28), maxY)
        return NSPoint(x: visible.minX, y: y)
    }

    private static func layoutRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        if let tlm = textView.textLayoutManager, let content = tlm.textContentManager {
            tlm.ensureLayout(for: tlm.documentRange)
            guard let start = content.location(content.documentRange.location, offsetBy: range.location) else {
                return nil
            }
            let end = content.location(start, offsetBy: max(range.length, 1)) ?? start
            guard let textRange = NSTextRange(location: start, end: end) else { return nil }
            var union = CGRect.null
            tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                union = union.union(rect)
                return true
            }
            return union.isNull ? nil : union
        }
        if let layout = textView.layoutManager, let container = textView.textContainer {
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = textView.textContainerOrigin
            return rect.offsetBy(dx: origin.x, dy: origin.y)
        }
        return nil
    }

    private static func ensureLayout(_ textView: NSTextView) {
        if let layout = textView.textLayoutManager {
            layout.ensureLayout(for: layout.documentRange)
            layout.textViewportLayoutController.layoutViewport()
        } else if let manager = textView.layoutManager {
            manager.ensureLayout(forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length))
        }
    }
}