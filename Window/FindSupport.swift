import Foundation

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