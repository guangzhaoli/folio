import AppKit

enum BlockChrome {
    static func attachment(image: NSImage) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: image.size)
        return attachment
    }

    static func tableImage(rows: [[NSAttributedString]], headerRows: Int, maxWidth: CGFloat) -> NSImage {
        let padX: CGFloat = 10
        let padY: CGFloat = 7
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0, !rows.isEmpty else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        var colWidths = Array(repeating: CGFloat(56), count: columns)
        var rowHeights = Array(repeating: CGFloat(0), count: rows.count)
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() where c < columns {
                let size = cell.boundingRect(
                    with: NSSize(width: maxWidth, height: 4000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).integral.size
                colWidths[c] = max(colWidths[c], size.width + padX * 2)
                rowHeights[r] = max(rowHeights[r], size.height + padY * 2)
            }
        }

        var total = colWidths.reduce(0, +)
        let width = min(maxWidth, max(total, 160))
        if total > width {
            let scale = width / total
            colWidths = colWidths.map { $0 * scale }
            total = width
        } else if total < width {
            colWidths[colWidths.count - 1] += width - total
            total = width
        }
        let height = rowHeights.reduce(0, +)

        return draw(size: NSSize(width: total, height: height)) { _ in
            let bounds = NSRect(origin: .zero, size: NSSize(width: total, height: height))
            NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
            let clip = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
            clip.addClip()
            NSColor.textBackgroundColor.setFill()
            clip.fill()

            var y: CGFloat = 0
            for (r, row) in rows.enumerated() {
                var x: CGFloat = 0
                let rowRect = NSRect(x: 0, y: y, width: total, height: rowHeights[r])
                if r < headerRows {
                    NSColor.quaternaryLabelColor.withAlphaComponent(0.16).setFill()
                    rowRect.fill()
                } else if r % 2 == 1 {
                    NSColor.quaternaryLabelColor.withAlphaComponent(0.06).setFill()
                    rowRect.fill()
                }
                for c in 0..<columns {
                    let cellRect = NSRect(x: x, y: y, width: colWidths[c], height: rowHeights[r])
                    NSColor.separatorColor.withAlphaComponent(0.28).setStroke()
                    NSBezierPath.stroke(cellRect.insetBy(dx: 0.25, dy: 0.25))
                    if c < row.count {
                        let textRect = cellRect.insetBy(dx: padX, dy: padY)
                        row[c].draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
                    }
                    x += colWidths[c]
                }
                y += rowHeights[r]
            }

            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            clip.lineWidth = 1
            clip.stroke()
        }
    }

    static func quoteImage(content: NSAttributedString, maxWidth: CGFloat) -> NSImage {
        let inset = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 14)
        let textWidth = max(120, maxWidth - inset.left - inset.right)
        let textSize = content.boundingRect(
            with: NSSize(width: textWidth, height: 8000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size
        let size = NSSize(width: min(maxWidth, textSize.width + inset.left + inset.right), height: textSize.height + inset.top + inset.bottom)
        return draw(size: size) { _ in
            let bounds = NSRect(origin: .zero, size: size)
            let fill = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            fill.fill()
            let bar = NSBezierPath(roundedRect: NSRect(x: 5, y: 8, width: 3, height: size.height - 16), xRadius: 1.5, yRadius: 1.5)
            NSColor.controlAccentColor.setFill()
            bar.fill()
            let textRect = NSRect(x: inset.left, y: inset.top, width: textWidth, height: textSize.height)
            content.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    static func codeImage(code: String, style: ReaderStyle, maxWidth: CGFloat) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: style.bodyPointSize - 1.5, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let content = NSAttributedString(string: code.hasSuffix("\n") ? String(code.dropLast()) : code, attributes: attrs)
        let inset = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let textWidth = max(160, maxWidth - inset.left - inset.right)
        let textSize = content.boundingRect(
            with: NSSize(width: textWidth, height: 8000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size
        let size = NSSize(width: maxWidth, height: textSize.height + inset.top + inset.bottom)
        return draw(size: size) { _ in
            let bounds = NSRect(origin: .zero, size: size)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
            content.draw(
                with: NSRect(x: inset.left, y: inset.top, width: textWidth, height: textSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }
    }

    private static func draw(size: NSSize, body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            body(rect)
            return true
        }
    }
}
