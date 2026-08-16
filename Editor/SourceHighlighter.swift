import AppKit

enum SourceHighlighter {
    static func apply(snapshot: ParseSnapshot, to textView: NSTextView) {
        guard let layout = textView.textLayoutManager else { return }
        let full = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        guard full.length > 0 else { return }

        let visible = visibleUTF16Range(in: textView)
        let padded = paddedRange(visible, limit: full.length, pad: 4000)

        func paint(_ range: NSRange, _ color: NSColor) {
            guard range.location != NSNotFound, range.length > 0,
                  NSIntersectionRange(range, padded).length > 0,
                  let textRange = NSTextRange(range, in: layout)
            else { return }
            layout.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
        }

        func walk(_ nodes: [BlockNode]) {
            for node in nodes {
                switch node.kind {
                case .heading:
                    paint(node.source.utf16Range, .secondaryLabelColor)
                case .codeBlock:
                    paint(node.source.utf16Range, .systemTeal)
                case .blockQuote:
                    paint(node.source.utf16Range, .secondaryLabelColor)
                default:
                    break
                }
                paintInlines(node.inlines, paint: paint)
                walk(node.children)
            }
        }
        walk(snapshot.nodes)
    }

    private static func paintInlines(_ inlines: [InlineNode], paint: (NSRange, NSColor) -> Void) {
        // Inline source ranges are not stored separately; skip to stay cheap and accurate at block grain.
        _ = inlines
        _ = paint
    }

    private static func visibleUTF16Range(in textView: NSTextView) -> NSRange {
        let visible = textView.visibleRect
        let glyphOrigin = textView.characterIndexForInsertion(at: NSPoint(x: visible.minX, y: visible.minY))
        let glyphEnd = textView.characterIndexForInsertion(at: NSPoint(x: visible.maxX, y: visible.maxY))
        let loc = min(glyphOrigin, glyphEnd)
        let end = max(glyphOrigin, glyphEnd)
        return NSRange(location: loc, length: max(0, end - loc))
    }

    private static func paddedRange(_ range: NSRange, limit: Int, pad: Int) -> NSRange {
        let loc = max(0, range.location - pad)
        let end = min(limit, range.location + range.length + pad)
        return NSRange(location: loc, length: max(0, end - loc))
    }
}

private extension NSTextRange {
    convenience init?(_ range: NSRange, in layout: NSTextLayoutManager) {
        guard let content = layout.textContentManager else { return nil }
        guard let start = content.location(content.documentRange.location, offsetBy: range.location) else { return nil }
        guard let end = content.location(start, offsetBy: range.length) else { return nil }
        self.init(location: start, end: end)
    }
}
