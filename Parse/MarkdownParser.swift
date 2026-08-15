import Foundation

enum MarkdownParser {
    static func parse(text: String, generation: UInt64) -> ParseSnapshot {
        cmark_gfm_core_extensions_ensure_registered()
        let options = Int32(CMARK_OPT_SOURCEPOS | CMARK_OPT_VALIDATE_UTF8 | CMARK_OPT_FOOTNOTES)
        guard let parser = cmark_parser_new(options) else {
            return ParseSnapshot.empty
        }
        defer { cmark_parser_free(parser) }

        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        text.withCString { cstr in
            cmark_parser_feed(parser, cstr, strlen(cstr))
        }
        guard let root = cmark_parser_finish(parser) else {
            return ParseSnapshot.empty
        }
        defer { cmark_node_free(root) }

        let map = SourceMap.build(from: text)
        var outline: [OutlineItem] = []
        let nodes = convertChildren(of: root, map: map, outline: &outline)
        return ParseSnapshot(generation: generation, nodes: nodes, outline: outline, sourceMap: map)
    }

    private static func convertChildren(
        of node: OpaquePointer,
        map: SourceMap,
        outline: inout [OutlineItem]
    ) -> [BlockNode] {
        var result: [BlockNode] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            if let block = convertBlock(current, map: map, outline: &outline) {
                result.append(block)
            }
            child = cmark_node_next(current)
        }
        return result
    }

    private static func convertBlock(
        _ node: OpaquePointer,
        map: SourceMap,
        outline: inout [OutlineItem]
    ) -> BlockNode? {
        let type = cmark_node_get_type(node)
        let span = sourceSpan(node, map: map)
        let id = BlockID(kindTag: kindTag(type, node), startLine: span.startLine, startColumn: span.startColumn)
        let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""

        if type == CMARK_NODE_DOCUMENT {
            return nil
        }

        if type == CMARK_NODE_HEADING {
            let level = Int(cmark_node_get_heading_level(node))
            let inlines = convertInlines(node)
            let title = plainText(inlines)
            outline.append(OutlineItem(id: id, level: max(1, min(level, 6)), title: title.isEmpty ? "(empty)" : title, span: span))
            return BlockNode(id: id, kind: .heading(level: level), source: span, children: [], inlines: inlines)
        }
        if type == CMARK_NODE_PARAGRAPH {
            return BlockNode(id: id, kind: .paragraph, source: span, children: [], inlines: convertInlines(node))
        }
        if type == CMARK_NODE_LIST {
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            return BlockNode(id: id, kind: .list(ordered: ordered), source: span, children: convertChildren(of: node, map: map, outline: &outline), inlines: [])
        }
        if type == CMARK_NODE_ITEM {
            let checked: Bool? = cmark_node_get_syntax_extension(node) == nil
                ? nil
                : cmark_gfm_extensions_get_tasklist_item_checked(node)
            return BlockNode(id: id, kind: .item(checked: checked), source: span, children: convertChildren(of: node, map: map, outline: &outline), inlines: convertInlines(node))
        }
        if type == CMARK_NODE_CODE_BLOCK {
            let lang = cmark_node_get_fence_info(node).map { String(cString: $0) } ?? ""
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return BlockNode(id: id, kind: .codeBlock(language: lang), source: span, children: [], inlines: [.text(literal)])
        }
        if type == CMARK_NODE_BLOCK_QUOTE {
            return BlockNode(id: id, kind: .blockQuote, source: span, children: convertChildren(of: node, map: map, outline: &outline), inlines: [])
        }
        if type == CMARK_NODE_THEMATIC_BREAK {
            return BlockNode(id: id, kind: .thematicBreak, source: span, children: [], inlines: [])
        }
        if type == CMARK_NODE_HTML_BLOCK {
            let html = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return BlockNode(id: id, kind: .html, source: span, children: [], inlines: [.html(html)])
        }
        if type == CMARK_NODE_FOOTNOTE_DEFINITION {
            return BlockNode(id: id, kind: .footnoteDefinition, source: span, children: convertChildren(of: node, map: map, outline: &outline), inlines: [])
        }
        if typeString == "table" {
            return BlockNode(id: id, kind: .table, source: span, children: convertChildren(of: node, map: map, outline: &outline), inlines: [])
        }
        if typeString == "table_row" || typeString == "table_header" {
            let header = cmark_gfm_extensions_get_table_row_is_header(node) != 0 || typeString == "table_header"
            return BlockNode(id: id, kind: .tableRow(isHeader: header), source: span, children: convertChildren(of: node, map: map, outline: &outline), inlines: [])
        }
        if typeString == "table_cell" {
            return BlockNode(id: id, kind: .tableCell, source: span, children: [], inlines: convertInlines(node))
        }

        let children = convertChildren(of: node, map: map, outline: &outline)
        if !children.isEmpty {
            return BlockNode(id: id, kind: .paragraph, source: span, children: children, inlines: [])
        }
        return nil
    }

    private static func convertInlines(_ node: OpaquePointer) -> [InlineNode] {
        var result: [InlineNode] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            if let inline = convertInline(current) {
                result.append(inline)
            }
            child = cmark_node_next(current)
        }
        return result
    }

    private static func convertInline(_ node: OpaquePointer) -> InlineNode? {
        let type = cmark_node_get_type(node)
        let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""
        if type == CMARK_NODE_TEXT {
            return .text(cmark_node_get_literal(node).map { String(cString: $0) } ?? "")
        }
        if type == CMARK_NODE_SOFTBREAK { return .softBreak }
        if type == CMARK_NODE_LINEBREAK { return .lineBreak }
        if type == CMARK_NODE_CODE {
            return .code(cmark_node_get_literal(node).map { String(cString: $0) } ?? "")
        }
        if type == CMARK_NODE_HTML_INLINE {
            return .html(cmark_node_get_literal(node).map { String(cString: $0) } ?? "")
        }
        if type == CMARK_NODE_EMPH { return .emphasis(convertInlines(node)) }
        if type == CMARK_NODE_STRONG { return .strong(convertInlines(node)) }
        if type == CMARK_NODE_LINK {
            let dest = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            return .link(destination: dest, children: convertInlines(node))
        }
        if type == CMARK_NODE_IMAGE {
            let dest = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            return .image(destination: dest, alt: plainText(convertInlines(node)))
        }
        if type == CMARK_NODE_FOOTNOTE_REFERENCE {
            let label = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return .footnoteReference(label)
        }
        if typeString == "strikethrough" {
            return .strikethrough(convertInlines(node))
        }
        return nil
    }

    private static func sourceSpan(_ node: OpaquePointer, map: SourceMap) -> SourceSpan {
        var span = SourceSpan(
            startLine: Int(cmark_node_get_start_line(node)),
            startColumn: Int(cmark_node_get_start_column(node)),
            endLine: Int(cmark_node_get_end_line(node)),
            endColumn: Int(cmark_node_get_end_column(node)),
            utf16Range: NSRange(location: NSNotFound, length: 0)
        )
        span.utf16Range = map.utf16Range(span: span)
        return span
    }

    private static func kindTag(_ type: cmark_node_type, _ node: OpaquePointer) -> UInt8 {
        let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""
        if typeString == "table" { return 40 }
        if typeString.contains("row") || typeString.contains("header") { return 41 }
        if typeString.contains("cell") { return 42 }
        return UInt8(truncatingIfNeeded: type.rawValue & 0xFF)
    }

    static func plainText(_ inlines: [InlineNode]) -> String {
        inlines.map { node in
            switch node {
            case .text(let s), .code(let s), .html(let s): return s
            case .strong(let c), .emphasis(let c), .strikethrough(let c), .link(_, let c):
                return plainText(c)
            case .image(_, let alt): return alt
            case .lineBreak, .softBreak: return " "
            case .footnoteReference: return ""
            }
        }.joined()
    }
}
