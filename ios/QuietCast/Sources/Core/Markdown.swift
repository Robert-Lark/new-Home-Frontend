import SwiftUI

// Port of renderMarkdown (ugc.md §5) — the deliberately-tiny subset used ONLY for posts.body_md.
// iOS operates on RAW text (no HTML escaping): the web escapes first then matches, but the
// divergence notes (ugc.md §5 "iOS divergence notes") confirm raw-text equivalents:
//   blockquote test = line starts with ">"; marker strip = /^>\s?/.
// Block order is the contract: bullets → blockquote → "## " h3 → "# " h2 → paragraph.
// Inline order is the contract: links → bold → italic (so ***x*** => em(strong(x))).

enum MarkdownBlock: Identifiable {
    case heading2(AttributedString)
    case heading3(AttributedString)
    case paragraph([AttributedString])   // lines, joined by <br> on web
    case bullets([AttributedString])
    case quote([AttributedString])        // lines, joined by <br> on web

    var id: String {
        switch self {
        case .heading2(let s): return "h2:\(s.characters.count):\(String(s.characters.prefix(12)))"
        case .heading3(let s): return "h3:\(s.characters.count):\(String(s.characters.prefix(12)))"
        case .paragraph(let l): return "p:\(l.count):\(l.first.map { String($0.characters.prefix(12)) } ?? "")"
        case .bullets(let l): return "ul:\(l.count):\(l.first.map { String($0.characters.prefix(12)) } ?? "")"
        case .quote(let l): return "bq:\(l.count):\(l.first.map { String($0.characters.prefix(12)) } ?? "")"
        }
    }
}

enum Markdown {
    static func parse(_ md: String) -> [MarkdownBlock] {
        let normalized = md.replacingOccurrences(of: "\r\n", with: "\n")
        let rawBlocks = normalized.components(separatedBy: try! NSRegularExpression(pattern: "\\n{2,}"))
        var out: [MarkdownBlock] = []

        for block in rawBlocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { $0.trimmingCharacters(in: .whitespaces) != "" }
            if lines.isEmpty { continue }

            if lines.allSatisfy({ $0.hasPrefix("- ") }) {
                out.append(.bullets(lines.map { inline(String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces)) }))
            } else if lines.allSatisfy({ $0.hasPrefix(">") }) {
                let quoted = lines.map { line -> AttributedString in
                    let stripped = line.replacingOccurrences(of: "^>\\s?", with: "", options: .regularExpression)
                    return inline(stripped.trimmingCharacters(in: .whitespaces))
                }
                out.append(.quote(quoted))
            } else if lines.count == 1 && lines[0].hasPrefix("## ") {
                out.append(.heading3(inline(String(lines[0].dropFirst(3)).trimmingCharacters(in: .whitespaces))))
            } else if lines.count == 1 && lines[0].hasPrefix("# ") {
                out.append(.heading2(inline(String(lines[0].dropFirst(2)).trimmingCharacters(in: .whitespaces))))
            } else {
                out.append(.paragraph(lines.map { inline($0) }))
            }
        }
        return out
    }

    // MARK: - Inline (links → bold → italic)

    private static let linkRE = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\((https?://[^\\s)]+)\\)")

    static func inline(_ s: String) -> AttributedString {
        var result = AttributedString()
        let ns = s as NSString
        var cursor = 0
        let matches = linkRE.matches(in: s, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if m.range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                result.append(emphasize(plain))
            }
            let text = ns.substring(with: m.range(at: 1))
            let href = ns.substring(with: m.range(at: 2))
            var linkPart = emphasize(text)
            if let url = URL(string: href) { linkPart.link = url }
            // foregroundColor left unset so the link uses the view's tint (ember).
            result.append(linkPart)
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result.append(emphasize(ns.substring(from: cursor)))
        }
        return result
    }

    /// Bold then italic, faithful to the two sequential regex passes (ugc.md §5 inline rules).
    private static func emphasize(_ s: String) -> AttributedString {
        // Pass 1: bold — wrap /\*\*([^*]+)\*\*/ content, consuming the ** delimiters.
        let (s2, boldFlags) = applyDelimiter(s, pattern: "\\*\\*([^*]+)\\*\\*", priorFlags: Array(repeating: false, count: s.count))
        // Pass 2: italic — over the bold-stripped text, wrap /\*([^*]+)\*/ content.
        let (s3, italicFlags, carriedBold) = applyDelimiterCarrying(s2, pattern: "\\*([^*]+)\\*", carry: boldFlags)

        var out = AttributedString()
        let chars = Array(s3)
        var i = 0
        while i < chars.count {
            let b = i < carriedBold.count ? carriedBold[i] : false
            let it = i < italicFlags.count ? italicFlags[i] : false
            var j = i
            while j < chars.count,
                  (j < carriedBold.count ? carriedBold[j] : false) == b,
                  (j < italicFlags.count ? italicFlags[j] : false) == it {
                j += 1
            }
            var run = AttributedString(String(chars[i..<j]))
            run.inlinePresentationIntent = intent(bold: b, italic: it)
            out.append(run)
            i = j
        }
        return out
    }

    private static func intent(bold: Bool, italic: Bool) -> InlinePresentationIntent? {
        switch (bold, italic) {
        case (true, true): return [.stronglyEmphasized, .emphasized]
        case (true, false): return .stronglyEmphasized
        case (false, true): return .emphasized
        default: return nil
        }
    }

    /// Find non-overlapping matches of `pattern` (group 1 = content). Returns the string with
    /// delimiters removed and a per-character flag array marking matched content.
    private static func applyDelimiter(_ s: String, pattern: String, priorFlags: [Bool]) -> (String, [Bool]) {
        let re = try! NSRegularExpression(pattern: pattern)
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (s, priorFlags) }

        var resultChars: [Character] = []
        var flags: [Bool] = []
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                for c in plain { resultChars.append(c); flags.append(false) }
            }
            let content = ns.substring(with: m.range(at: 1))
            for c in content { resultChars.append(c); flags.append(true) }
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            for c in ns.substring(from: cursor) { resultChars.append(c); flags.append(false) }
        }
        return (String(resultChars), flags)
    }

    /// Like applyDelimiter but carries an existing flag array (bold) through delimiter removal,
    /// and returns the new (italic) flags too.
    private static func applyDelimiterCarrying(_ s: String, pattern: String, carry: [Bool]) -> (String, [Bool], [Bool]) {
        let re = try! NSRegularExpression(pattern: pattern)
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        let srcChars = Array(s)
        guard !matches.isEmpty else { return (s, Array(repeating: false, count: srcChars.count), carry) }

        var resultChars: [Character] = []
        var italic: [Bool] = []
        var carried: [Bool] = []
        var cursor = 0
        func appendRange(_ start: Int, _ end: Int, italicFlag: Bool) {
            var k = start
            while k < end {
                resultChars.append(srcChars[k])
                italic.append(italicFlag)
                carried.append(k < carry.count ? carry[k] : false)
                k += 1
            }
        }
        for m in matches {
            if m.range.location > cursor { appendRange(cursor, m.range.location, italicFlag: false) }
            let g = m.range(at: 1)
            appendRange(g.location, g.location + g.length, italicFlag: true)
            cursor = m.range.location + m.range.length
        }
        if cursor < srcChars.count { appendRange(cursor, srcChars.count, italicFlag: false) }
        return (String(resultChars), italic, carried)
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let ns = self as NSString
        var result: [String] = []
        var last = 0
        for m in regex.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            result.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        result.append(ns.substring(from: last))
        return result
    }
}
