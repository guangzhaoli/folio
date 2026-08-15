import AppKit

struct ReadingDocument {
    var text: NSAttributedString
    var blockCharRanges: [BlockID: NSRange]
}

enum ReadingRenderer {
    static func render(snapshot: ParseSnapshot, baseDirectory: URL?, style: ReaderStyle) -> ReadingDocument {
        let output = NSMutableAttributedString()
        var ranges: [BlockID: NSRange] = [:]
        var listDepth = 0
        for node in snapshot.nodes {
            appendBlock(node, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: 1)
        }
        return ReadingDocument(text: output, blockCharRanges: ranges)
    }

    private static func appendBlock(
        _ node: BlockNode,
        to output: NSMutableAttributedString,
        ranges: inout [BlockID: NSRange],
        style: ReaderStyle,
        baseDirectory: URL?,
        listDepth: inout Int,
        orderedIndex: Int
    ) {
        let start = output.length
        switch node.kind {
        case .heading(let level):
            appendInlines(node.inlines, to: output, attributes: headingAttrs(level: level, style: style), baseDirectory: baseDirectory)
            output.append(breakAfter(style.headingSpaceAfter(level)))
        case .paragraph:
            appendInlines(node.inlines, to: output, attributes: bodyAttrs(style: style, indent: CGFloat(listDepth) * style.listStep), baseDirectory: baseDirectory)
            output.append(breakAfter(listDepth > 0 ? 3 : 12))
        case .list(let ordered):
            var index = 1
            for child in node.children {
                appendBlock(
                    child,
                    to: output,
                    ranges: &ranges,
                    style: style,
                    baseDirectory: baseDirectory,
                    listDepth: &listDepth,
                    orderedIndex: ordered ? index : 0
                )
                index += 1
            }
            if listDepth == 0 {
                output.append(breakAfter(8))
            }
        case .item(let checked):
            appendListItem(
                node,
                checked: checked,
                orderedIndex: orderedIndex,
                to: output,
                ranges: &ranges,
                style: style,
                baseDirectory: baseDirectory,
                listDepth: &listDepth
            )
        case .codeBlock:
            let code = MarkdownParser.plainText(node.inlines)
            appendAttachment(BlockChrome.codeImage(code: code, style: style, maxWidth: style.measure), to: output)
        case .blockQuote:
            let inner = NSMutableAttributedString()
            var quoteDepth = 1
            flattenQuote(node, depth: 1, into: inner, ranges: &ranges, style: style, baseDirectory: baseDirectory, maxDepth: &quoteDepth)
            if inner.length > 0 {
                trimTrailingNewlines(inner)
                inner.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: inner.length))
            }
            appendAttachment(BlockChrome.quoteImage(content: inner, depth: quoteDepth, maxWidth: style.measure), to: output)
        case .thematicBreak:
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            ps.paragraphSpacing = 18
            ps.paragraphSpacingBefore = 8
            output.append(NSAttributedString(string: "·   ·   ·\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: ps,
            ]))
        case .table:
            var rows: [[NSAttributedString]] = []
            var headerRows = 0
            for child in node.children {
                guard case .tableRow(let isHeader) = child.kind else { continue }
                var cells: [NSAttributedString] = []
                for cell in child.children {
                    guard case .tableCell = cell.kind else { continue }
                    let piece = NSMutableAttributedString()
                    appendInlines(
                        cell.inlines,
                        to: piece,
                        attributes: isHeader ? headerCellAttrs(style: style) : bodyAttrs(style: style, indent: 0),
                        baseDirectory: baseDirectory
                    )
                    cells.append(piece)
                }
                if isHeader { headerRows += 1 }
                rows.append(cells)
            }
            if !rows.isEmpty {
                appendAttachment(BlockChrome.tableImage(rows: rows, headerRows: headerRows, maxWidth: style.measure), to: output)
            }
        case .tableRow, .tableCell:
            break
        case .html:
            appendInlines(node.inlines, to: output, attributes: monoAttrs(style: style), baseDirectory: baseDirectory)
            output.append(breakAfter(8))
        case .footnoteDefinition:
            for child in node.children {
                appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: 1)
            }
        }

        let length = output.length - start
        if length > 0 {
            ranges[node.id] = NSRange(location: start, length: length)
        }
    }

    private static func appendListItem(
        _ node: BlockNode,
        checked: Bool?,
        orderedIndex: Int,
        to output: NSMutableAttributedString,
        ranges: inout [BlockID: NSRange],
        style: ReaderStyle,
        baseDirectory: URL?,
        listDepth: inout Int
    ) {
        listDepth += 1
        let marker: String
        if let checked {
            marker = checked ? "✓  " : "○  "
        } else if orderedIndex > 0 {
            marker = "\(orderedIndex).  "
        } else {
            marker = "•  "
        }
        let base = CGFloat(listDepth - 1) * style.listStep
        let markerWidth = ceil((marker as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: style.bodyPointSize),
        ]).width)
        let hanging = listAttrs(style: style, indent: base, hang: markerWidth)

        let line = NSMutableAttributedString()
        var markerAttrs = hanging
        markerAttrs[.foregroundColor] = NSColor.tertiaryLabelColor
        line.append(NSAttributedString(string: marker, attributes: markerAttrs))

        if !node.inlines.isEmpty {
            appendInlines(node.inlines, to: line, attributes: hanging, baseDirectory: baseDirectory)
        } else if let paragraph = node.children.first, case .paragraph = paragraph.kind {
            appendInlines(paragraph.inlines, to: line, attributes: hanging, baseDirectory: baseDirectory)
        }
        line.append(NSAttributedString(string: "\n", attributes: hanging))
        output.append(line)

        var childIndex = 1
        for child in node.children {
            if case .paragraph = child.kind, node.inlines.isEmpty, child.id == node.children.first?.id {
                continue
            }
            let nextOrdered: Int
            if case .list(let ordered) = child.kind {
                nextOrdered = ordered ? 1 : 0
            } else {
                nextOrdered = childIndex
            }
            appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: nextOrdered)
            childIndex += 1
        }
        listDepth -= 1
    }

    private static func flattenQuote(
        _ node: BlockNode,
        depth: Int,
        into output: NSMutableAttributedString,
        ranges: inout [BlockID: NSRange],
        style: ReaderStyle,
        baseDirectory: URL?,
        maxDepth: inout Int
    ) {
        maxDepth = max(maxDepth, depth)
        var innerDepth = 0
        for child in node.children {
            if case .blockQuote = child.kind {
                flattenQuote(child, depth: depth + 1, into: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, maxDepth: &maxDepth)
            } else {
                appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &innerDepth, orderedIndex: 1)
            }
        }
    }

    private static func appendAttachment(_ image: NSImage, to output: NSMutableAttributedString) {
        output.append(NSAttributedString(attachment: BlockChrome.attachment(image: image)))
        output.append(breakAfter(16))
    }

    private static func breakAfter(_ space: CGFloat) -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = space
        return NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 2),
            .paragraphStyle: ps,
        ])
    }

    private static func trimTrailingNewlines(_ text: NSMutableAttributedString) {
        while text.length > 0 {
            let last = (text.string as NSString).substring(from: text.length - 1)
            if last == "\n" || last == " " {
                text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
            } else {
                break
            }
        }
    }

    private static func appendInlines(
        _ inlines: [InlineNode],
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any],
        baseDirectory: URL?
    ) {
        for inline in inlines {
            switch inline {
            case .text(let text):
                output.append(NSAttributedString(string: text, attributes: attributes))
            case .softBreak:
                output.append(NSAttributedString(string: " ", attributes: attributes))
            case .lineBreak:
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            case .code(let code):
                var attrs = attributes
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: (attributes[.font] as? NSFont)?.pointSize ?? 15, weight: .regular)
                attrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.14)
                attrs[.foregroundColor] = NSColor.labelColor
                output.append(NSAttributedString(string: "\u{00A0}\(code)\u{00A0}", attributes: attrs))
            case .strong(let children):
                var attrs = attributes
                let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 17)
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                appendInlines(children, to: output, attributes: attrs, baseDirectory: baseDirectory)
            case .emphasis(let children):
                var attrs = attributes
                let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 17)
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                appendInlines(children, to: output, attributes: attrs, baseDirectory: baseDirectory)
            case .strikethrough(let children):
                var attrs = attributes
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                appendInlines(children, to: output, attributes: attrs, baseDirectory: baseDirectory)
            case .link(let destination, let children):
                var attrs = attributes
                attrs[.foregroundColor] = NSColor.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let url = URL(string: destination) {
                    attrs[.link] = url
                } else if let baseDirectory {
                    attrs[.link] = URL(fileURLWithPath: destination, relativeTo: baseDirectory)
                }
                appendInlines(children, to: output, attributes: attrs, baseDirectory: baseDirectory)
            case .image(let destination, let alt):
                if let image = loadImage(destination, baseDirectory: baseDirectory) {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    let maxWidth: CGFloat = 560
                    if image.size.width > maxWidth {
                        let scale = maxWidth / image.size.width
                        attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: image.size.height * scale)
                    }
                    output.append(NSAttributedString(attachment: attachment))
                } else {
                    output.append(NSAttributedString(string: alt.isEmpty ? "[image]" : alt, attributes: attributes))
                }
            case .html(let html):
                output.append(NSAttributedString(string: html, attributes: attributes))
            case .footnoteReference(let label):
                var attrs = attributes
                attrs[.baselineOffset] = 4
                let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 17)
                attrs[.font] = NSFont.systemFont(ofSize: font.pointSize - 4)
                output.append(NSAttributedString(string: "[\(label)]", attributes: attrs))
            }
        }
    }

    private static func loadImage(_ destination: String, baseDirectory: URL?) -> NSImage? {
        if destination.hasPrefix("http://") || destination.hasPrefix("https://") || destination.hasPrefix("file:") {
            return nil
        }
        guard let baseDirectory else { return nil }
        let decoded = destination.removingPercentEncoding ?? destination
        let url = URL(fileURLWithPath: decoded, relativeTo: baseDirectory).standardizedFileURL
        return NSImage(contentsOf: url)
    }

    private static func bodyAttrs(style: ReaderStyle, indent: CGFloat) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = style.lineHeight
        ps.paragraphSpacing = 10
        ps.headIndent = indent
        ps.firstLineHeadIndent = indent
        return [
            .font: NSFont.systemFont(ofSize: style.bodyPointSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private static func listAttrs(style: ReaderStyle, indent: CGFloat, hang: CGFloat) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = style.lineHeight
        ps.paragraphSpacing = 4
        ps.firstLineHeadIndent = indent
        ps.headIndent = indent + hang
        ps.tabStops = [NSTextTab(textAlignment: .left, location: indent + hang)]
        return [
            .font: NSFont.systemFont(ofSize: style.bodyPointSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private static func headerCellAttrs(style: ReaderStyle) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: style.bodyPointSize - 1, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private static func headingAttrs(level: Int, style: ReaderStyle) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.12
        ps.paragraphSpacing = style.headingSpaceAfter(level)
        ps.paragraphSpacingBefore = style.headingSpaceBefore(level)
        return [
            .font: NSFont.systemFont(ofSize: style.headingPointSize(level), weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private static func monoAttrs(style: ReaderStyle) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.25
        return [
            .font: NSFont.monospacedSystemFont(ofSize: style.bodyPointSize - 2, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }
}
