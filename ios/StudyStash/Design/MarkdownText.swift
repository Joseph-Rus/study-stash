import SwiftUI
import UIKit

/// Markdown from the AI (an Ask answer, Canvas instructions) in the notes' type, as the desktop's answers read:
/// headings, lists, quotes, tables, code and formulas as blocks; bold, italics, code and links inline; maths as plain
/// characters (∫ u dv = uv − ∫ v du). Ink on the page; bullets and numbers in the subtle ink. Code is the app's own
/// type on the wash, never a system monospace. A diagram (a Mermaid chart, a drawing, a plot) isn't drawn here: a line
/// says the computer shows it. `caret`: the text is still being written, with a caret at its end.
struct MarkdownText: View {
    var text: String
    var style: AppText = .body
    var caret = false
    @ScaledMetric private var caretHeight: CGFloat

    init(_ text: String, style: AppText = .body, caret: Bool = false) {
        self.text = text
        self.style = style
        self.caret = caret
        _caretHeight = ScaledMetric(wrappedValue: style.spec.size * 1.1, relativeTo: style.spec.relativeTo)
    }

    var body: some View {
        let blocks = Self.blocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                let end = caret && i == blocks.count - 1
                switch block {
                case .heading(let s):
                    line(s, end).textStyle(.title).padding(.top, i == 0 ? 0 : 6).accessibilityAddTraits(.isHeader)
                case .bullet(let s, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundStyle(.inkSubtle)
                        line(s, end).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4 + CGFloat(depth) * 18)
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(.inkSubtle).monospacedDigit()
                        line(s, end).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 2)
                case .paragraph(let s):
                    line(s, end).fixedSize(horizontal: false, vertical: true)
                case .quote(let s):
                    HStack(alignment: .top, spacing: 12) {
                        Rectangle().fill(.line).frame(width: 2)
                        line(s, end).foregroundStyle(.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .code(let s):
                    VStack(alignment: .leading, spacing: 6) {
                        Wash { Text(s).textStyle(.summary).foregroundStyle(.ink).fixedSize() }
                        if end { caretView }
                    }
                case .math(let tex):
                    VStack(alignment: .leading, spacing: 6) {
                        // On its own line; a long one scrolls sideways (where it isn't cut off at its ends).
                        let f = Text(Self.formula(tex)).textStyle(.lede).foregroundStyle(.ink).fixedSize().padding(.vertical, 4)
                        ViewThatFits(in: .horizontal) {
                            f
                            ScrollView(.horizontal, showsIndicators: false) { f.padding(.horizontal, 8) }.padding(.horizontal, -8)
                        }
                        .accessibilityLabel(Self.formula(tex))
                        if end { caretView }
                    }
                case .table(let rows):
                    VStack(alignment: .leading, spacing: 6) {
                        table(rows)
                        if end { caretView }
                    }
                case .rule:
                    Rule().padding(.vertical, 4)
                case .diagram:
                    VStack(alignment: .leading, spacing: 6) {
                        Wash {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Icon("hub", size: 15, relativeTo: .subheadline).foregroundStyle(.inkSubtle)
                                Text("There's a diagram here. Syft Notes on your computer shows it.")
                                    .textStyle(.summary).foregroundStyle(.inkMuted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if end { caretView }
                    }
                }
            }
            if caret && blocks.isEmpty { caretView }
        }
        .textStyle(style)
        .foregroundStyle(.ink)
        .textSelection(.enabled)
    }

    /// A line of inline Markdown, with the caret after it when the text ends there.
    private func line(_ s: String, _ end: Bool) -> Text {
        let t = Text(Self.inline(s))
        guard end else { return t }
        return Text("\(t)\u{2060}\(Text(Image(uiImage: Self.caretImage(height: caretHeight))).baselineOffset(-caretHeight * 0.2))")
    }

    private var caretView: some View {
        WritingCaret(blinks: false)
    }

    /// A table: its header bold, hairlines between rows. Three columns or fewer wrap to the page's width; a wider one
    /// scrolls sideways.
    @ViewBuilder private func table(_ rows: [[String]]) -> some View {
        let width = rows.map(\.count).max() ?? 0
        // Short row names keep to one line, so a word like "Stereochemistry" isn't broken.
        let shortNames = rows.allSatisfy { ($0.first ?? "").count <= 18 }
        let grid = Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, cells in
                if r > 0 { Rule() }
                GridRow {
                    ForEach(0..<width, id: \.self) { c in
                        Text(Self.inline(c < cells.count ? cells[c] : ""))
                            .textStyle(.summary)
                            .fontWeight(r == 0 || (c == 0 && shortNames) ? .semibold : nil)
                            .frame(maxWidth: width > 3 ? 240 : .infinity, alignment: .leading)
                            .fixedSize(horizontal: c == 0 && shortNames, vertical: true)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        if width <= 3 {
            grid
        } else {
            ScrollView(.horizontal, showsIndicators: false) { grid }
        }
    }

    /// A block on the wash: code, a diagram's line.
    private struct Wash<Content: View>: View {
        @ViewBuilder var content: Content
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                content.padding(.horizontal, 14).padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surfaceSunken, in: .rect(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(.line))
        }
    }

    /// A formula on its own line in plain characters, its spacing commands as spaces.
    static func formula(_ tex: String) -> String {
        var t = tex
        for (cmd, space) in [("\\,", "\u{2009}"), ("\\;", " "), ("\\:", " "), ("\\!", ""), ("\\quad", "  "), ("\\qquad", "    ")] {
            t = t.replacingOccurrences(of: cmd, with: space)
        }
        return PlainMath.plain(t)
    }

    // MARK: inline

    private final class Parsed: @unchecked Sendable {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    /// Inline Markdown already read: an answer being written draws each finished paragraph many times a second.
    nonisolated(unsafe) private static let parsed: NSCache<NSString, Parsed> = {
        let c = NSCache<NSString, Parsed>()
        c.countLimit = 400
        return c
    }()

    /// Bold, italics, code and links, with maths as plain characters.
    static func inline(_ s: String) -> AttributedString {
        if let hit = parsed.object(forKey: s as NSString) { return hit.value }
        var a = (try? AttributedString(markdown: PlainMath.inline(s), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        // Code in the app's own type on the wash, never a system monospace.
        let code = a.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for r in code {
            a[r].inlinePresentationIntent?.remove(.code)
            a[r].backgroundColor = .hover
        }
        parsed.setObject(Parsed(a), forKey: s as NSString)
        return a
    }

    /// The caret drawn in the text's own colour (a template), two points wide.
    private static func caretImage(height: CGFloat) -> UIImage {
        let size = CGSize(width: 2, height: max(8, height.rounded()))
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.black.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1).fill()
        }.withRenderingMode(.alwaysTemplate)
    }

    // MARK: blocks

    enum Block {
        case heading(String), bullet(String, Int), numbered(Int, String), paragraph(String)
        case quote(String), code(String), math(String), table([[String]]), rule, diagram
    }

    nonisolated static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var quote: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: " "))); quote = [] }
        }
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            // A fenced block: code, or a diagram (written to its end, or as far as it's come).
            if let fence = line.wholeMatch(of: /(`{3,}|~{3,})\s*([^`]*)/) {
                flush()
                let mark = String(fence.1)
                let info = String(fence.2).trimmingCharacters(in: .whitespaces).lowercased()
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(mark) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1
                let code = body.joined(separator: "\n")
                if isDiagram(info: info, code) {
                    out.append(.diagram)
                } else if ["math", "latex", "tex"].contains(info) {
                    out.append(.math(code))
                } else {
                    out.append(.code(code))
                }
                continue
            }
            // A formula on lines of its own: $$ … $$ or \[ … \].
            if line.hasPrefix("$$") || line.hasPrefix("\\[") {
                flush()
                let close = line.hasPrefix("$$") ? "$$" : "\\]"
                let rest = String(line.dropFirst(2))
                if let r = rest.range(of: close) {
                    out.append(.math(String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)))
                    i += 1
                    continue
                }
                var body = [rest]
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    i += 1
                    if let r = l.range(of: close) { body.append(String(l[..<r.lowerBound])); break }
                    body.append(l)
                }
                out.append(.math(body.joined(separator: " ").trimmingCharacters(in: .whitespaces)))
                continue
            }
            // A table: a row of cells, then a row of dashes under it.
            if line.hasPrefix("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).wholeMatch(of: /\|?(\s*:?-{2,}:?\s*\|)+\s*(:?-{2,}:?\s*)?/) != nil {
                flush()
                var rows = [cells(line)]
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                out.append(.table(rows))
                continue
            }
            i += 1
            if line.isEmpty { flush(); continue }
            if line.wholeMatch(of: /(-[ \t]*){3,}|(\*[ \t]*){3,}|(_[ \t]*){3,}/) != nil { flush(); out.append(.rule); continue }
            if let m = line.firstMatch(of: /^>\s?(.*)$/) {
                if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
                quote.append(String(m.1))
                continue
            }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: " "))); quote = [] }
            if let m = line.firstMatch(of: /^#{1,6}\s+(.*)$/) { flush(); out.append(.heading(String(m.1))) }
            else if let m = line.firstMatch(of: /^[-*•+]\s+(.*)$/) { flush(); out.append(.bullet(String(m.1), indent / 2)) }
            else if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) { flush(); out.append(.numbered(Int(m.1) ?? 1, String(m.2))) }
            else { para.append(line) }
        }
        flush()
        return out
    }

    /// A table row's cells, without the bars round them.
    private nonisolated static func cells(_ line: String) -> [String] {
        var s = Substring(line)
        if s.hasPrefix("|") { s = s.dropFirst() }
        if s.hasSuffix("|") { s = s.dropLast() }
        return s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A fenced block that holds a diagram, as the desktop reads them (NoteBlocks): ```mermaid, ```svg, ```plot, an
    /// SVG in ```xml or ```html, or a bare fence that starts like a flowchart.
    private nonisolated static func isDiagram(info: String, _ code: String) -> Bool {
        let kind = info.split(separator: " ").first.map(String.init) ?? ""
        if ["mermaid", "mmd", "svg", "plot"].contains(kind) { return true }
        let start = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["xml", "html", ""].contains(kind), start.hasPrefix("<svg") { return true }
        if kind.isEmpty, ["graph ", "flowchart", "sequencediagram", "classdiagram", "statediagram"].contains(where: start.hasPrefix) { return true }
        return false
    }

    // MARK: while it's written, and copied

    /// The text so far as it can be shown while it's still being written: what's finished reads as it will in the
    /// end, and what's half written doesn't flash its raw source (a formula still open, `**` not yet closed).
    nonisolated static func showable(_ text: String) -> String {
        var t = text
        // A $$ formula still open at the end waits until it's whole.
        if t.components(separatedBy: "$$").count % 2 == 0, let r = t.range(of: "$$", options: .backwards) { t = String(t[..<r.lowerBound]) }
        // Inside a fence that's still open, everything shows as it comes.
        let fences = t.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count
        if fences % 2 == 1 { return t }
        let start = t.range(of: "\n\n", options: .backwards)?.upperBound ?? t.startIndex
        var last = t[start...]
        // An inline formula not yet closed (not one that's just a price).
        var dollars: [Substring.Index] = []
        var j = last.startIndex
        while j < last.endIndex {
            let next = last.index(after: j)
            if last[j] == "\\" {
                j = next < last.endIndex ? last.index(after: next) : next
                continue
            }
            if last[j] == "$" {
                if next < last.endIndex, last[next] == "$" { j = last.index(after: next); continue }
                dollars.append(j)
            }
            j = next
        }
        if dollars.count % 2 == 1, let open = dollars.last, last.distance(from: open, to: last.endIndex) <= 300 { last = last[..<open] }
        // Bold or code not yet closed.
        for mark in ["**", "`"] {
            let parts = last.components(separatedBy: mark)
            if parts.count % 2 == 0, let r = last.range(of: mark, options: .backwards) { last = last[..<r.lowerBound] }
        }
        return String(t[..<start]) + last
    }

    /// The text as words alone, for Copy: no Markdown marks, maths as plain characters, a list's bullets and numbers
    /// kept.
    static func plain(_ text: String) -> String {
        func words(_ s: String) -> String { String(inline(s).characters) }
        var out: [String] = []
        var list: [String] = []
        func endList() { if !list.isEmpty { out.append(list.joined(separator: "\n")); list = [] } }
        for b in blocks(text) {
            switch b {
            case .bullet(let s, let depth): list.append(String(repeating: "  ", count: depth) + "• " + words(s))
            case .numbered(let n, let s): list.append("\(n). " + words(s))
            default:
                endList()
                switch b {
                case .heading(let s), .paragraph(let s), .quote(let s): out.append(words(s))
                case .code(let s): out.append(s)
                case .math(let tex): out.append(PlainMath.plain(tex))
                case .table(let rows): out.append(rows.map { $0.map(words).joined(separator: "\t") }.joined(separator: "\n"))
                case .rule, .diagram, .bullet, .numbered: break
                }
            }
        }
        endList()
        return out.joined(separator: "\n\n")
    }
}

/// The caret where an answer is about to be written: an ink bar, blinking as a text caret does while nothing is
/// arriving (`blinks`; it dims rather than goes, so it's always there to see), steady with Reduce Motion.
struct WritingCaret: View {
    var blinks = true
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.ink)
            .frame(width: 2, height: height)
            .opacity(on ? 1 : 0.2)
            .task {
                guard blinks, !still else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    on.toggle()
                }
            }
            .accessibilityHidden(true)
    }
}
