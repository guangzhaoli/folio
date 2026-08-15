import Foundation

final class Workspace {
    let rootURL: URL
    let root: FileNode
    private var remainingBudget: Int

    init(root url: URL) {
        rootURL = url.standardizedFileURL
        remainingBudget = FileWalker.treeLimit
        root = FileNode(url: rootURL, isDirectory: true, isMarkdown: false)
        root.children = FileWalker.children(of: rootURL, budget: &remainingBudget)
    }

    func expand(_ node: FileNode) -> [FileNode] {
        if let children = node.children { return children }
        guard node.isDirectory else { return [] }
        let children = FileWalker.children(of: node.url, budget: &remainingBudget)
        node.children = children
        return children
    }

    func firstMarkdown() -> URL? {
        func walk(_ node: FileNode) -> URL? {
            if node.isMarkdown { return node.url }
            let children = expand(node).filter { !$0.isTruncated }
            if let file = children.first(where: \.isMarkdown) { return file.url }
            for child in children where child.isDirectory {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(root)
    }

    func containsMarkdown() -> Bool {
        firstMarkdown() != nil
    }

    func markdownFiles() -> [URL] {
        var result: [URL] = []
        func walk(_ node: FileNode) {
            if node.isMarkdown { result.append(node.url) }
            for child in expand(node) where !child.isTruncated { walk(child) }
        }
        walk(root)
        return result
    }

    func nextMarkdown(after url: URL) -> URL? {
        neighbor(of: url, delta: 1)
    }

    func previousMarkdown(before url: URL) -> URL? {
        neighbor(of: url, delta: -1)
    }

    private func neighbor(of url: URL, delta: Int) -> URL? {
        let files = markdownFiles()
        guard let index = files.firstIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) else {
            return files.first
        }
        let next = index + delta
        guard files.indices.contains(next) else { return nil }
        return files[next]
    }
}
