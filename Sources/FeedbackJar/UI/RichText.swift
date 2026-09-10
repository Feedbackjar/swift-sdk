#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Dependency-free renderer for the subset of Markdown feedback posts and
/// comments use, plus FeedbackJar mention tokens:
///
/// - `#[Post title](postId)`                    -> post reference chip (tappable)
/// - `@[Name](user:id | guest:id | post:id)`    -> user mention
/// - **bold**, *italic*, `code`, [links](url), bare URLs
/// - headings, `-`/`1.` lists, `>` quotes, ``` fenced code
///
/// Single newlines are hard breaks (matches the web renderer's `remark-breaks`).

// MARK: - Parser model

enum FJInline {
    case text(String)
    case strong([FJInline])
    case em([FJInline])
    case code(String)
    case link(href: String, children: [FJInline])
    case postMention(title: String, postId: String)
    case userMention(name: String)
}

enum FJBlock {
    case paragraph([FJInline])
    case heading(level: Int, [FJInline])
    case bulletList([[FJInline]])
    case orderedList([[FJInline]])
    case quote([FJInline])
    case codeBlock(String)
}

private func re(_ pattern: String) -> NSRegularExpression {
    // Patterns are compile-time constants; a bad one is a programmer error.
    // swiftlint:disable:next force_try
    try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
}

private let rPostMention = re(#"^#\[([^\]]+)\]\(([^)]+)\)"#)
private let rUserMention = re(#"^@\[([^\]]+)\]\((?:user|guest|post):([^)]+)\)"#)
private let rCodeSpan = re(#"^(`+)(.+?)\1"#)
private let rLink = re(#"^\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
private let rStrong = re(#"^(\*\*|__)(.+?)\1"#)
private let rEm = re(#"^(\*|_)(\S(?:.*?\S)?|\S)\1"#)
private let rAutolink = re(#"^(https?://[^\s<]+[^\s<.,:;"'!?)\]])"#)

private func firstMatch(_ regex: NSRegularExpression, _ s: String) -> [String]? {
    let range = NSRange(s.startIndex..., in: s)
    guard let m = regex.firstMatch(in: s, options: [.anchored], range: range) else { return nil }
    var groups: [String] = []
    for i in 0..<m.numberOfRanges {
        if let r = Range(m.range(at: i), in: s) {
            groups.append(String(s[r]))
        } else {
            groups.append("")
        }
    }
    return groups
}

private let fjSpecials: Set<Character> = ["`", "#", "@", "[", "*", "_"]

func fjParseInline(_ src: String) -> [FJInline] {
    var out: [FJInline] = []
    var rest = src
    var buf = ""
    func flush() {
        if !buf.isEmpty { out.append(.text(buf)); buf = "" }
    }

    while !rest.isEmpty {
        if let g = firstMatch(rCodeSpan, rest) {
            flush()
            out.append(.code(g[2].trimmingCharacters(in: .whitespaces)))
            rest.removeFirst(g[0].count)
            continue
        }
        if let g = firstMatch(rPostMention, rest) {
            flush()
            out.append(.postMention(
                title: g[1].trimmingCharacters(in: .whitespaces),
                postId: g[2].trimmingCharacters(in: .whitespaces)
            ))
            rest.removeFirst(g[0].count)
            continue
        }
        if let g = firstMatch(rUserMention, rest) {
            flush()
            out.append(.userMention(name: g[1].trimmingCharacters(in: .whitespaces)))
            rest.removeFirst(g[0].count)
            continue
        }
        if let g = firstMatch(rLink, rest) {
            flush()
            out.append(.link(href: g[2], children: fjParseInline(g[1])))
            rest.removeFirst(g[0].count)
            continue
        }
        if let g = firstMatch(rStrong, rest) {
            flush()
            out.append(.strong(fjParseInline(g[2])))
            rest.removeFirst(g[0].count)
            continue
        }
        if let g = firstMatch(rEm, rest) {
            flush()
            out.append(.em(fjParseInline(g[2])))
            rest.removeFirst(g[0].count)
            continue
        }
        if let g = firstMatch(rAutolink, rest) {
            flush()
            out.append(.link(href: g[1], children: [.text(g[1])]))
            rest.removeFirst(g[0].count)
            continue
        }

        // Plain text — always consume the first character, then take up to the
        // next possibly-special one. Consuming char 0 guarantees progress even
        // when a lone `*` / `_` / `#` doesn't form a token.
        buf.append(rest.removeFirst())
        if let special = rest.firstIndex(where: {
            fjSpecials.contains($0) || $0 == "h"
        }) {
            buf.append(contentsOf: rest[rest.startIndex..<special])
            rest = String(rest[special...])
        } else {
            buf.append(rest)
            rest = ""
        }
    }
    flush()
    return out
}

private let rHeading = re(#"^(#{1,6})\s+(.*)$"#)
private let rFence = re(#"^(```|~~~)"#)
private let rQuote = re(#"^>\s?"#)
private let rBullet = re(#"^\s*[-*+]\s+"#)
private let rOrdered = re(#"^\s*\d+[.)]\s+"#)

private func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
    regex.firstMatch(in: s, options: [.anchored], range: NSRange(s.startIndex..., in: s)) != nil
}

private func stripPrefix(_ regex: NSRegularExpression, _ s: String) -> String {
    guard let g = firstMatch(regex, s) else { return s }
    var out = s
    out.removeFirst(g[0].count)
    return out
}

func fjParseBlocks(_ md: String) -> [FJBlock] {
    let lines = md
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
    var blocks: [FJBlock] = []
    var i = 0

    while i < lines.count {
        let line = lines[i]

        if line.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }

        if matches(rFence, line.trimmingCharacters(in: .whitespaces)) {
            i += 1
            var body: [String] = []
            while i < lines.count, !matches(rFence, lines[i].trimmingCharacters(in: .whitespaces)) {
                body.append(lines[i]); i += 1
            }
            i += 1 // closing fence
            blocks.append(.codeBlock(body.joined(separator: "\n")))
            continue
        }

        if let g = firstMatch(rHeading, line) {
            blocks.append(.heading(
                level: g[1].count,
                fjParseInline(g[2].trimmingCharacters(in: .whitespaces))
            ))
            i += 1
            continue
        }

        if matches(rQuote, line) {
            var q: [String] = []
            while i < lines.count, matches(rQuote, lines[i]) {
                q.append(stripPrefix(rQuote, lines[i])); i += 1
            }
            blocks.append(.quote(fjParseInline(q.joined(separator: "\n"))))
            continue
        }

        if matches(rBullet, line) {
            var items: [[FJInline]] = []
            while i < lines.count, matches(rBullet, lines[i]) {
                items.append(fjParseInline(stripPrefix(rBullet, lines[i]))); i += 1
            }
            blocks.append(.bulletList(items))
            continue
        }

        if matches(rOrdered, line) {
            var items: [[FJInline]] = []
            while i < lines.count, matches(rOrdered, lines[i]) {
                items.append(fjParseInline(stripPrefix(rOrdered, lines[i]))); i += 1
            }
            blocks.append(.orderedList(items))
            continue
        }

        var para: [String] = []
        while i < lines.count,
              !lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
              !matches(rHeading, lines[i]),
              !matches(rBullet, lines[i]),
              !matches(rOrdered, lines[i]),
              !matches(rQuote, lines[i]),
              !matches(rFence, lines[i].trimmingCharacters(in: .whitespaces)) {
            para.append(lines[i]); i += 1
        }
        blocks.append(.paragraph(fjParseInline(para.joined(separator: "\n"))))
    }

    return blocks
}

/// Flatten Markdown + mention tokens to readable one-line text (list previews).
public func fjPlainText(_ md: String) -> String {
    func replace(_ pattern: String, _ template: String, _ s: String) -> String {
        let r = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .anchorsMatchLines])
        return r.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template
        )
    }
    var s = md
    s = replace(#"```(.|\n)*?```"#, " ", s)
    s = replace(#"`([^`]+)`"#, "$1", s)
    s = replace(#"#\[([^\]]+)\]\([^)]+\)"#, "$1", s)
    s = replace(#"@\[([^\]]+)\]\((?:user|guest|post):[^)]+\)"#, "$1", s)
    s = replace(#"\[([^\]]+)\]\([^)]+\)"#, "$1", s)
    s = replace(#"(\*\*|__|~~|\*|_)"#, "", s)
    s = replace(#"^\s{0,3}#{1,6}\s+"#, "", s)
    s = replace(#"^\s*[-*+]\s+"#, "", s)
    s = replace(#"^\s*\d+[.)]\s+"#, "", s)
    s = replace(#"^\s*>\s?"#, "", s)
    s = replace(#"\s+"#, " ", s)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - View

private struct FJInlineStyle {
    var bold = false
    var italic = false
    var color: Color?
    var link: URL?
}

/// Render feedback post / comment content with mentions and light Markdown.
public struct FJRichText: View {
    private let content: String
    private let onPostPress: ((String) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.fjAccent) private var accent

    public init(_ content: String, onPostPress: ((String) -> Void)? = nil) {
        self.content = content
        self.onPostPress = onPostPress
    }

    public var body: some View {
        let palette = FJPalette.resolve(scheme, accent: accent)
        let blocks = fjParseBlocks(content)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block, palette)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "feedbackjar", url.host == "post" {
                let id = url.lastPathComponent
                if let onPostPress { onPostPress(id); return .handled }
                return .discarded
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private func blockView(_ block: FJBlock, _ palette: FJPalette) -> some View {
        switch block {
        case .paragraph(let inl):
            Text(attributed(inl, FJInlineStyle(color: palette.text), palette))
                .font(.system(size: FJFont.body))
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let inl):
            Text(attributed(inl, FJInlineStyle(bold: true, color: palette.text), palette))
                .font(.system(size: level <= 1 ? FJFont.body + 2 : FJFont.body, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let inl):
            HStack(spacing: 10) {
                Rectangle().fill(palette.field).frame(width: 2)
                Text(attributed(inl, FJInlineStyle(color: palette.textDim), palette))
                    .font(.system(size: FJFont.body))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .bulletList(let items):
            listView(items.map { _ in "•" }, items, palette)
        case .orderedList(let items):
            listView(items.indices.map { "\($0 + 1)." }, items, palette)
        case .codeBlock(let value):
            Text(value)
                .font(.system(size: FJFont.small, design: .monospaced))
                .foregroundColor(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: fjRadius).fill(palette.field))
        }
    }

    private func listView(_ markers: [String], _ items: [[FJInline]], _ palette: FJPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(markers[idx])
                        .font(.system(size: FJFont.body))
                        .foregroundColor(palette.textDim)
                    Text(attributed(item, FJInlineStyle(color: palette.text), palette))
                        .font(.system(size: FJFont.body))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func attributed(_ nodes: [FJInline], _ style: FJInlineStyle, _ palette: FJPalette) -> AttributedString {
        var result = AttributedString("")
        for node in nodes {
            switch node {
            case .text(let value):
                result += run(value, style)
            case .strong(let children):
                var s = style; s.bold = true
                result += attributed(children, s, palette)
            case .em(let children):
                var s = style; s.italic = true
                result += attributed(children, s, palette)
            case .code(let value):
                var piece = AttributedString(value)
                piece.font = .system(size: FJFont.small, design: .monospaced)
                piece.backgroundColor = palette.field
                result += piece
            case .link(let href, let children):
                var s = style
                s.color = palette.accent
                s.link = URL(string: href)
                result += attributed(children, s, palette)
            case .userMention(let name):
                var s = style
                s.bold = true
                s.color = palette.accent
                result += run("@\(name)", s)
            case .postMention(let title, let postId):
                var piece = AttributedString(" #\(title) ")
                piece.foregroundColor = palette.accent
                piece.backgroundColor = palette.accent.opacity(0.12)
                piece.font = .system(size: FJFont.small, weight: .semibold)
                if onPostPress != nil {
                    piece.link = URL(string: "feedbackjar://post/\(postId)")
                }
                result += piece
            }
        }
        return result
    }

    private func run(_ text: String, _ style: FJInlineStyle) -> AttributedString {
        var piece = AttributedString(text)
        let weight: Font.Weight = style.bold ? .bold : .regular
        var font = Font.system(size: FJFont.body, weight: weight)
        if style.italic { font = font.italic() }
        piece.font = font
        if let color = style.color { piece.foregroundColor = color }
        if let link = style.link { piece.link = link }
        return piece
    }
}
#endif
