import Foundation

final class FileNode: NSObject {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isMarkdown: Bool
    var isTruncated = false
    var children: [FileNode]?

    init(url: URL, isDirectory: Bool, isMarkdown: Bool) {
        self.url = url.standardizedFileURL
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.isMarkdown = isMarkdown
    }
}

enum FileWalker {
    static let skippedDirectories: Set<String> = [
        ".git", ".svn", ".hg", ".jj", "node_modules", ".build", ".swiftpm",
        "deriveddata", "pods", ".venv", "venv", "__pycache__", ".obsidian",
        ".trash", "carthage", "build", "dist", ".gradle",
    ]
    static let perDirectoryLimit = 2000
    static let treeLimit = 10_000

    static func isMarkdown(_ url: URL) -> Bool {
        FolioDocumentController.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func shouldSkip(_ name: String, isDirectory: Bool) -> Bool {
        if name.hasPrefix(".") { return true }
        if isDirectory, skippedDirectories.contains(name.lowercased()) {
            return true
        }
        return false
    }

    static func children(of directory: URL, budget: inout Int) -> [FileNode] {
        guard budget > 0 else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var nodes: [FileNode] = []
        var truncated = false
        for url in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if nodes.count >= perDirectoryLimit {
                truncated = true
                break
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory == true
            if shouldSkip(url.lastPathComponent, isDirectory: isDirectory) { continue }
            if !isDirectory, !isMarkdown(url) { continue }
            if budget <= 0 {
                truncated = true
                break
            }
            budget -= 1
            let node = FileNode(url: url, isDirectory: isDirectory, isMarkdown: !isDirectory)
            if isDirectory {
                node.children = nil
            }
            nodes.append(node)
        }
        if truncated {
            nodes.append(truncationMarker(in: directory))
        }
        return nodes
    }

    static func truncationMarker(in directory: URL) -> FileNode {
        let node = FileNode(
            url: directory.appendingPathComponent("truncated"),
            isDirectory: false,
            isMarkdown: false
        )
        node.isTruncated = true
        return node
    }
}
