import AppKit

enum BlockChrome {
    static func attachment(image: NSImage) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: image.size)
        return attachment
    }

    static func tableImage(rows: [[NSAttributedString]], headerRows: Int, maxWidth: CGFloat) -> NSImage {
        let padX: CGFloat = 12
        let padY: CGFloat = 8
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0, !rows.isEmpty else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        let minCol: CGFloat = 52
        let maxCol = max(minCol, floor((maxWidth - 2) / CGFloat(columns)))
        var colWidths = Array(repeating: minCol, count: columns)
        var rowHeights = Array(repeating: CGFloat(0), count: rows.count)

        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() where c < columns {
                let size = cell.boundingRect(
                    with: NSSize(width: maxCol - padX * 2, height: 4000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).integral.size
                colWidths[c] = min(maxCol, max(colWidths[c], size.width + padX * 2))
                rowHeights[r] = max(rowHeights[r], max(28, size.height + padY * 2))
            }
        }

        var total = colWidths.reduce(0, +)
        if total > maxWidth {
            let scale = maxWidth / total
            colWidths = colWidths.map { $0 * scale }
            total = maxWidth
        }

        let height = rowHeights.reduce(0, +)
        return draw(size: NSSize(width: total, height: height)) { _ in
            let bounds = NSRect(origin: .zero, size: NSSize(width: total, height: height))
            let clip = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            clip.addClip()
            NSColor.textBackgroundColor.setFill()
            clip.fill()

            var y: CGFloat = 0
            for (r, row) in rows.enumerated() {
                var x: CGFloat = 0
                let rowRect = NSRect(x: 0, y: y, width: total, height: rowHeights[r])
                if r < headerRows {
                    NSColor.quaternaryLabelColor.withAlphaComponent(0.22).setFill()
                    rowRect.fill()
                }
                if r > 0 {
                    NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
                    let line = NSBezierPath()
                    line.lineWidth = 1
                    line.move(to: NSPoint(x: 0, y: y + 0.5))
                    line.line(to: NSPoint(x: total, y: y + 0.5))
                    line.stroke()
                }
                for c in 0..<columns {
                    if c < row.count {
                        let textRect = NSRect(
                            x: x + padX,
                            y: y + padY,
                            width: colWidths[c] - padX * 2,
                            height: rowHeights[r] - padY * 2
                        )
                        row[c].draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
                    }
                    x += colWidths[c]
                }
                y += rowHeights[r]
            }

            NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
            clip.lineWidth = 1
            clip.stroke()
        }
    }

    static func quoteImage(content: NSAttributedString, depth: Int, maxWidth: CGFloat) -> NSImage {
        let bars = max(1, depth)
        let barPitch: CGFloat = 7
        let inset = NSEdgeInsets(top: 10, left: 12 + CGFloat(bars) * barPitch, bottom: 10, right: 14)
        let textWidth = max(120, maxWidth - inset.left - inset.right)
        let textSize = content.boundingRect(
            with: NSSize(width: textWidth, height: 8000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size
        let width = min(maxWidth, max(textSize.width + inset.left + inset.right, 180))
        let size = NSSize(width: width, height: textSize.height + inset.top + inset.bottom)
        return draw(size: size) { _ in
            let bounds = NSRect(origin: .zero, size: size)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
            for i in 0..<bars {
                let x = 6 + CGFloat(i) * barPitch
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: 8, width: 3, height: size.height - 16),
                    xRadius: 1.5,
                    yRadius: 1.5
                )
                NSColor.controlAccentColor.withAlphaComponent(i == 0 ? 1 : 0.45).setFill()
                bar.fill()
            }
            content.draw(
                with: NSRect(x: inset.left, y: inset.top, width: textWidth, height: textSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }
    }

    static func codeImage(code: String, style: ReaderStyle, maxWidth: CGFloat) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: style.bodyPointSize - 2, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.28
        let content = NSAttributedString(
            string: code.hasSuffix("\n") ? String(code.dropLast()) : code,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        let inset = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let textWidth = max(80, maxWidth - inset.left - inset.right)
        let textSize = content.boundingRect(
            with: NSSize(width: textWidth, height: 8000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral.size
        let width = min(maxWidth, max(textSize.width + inset.left + inset.right, 120))
        let size = NSSize(width: width, height: textSize.height + inset.top + inset.bottom)
        return draw(size: size) { _ in
            let bounds = NSRect(origin: .zero, size: size)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.12).setFill()
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
