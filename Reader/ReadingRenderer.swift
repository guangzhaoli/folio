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
            output.append(NSAttributedString(string: "\n"))
        case .paragraph:
            appendInlines(node.inlines, to: output, attributes: bodyAttrs(style: style, indent: CGFloat(listDepth) * 22), baseDirectory: baseDirectory)
            output.append(NSAttributedString(string: "\n"))
        case .list:
            var index = 1
            for child in node.children {
                appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: index)
                index += 1
            }
        case .item(let checked):
            listDepth += 1
            let marker: String
            if let checked {
                marker = checked ? "☑  " : "☐  "
            } else if case .list(let ordered) = node.children.first?.kind {
                _ = ordered
                marker = ""
            } else {
                marker = "•  "
            }
            if !marker.isEmpty {
                output.append(NSAttributedString(string: String(repeating: "\t", count: max(0, listDepth - 1)) + marker, attributes: bodyAttrs(style: style, indent: 0)))
            }
            if !node.inlines.isEmpty {
                appendInlines(node.inlines, to: output, attributes: bodyAttrs(style: style, indent: 0), baseDirectory: baseDirectory)
                output.append(NSAttributedString(string: "\n"))
            }
            var childIndex = 1
            for child in node.children {
                appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: childIndex)
                childIndex += 1
            }
            listDepth -= 1
        case .codeBlock:
            let code = MarkdownParser.plainText(node.inlines)
            var attrs = monoAttrs(style: style)
            attrs[.backgroundColor] = NSColor.textBackgroundColor.shadow(withLevel: 0.06) ?? NSColor.quaternaryLabelColor
            output.append(NSAttributedString(string: (code.hasSuffix("\n") ? code : code + "\n"), attributes: attrs))
            output.append(NSAttributedString(string: "\n"))
        case .blockQuote:
            for child in node.children {
                appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: 1)
            }
        case .thematicBreak:
            output.append(NSAttributedString(string: "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\n", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.separatorColor,
            ]))
        case .table:
            for child in node.children {
                appendBlock(child, to: output, ranges: &ranges, style: style, baseDirectory: baseDirectory, listDepth: &listDepth, orderedIndex: 1)
            }
            output.append(NSAttributedString(string: "\n"))
        case .tableRow:
            var cells: [String] = []
            for child in node.children {
                if case .tableCell = child.kind {
                    cells.append(MarkdownParser.plainText(child.inlines))
                }
            }
            let line = cells.joined(separator: "   ") + "\n"
            output.append(NSAttributedString(string: line, attributes: monoAttrs(style: style)))
        case .tableCell:
            break
        case .html:
            appendInlines(node.inlines, to: output, attributes: monoAttrs(style: style), baseDirectory: baseDirectory)
            output.append(NSAttributedString(string: "\n"))
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
                attrs[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
                output.append(NSAttributedString(string: code, attributes: attrs))
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
        let font = NSFont.systemFont(ofSize: style.bodyPointSize)
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.28
        ps.paragraphSpacing = 10
        ps.headIndent = indent
        ps.firstLineHeadIndent = indent
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private static func headingAttrs(level: Int, style: ReaderStyle) -> [NSAttributedString.Key: Any] {
        let font = NSFont.systemFont(ofSize: style.headingPointSize(level), weight: .semibold)
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.15
        ps.paragraphSpacing = 8
        ps.paragraphSpacingBefore = level == 1 ? 8 : 16
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private static func monoAttrs(style: ReaderStyle) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.25
        ps.paragraphSpacing = 8
        return [
            .font: NSFont.monospacedSystemFont(ofSize: style.bodyPointSize - 2, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }
}
