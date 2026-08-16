import AppKit

enum FindSupport {
    static let objectReplacement: unichar = 0xFFFC

    static func isAttachmentOnly(_ text: String, range: NSRange) -> Bool {
        let ns = text as NSString
        guard range.length > 0, range.location >= 0, NSMaxRange(range) <= ns.length else { return false }
        for index in range.location..<NSMaxRange(range) {
            if ns.character(at: index) != objectReplacement { return false }
        }
        return true
    }

    static func allMatches(in text: String, pattern: String) -> [NSRange] {
        let ns = text as NSString
        guard !pattern.isEmpty, ns.length > 0 else { return [] }
        var results: [NSRange] = []
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            guard let hit = firstSearchable(
                in: ns,
                pattern: pattern,
                range: search,
                options: [.caseInsensitive]
            ) else { break }
            results.append(hit)
            let next = NSMaxRange(hit)
            if next >= NSMaxRange(search) { break }
            search = NSRange(location: next, length: NSMaxRange(search) - next)
        }
        return results
    }

    static func currentMatch(in matches: [NSRange], selected: NSRange) -> NSRange? {
        matches.first { $0 == selected }
    }

    static func nextMatch(
        in text: String,
        pattern: String,
        from location: Int,
        backwards: Bool,
        wrap: Bool
    ) -> NSRange? {
        let ns = text as NSString
        guard !pattern.isEmpty, ns.length > 0 else { return nil }
        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
        let start = min(max(location, 0), ns.length)
        if backwards {
            if start > 0,
               let hit = firstSearchable(in: ns, pattern: pattern, range: NSRange(location: 0, length: start), options: options) {
                return hit
            }
            if wrap, let hit = firstSearchable(in: ns, pattern: pattern, range: NSRange(location: 0, length: ns.length), options: options) {
                return hit
            }
        } else {
            if start < ns.length,
               let hit = firstSearchable(in: ns, pattern: pattern, range: NSRange(location: start, length: ns.length - start), options: options) {
                return hit
            }
            if wrap, let hit = firstSearchable(in: ns, pattern: pattern, range: NSRange(location: 0, length: ns.length), options: options) {
                return hit
            }
        }
        return nil
    }

    private static func firstSearchable(
        in text: NSString,
        pattern: String,
        range: NSRange,
        options: NSString.CompareOptions
    ) -> NSRange? {
        var search = range
        while search.length > 0 {
            let hit = text.range(of: pattern, options: options, range: search)
            guard hit.location != NSNotFound else { return nil }
            if !isAttachmentOnly(text as String, range: hit) { return hit }
            if options.contains(.backwards) {
                search = NSRange(location: search.location, length: hit.location - search.location)
            } else {
                let next = NSMaxRange(hit)
                search = NSRange(location: next, length: NSMaxRange(range) - next)
            }
        }
        return nil
    }
}

enum FindHighlight {
    private static let views = NSHashTable<NSTextView>.weakObjects()
    private static var installed = false
    private static var refreshing = false

    static var matchColor: NSColor { .findHighlightColor }

    static var currentColor: NSColor {
        NSColor(name: "FolioFindCurrent") { appearance in
            var color = NSColor.systemOrange
            appearance.performAsCurrentDrawingAppearance {
                color = NSColor.findHighlightColor.blended(withFraction: 0.42, of: .systemOrange) ?? .systemOrange
            }
            return color
        }
    }

    static func attach(to scroll: NSScrollView, textView: NSTextView) {
        install()
        scroll.findBarPosition = .aboveContent
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scroll.contentView,
            queue: .main
        ) { [weak textView] _ in
            refresh(in: textView)
        }
    }

    static func refresh(in textView: NSTextView?) {
        install()
        guard let textView, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard isFindBarShowing(in: textView) else {
            clear(from: textView)
            return
        }
        let pattern = pattern(in: textView)
        let matches = FindSupport.allMatches(in: textView.string, pattern: pattern)
        let current = FindSupport.currentMatch(in: matches, selected: textView.selectedRange())
        paint(textView, matches: matches, current: current)
        applyFindingSelection(to: textView)
        views.add(textView)
        textView.needsDisplay = true
    }

    static func clear(from textView: NSTextView) {
        guard views.contains(textView) else { return }
        if let layout = textView.textLayoutManager {
            layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        }
        restoreSelection(on: textView)
        views.remove(textView)
        textView.needsDisplay = true
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSControl.textDidChangeNotification, object: nil, queue: .main) { note in
            guard let field = note.object as? NSTextField else { return }
            refreshIfFindField(field)
        }
        center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main) { note in
            guard let textView = note.object as? NSTextView, views.contains(textView) || isFindBarShowing(in: textView) else { return }
            refresh(in: textView)
        }
        center.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { note in
            guard let textView = note.object as? NSTextView, views.contains(textView) || isFindBarShowing(in: textView) else { return }
            refresh(in: textView)
        }
    }

    private static func refreshIfFindField(_ field: NSTextField) {
        var view: NSView? = field
        while let current = view {
            if let scroll = current as? NSScrollView, let textView = scroll.documentView as? NSTextView {
                refresh(in: textView)
                return
            }
            view = current.superview
        }
    }

    private static func isFindBarShowing(in textView: NSTextView) -> Bool {
        guard let scroll = textView.enclosingScrollView else { return false }
        guard scroll.isFindBarVisible else { return false }
        guard let bar = scroll.findBarView else { return false }
        return bar.superview != nil && bar.isHidden == false
    }

    private static func pattern(in textView: NSTextView) -> String {
        if let bar = textView.enclosingScrollView?.findBarView, let field = firstEditableField(in: bar) {
            return field.stringValue
        }
        return NSPasteboard(name: .find).string(forType: .string) ?? ""
    }

    private static func firstEditableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for child in view.subviews {
            if let field = firstEditableField(in: child) { return field }
        }
        return nil
    }

    private static func paint(_ textView: NSTextView, matches: [NSRange], current: NSRange?) {
        guard let layout = textView.textLayoutManager else { return }
        layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        for match in matches {
            if let current, match == current { continue }
            guard let range = NSTextRange(match, in: layout) else { continue }
            layout.addRenderingAttribute(.backgroundColor, value: matchColor, for: range)
        }
        layout.invalidateRenderingAttributes(for: layout.documentRange)
    }

    private static func applyFindingSelection(to textView: NSTextView) {
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            textView.selectedTextAttributes = [
                .backgroundColor: currentColor,
                .foregroundColor: NSColor.labelColor,
            ]
        }
    }

    private static func restoreSelection(on textView: NSTextView) {
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor,
        ]
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
