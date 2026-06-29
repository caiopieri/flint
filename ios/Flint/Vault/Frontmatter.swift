// Frontmatter — pure tag extraction from Markdown YAML frontmatter + inline #tags.
//
// Known limitation: #tag inside fenced code blocks or inline code spans is not
// filtered out. Accepted for v1; a note full of code may show spurious tags.
import Foundation

enum Frontmatter {
    private static let maxBodyChars = 512 * 1024
    private static let maxFrontmatterLines = 60
    private static let maxTags = 100

    /// Extracts all tags from `body` (frontmatter `tags:` / `tag:` + inline `#tag`).
    /// Returns deduplicated (case-insensitive), alphabetically sorted tags.
    /// Never crashes on malformed input; returns best-effort results or `[]`.
    static func tags(in body: String) -> [String] {
        let safe = body.count > maxBodyChars ? String(body.prefix(maxBodyChars)) : body
        let collected = frontmatterTags(safe) + inlineTags(safe)
        var seen: [String: String] = [:]
        for tag in collected {
            let key = tag.lowercased()
            if seen[key] == nil { seen[key] = tag }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Frontmatter

    private static func frontmatterTags(_ body: String) -> [String] {
        guard body.hasPrefix("---\n") || body.hasPrefix("---\r\n") else { return [] }
        let lines = body.components(separatedBy: .newlines)
        var end = -1
        for (i, line) in lines.dropFirst().prefix(maxFrontmatterLines).enumerated() {
            if line == "---" || line == "..." { end = i + 1; break }
        }
        guard end > 0 else { return [] }

        var inTagsBlock = false
        var raw: [String] = []

        for line in lines[1..<end] {
            if let val = keyValue("tags", line) ?? keyValue("tag", line) {
                inTagsBlock = false
                if val.hasPrefix("[") {
                    raw += parseFlow(val)
                } else if val.isEmpty {
                    inTagsBlock = true
                } else {
                    raw += parseScalar(val)
                }
            } else if inTagsBlock {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    let t = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { raw.append(t) }
                } else if trimmed.count > 1 && trimmed.hasPrefix("-") {
                    let t = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { raw.append(t) }
                } else {
                    inTagsBlock = false
                }
            }
        }

        return raw.filter { !$0.isEmpty }.prefix(maxTags).map(normalizeTag)
    }

    private static func keyValue(_ key: String, _ line: String) -> String? {
        let prefix = "\(key): "
        if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        if line == "\(key):" { return "" }
        return nil
    }

    private static func parseFlow(_ val: String) -> [String] {
        var s = val.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") { s = String(s.dropFirst()) }
        if s.hasSuffix("]") { s = String(s.dropLast()) }
        return s.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }

    private static func parseScalar(_ val: String) -> [String] {
        val.components(separatedBy: CharacterSet(charactersIn: ", "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeTag(_ tag: String) -> String {
        var t = tag
        while t.hasPrefix("#") { t = String(t.dropFirst()) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Inline #tags

    // Mirrors livePreview.ts §Tag: # preceded by non-tagBody (or start), followed by
    // one or more tagBody chars that contain at least one non-digit.
    private static func inlineTags(_ body: String) -> [String] {
        var tags: [String] = []
        let scalars = body.unicodeScalars
        var idx = scalars.startIndex

        while idx < scalars.endIndex {
            guard scalars[idx].value == 35 else {   // '#'
                idx = scalars.index(after: idx)
                continue
            }

            let beforeOk: Bool
            if idx == scalars.startIndex {
                beforeOk = true
            } else {
                beforeOk = !isTagBody(scalars[scalars.index(before: idx)].value)
            }

            guard beforeOk else {
                idx = scalars.index(after: idx)
                continue
            }

            let bodyStart = scalars.index(after: idx)
            var j = bodyStart
            var hasLetter = false
            while j < scalars.endIndex && isTagBody(scalars[j].value) {
                if !(scalars[j].value >= 48 && scalars[j].value <= 57) { hasLetter = true }
                j = scalars.index(after: j)
            }

            if j > bodyStart && hasLetter {
                tags.append(String(String.UnicodeScalarView(scalars[bodyStart..<j])))
                if tags.count >= maxTags { return tags }
            }
            idx = j
        }
        return tags
    }

    // Matches livePreview.ts isTagBody: A-Z (65-90), a-z (97-122), 0-9 (48-57), - (45), _ (95), / (47)
    private static func isTagBody(_ c: UInt32) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) || c == 45 || c == 95 || c == 47
    }
}
