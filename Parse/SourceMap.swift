import Foundation

struct SourceMap: Sendable {
    /// `lineStartsUTF16[line]` is the UTF-16 offset of the first scalar of a 1-based cmark line.
    let lineStartsUTF16: [Int]
    let original: String

    func utf16Range(span: SourceSpan) -> NSRange {
        let start = utf16Offset(line: span.startLine, column: span.startColumn)
        let end = utf16Offset(line: span.endLine, column: span.endColumn)
        guard start != NSNotFound, end != NSNotFound, end >= start else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: start, length: end - start)
    }

    func blockID(containingSourceLine line: Int, in nodes: [BlockNode]) -> BlockID? {
        var match: BlockNode?
        func walk(_ nodes: [BlockNode]) {
            for node in nodes {
                if node.source.startLine <= line && line <= node.source.endLine {
                    match = node
                    walk(node.children)
                    return
                }
            }
        }
        walk(nodes)
        return match?.id
    }

    static func build(from original: String) -> SourceMap {
        var starts = [0, 0]
        var utf16 = 0
        let scalars = original.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            let next = scalars.index(after: index)
            if scalar == "\r" {
                let isCRLF = next < scalars.endIndex && scalars[next] == "\n"
                utf16 += isCRLF ? 2 : 1
                starts.append(utf16)
                index = isCRLF ? scalars.index(after: next) : next
                continue
            }
            if scalar == "\n" {
                utf16 += 1
                starts.append(utf16)
                index = next
                continue
            }
            utf16 += scalar.value > 0xFFFF ? 2 : 1
            index = next
        }
        return SourceMap(lineStartsUTF16: starts, original: original)
    }

    private func utf16Offset(line: Int, column: Int) -> Int {
        guard line > 0, line < lineStartsUTF16.count else { return NSNotFound }
        let lineStart = lineStartsUTF16[line]
        if column <= 1 { return lineStart }

        let utf16 = original.utf16
        var i = utf16.index(utf16.startIndex, offsetBy: lineStart, limitedBy: utf16.endIndex) ?? utf16.endIndex
        var cmarkCol = 1
        while i < utf16.endIndex {
            let unit = utf16[i]
            if unit == 0x0A || unit == 0x0D { break }
            if cmarkCol >= column { return lineStart + utf16.distance(from: utf16.startIndex, to: i) }

            if unit == 0x09 {
                cmarkCol = ((cmarkCol - 1) / 4 + 1) * 4 + 1
                i = utf16.index(after: i)
                continue
            }

            // cmark columns count UTF-8 bytes.
            if unit >= 0xD800 && unit <= 0xDBFF {
                let next = utf16.index(after: i)
                cmarkCol += 4
                i = next < utf16.endIndex ? utf16.index(after: next) : utf16.endIndex
            } else if unit < 0x80 {
                cmarkCol += 1
                i = utf16.index(after: i)
            } else if unit < 0x800 {
                cmarkCol += 2
                i = utf16.index(after: i)
            } else {
                cmarkCol += 3
                i = utf16.index(after: i)
            }
        }
        return lineStart + utf16.distance(from: utf16.startIndex, to: i)
    }
}
