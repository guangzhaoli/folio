import Foundation
import UniformTypeIdentifiers

enum ResolvedLink: Equatable {
    case remote(URL)
    case mail(URL)
    case localFile(URL, fragment: String?)
    case fragmentOnly(String)
    case invalid
}

enum PathResolver {
    static let destinationKey = NSAttributedString.Key("folio.destination")

    static func resolve(destination: String, baseDirectory: URL?) -> ResolvedLink {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .invalid }

        if trimmed.hasPrefix("#") {
            let fragment = String(trimmed.dropFirst())
            return fragment.isEmpty ? .invalid : .fragmentOnly(fragment)
        }

        let (pathPart, fragment) = splitFragment(trimmed)
        let scheme = schemePrefix(pathPart)

        if scheme == "http" || scheme == "https" {
            return URL(string: pathPart).map { .remote($0) } ?? .invalid
        }
        if scheme == "mailto" {
            return URL(string: pathPart).map { .mail($0) } ?? .invalid
        }
        if scheme == "javascript" || scheme == "data" {
            return .invalid
        }
        if scheme == "file" {
            guard let url = URL(string: pathPart) else { return .invalid }
            return .localFile(url.standardizedFileURL, fragment: fragment)
        }

        guard let baseDirectory else { return .invalid }
        let decoded = pathPart.removingPercentEncoding ?? pathPart
        if decoded.hasPrefix("/") {
            return .localFile(URL(fileURLWithPath: decoded).standardizedFileURL, fragment: fragment)
        }
        return .localFile(join(relative: decoded, to: baseDirectory), fragment: fragment)
    }

    static func isMarkdown(_ url: URL) -> Bool {
        FolioDocumentController.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func isInside(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }

    static func isAllowlistedLocal(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        guard let type = values?.contentType else {
            return isMarkdown(url)
        }
        let allowed: [UTType] = [
            .image, .pdf, .plainText, .html, .movie, .audio, .text,
        ]
        if allowed.contains(where: { type.conforms(to: $0) }) { return true }
        if let markdown = UTType("net.daringfireball.markdown"), type.conforms(to: markdown) { return true }
        if let folio = UTType("org.folio.markdown"), type.conforms(to: folio) { return true }
        return isMarkdown(url)
    }

    private static func splitFragment(_ raw: String) -> (String, String?) {
        guard let hash = raw.firstIndex(of: "#"), hash != raw.startIndex else {
            return (raw, nil)
        }
        let path = String(raw[..<hash])
        let fragment = String(raw[raw.index(after: hash)...])
        return (path, fragment.isEmpty ? nil : fragment)
    }

    private static func schemePrefix(_ raw: String) -> String? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = raw[..<colon]
        guard scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }),
              !scheme.isEmpty
        else { return nil }
        return scheme.lowercased()
    }

    private static func join(relative: String, to base: URL) -> URL {
        var url = base.standardizedFileURL
        if url.pathExtension.isEmpty == false {
            url.deleteLastPathComponent()
        }
        for segment in relative.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == "." { continue }
            if segment == ".." {
                url.deleteLastPathComponent()
                continue
            }
            url.appendPathComponent(String(segment))
        }
        return url.standardizedFileURL
    }
}

extension OutlineItem {
    static func matching(fragment: String, in items: [OutlineItem]) -> OutlineItem? {
        let needle = slug(fragment)
        if let exact = items.first(where: { slug($0.title) == needle }) { return exact }
        return items.first { $0.title.compare(fragment, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    static func slug(_ text: String) -> String {
        let scalars = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars
        var pieces: [String] = []
        var current = ""
        for scalar in scalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(Character(scalar))
            } else if !current.isEmpty {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.joined(separator: "-")
    }
}