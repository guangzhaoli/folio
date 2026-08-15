import Foundation

struct BlockID: Hashable, Sendable {
    var kindTag: UInt8
    var startLine: Int
    var startColumn: Int
}

struct SourceSpan: Sendable {
    var startLine: Int
    var startColumn: Int
    var endLine: Int
    var endColumn: Int
    var utf16Range: NSRange
}

enum BlockKind: Sendable {
    case heading(level: Int)
    case paragraph
    case list(ordered: Bool)
    case item(checked: Bool?)
    case codeBlock(language: String)
    case blockQuote
    case thematicBreak
    case table
    case tableRow(isHeader: Bool)
    case tableCell
    case html
    case footnoteDefinition
}

enum InlineNode: Sendable {
    case text(String)
    case strong([InlineNode])
    case emphasis([InlineNode])
    case strikethrough([InlineNode])
    case code(String)
    case link(destination: String, children: [InlineNode])
    case image(destination: String, alt: String)
    case lineBreak
    case softBreak
    case html(String)
    case footnoteReference(String)
}

struct BlockNode: Sendable, Identifiable {
    var id: BlockID
    var kind: BlockKind
    var source: SourceSpan
    var children: [BlockNode]
    var inlines: [InlineNode]
}

struct OutlineItem: Sendable, Identifiable {
    var id: BlockID
    var level: Int
    var title: String
    var span: SourceSpan
}

struct ParseSnapshot: Sendable {
    var generation: UInt64
    var nodes: [BlockNode]
    var outline: [OutlineItem]
    var sourceMap: SourceMap

    static let empty = ParseSnapshot(
        generation: 0,
        nodes: [],
        outline: [],
        sourceMap: SourceMap(lineStartsUTF16: [0], original: "")
    )
}
