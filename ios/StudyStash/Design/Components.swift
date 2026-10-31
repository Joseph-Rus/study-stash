import SwiftUI

// The look's own pieces, as the desktop draws them (Styles.axaml, "The look's own pieces", and Controls/Highlight.cs):
// a class's swatch, highlight and title underline; a note's row; section headings; the grouped box; the pills (Record,
// Attach, the ink button), links, pickers and icon buttons; the Ask bar; empty states and toasts; tabs, segments and
// the switch. ios/DESIGN.md shows each in a line. Every colour is a token (Theme.swift), every word's type a style
// (Type.swift), every icon the desktop's (Icons.swift).

// MARK: - The logo

/// Syft Notes' own logo, the app icon (the pixel s on its white tile, or the dark tile in dark mode), with the app
/// icon's rounded corners: wherever the app shows its logo (setup, pairing, About). Never a stand-in drawn some other
/// way. `size` is its width and height in points.
struct StudyStashLogo: View {
    var size: CGFloat = 64
    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.2237, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.line))
            .accessibilityLabel("Syft Notes")
    }
}

// MARK: - A class's colour

/// A class's colour beside its name: a small mark, a touch crooked, as if dabbed on with its highlighter (14 × 10;
/// `small`, 9 × 7). Nil is no class: the desktop's grey.
struct Swatch: View {
    var hue: Highlighter?
    var small = false

    init(_ hue: Highlighter?, small: Bool = false) {
        self.hue = hue
        self.small = small
    }

    var body: some View {
        let k: CGFloat = small ? 0.7 : 1
        UnevenRoundedRectangle(topLeadingRadius: 2 * k, bottomLeadingRadius: 5 * k, bottomTrailingRadius: 3 * k, topTrailingRadius: 4 * k)
            .fill(hue?.swatch ?? Highlighter.noneSwatch)
            .frame(width: small ? 9 : 14, height: small ? 7 : 10)
            .rotationEffect(.degrees(-8))
            .accessibilityHidden(true)
    }
}

/// Words marked with a class's highlighter: a swipe behind ink text, its corners uneven so it reads as drawn by hand,
/// each wrapped line with a swipe of its own (the folder under a note's title, an event's class, an assignment in the
/// calendar). `struck`: handed in, no swipe, struck through in the class's colour. `outlined`: ringed in ink (pressed).
/// `under`: a class page's title, the marker under the lower half of the words (or use `FolderTitle`). Nil hue is no
/// class: a grey wash.
struct Highlight: View {
    var text: String
    var hue: Highlighter?
    var style: AppText
    var struck = false
    var outlined = false
    var under = false
    @ScaledMetric private var em: CGFloat

    init(_ text: String, hue: Highlighter?, style: AppText = .folder, struck: Bool = false, outlined: Bool = false, under: Bool = false) {
        self.text = text
        self.hue = hue
        self.style = style
        self.struck = struck
        self.outlined = outlined
        self.under = under
        _em = ScaledMetric(wrappedValue: style.spec.compactSize ?? style.spec.size, relativeTo: style.spec.relativeTo)
    }

    var body: some View {
        Text(text)
            .textStyle(style)
            .foregroundStyle(struck ? Color.inkSubtle : .ink)
            .textRenderer(Marker(fill: struck ? nil : hue?.highlight ?? Highlighter.none, strike: struck ? hue?.swatch ?? .inkSubtle : nil,
                                 ring: outlined ? .ink : nil, under: under))
            // The swipe runs 0.28 em past the words; they're moved in by 0.18 of it, so a marked line starts level
            // with a plain one beside it.
            .padding(.horizontal, under ? 0 : 0.18 * em)
    }
}

/// A class page's title: its name, the date style's size, underlined with its highlighter.
struct FolderTitle: View {
    var name: String
    var hue: Highlighter?
    init(_ name: String, hue: Highlighter?) {
        self.name = name
        self.hue = hue
    }
    var body: some View {
        Highlight(name, hue: hue, style: .date, under: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Draws the marker behind each line of the words, then the words.
private struct Marker: TextRenderer {
    var fill: Color?
    var strike: Color?
    var ring: Color?
    var under: Bool

    var displayPadding: EdgeInsets { EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10) }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            let b = line.typographicBounds
            let body = b.ascent + b.descent
            let em = body / Atkinson.naturalLineHeight
            let r = b.rect
            if let fill, b.width > 0 {
                if under {
                    // From the middle of the type's own box to just above its foot, a little past the words.
                    ctx.fill(Path(CGRect(x: r.minX - 0.04 * em, y: r.minY + body * 0.5, width: b.width + 0.08 * em, height: body * 0.4)),
                             with: .color(fill))
                } else {
                    let box = CGRect(x: r.minX - 0.28 * em, y: r.minY - 0.04 * em, width: b.width + 0.56 * em, height: body + 0.06 * em)
                    let swipe = Swipe(em: em).path(in: box)
                    ctx.fill(swipe, with: .color(fill))
                    if let ring { ctx.stroke(swipe, with: .color(ring), lineWidth: 1.5) }
                }
            }
            ctx.draw(line)
            if let strike, b.width > 0 {
                // Handed in: two points of the class's colour through the middle of the small letters.
                ctx.fill(Path(CGRect(x: r.minX, y: b.origin.y - 0.27 * em - 1, width: b.width, height: 2)), with: .color(strike))
            }
        }
    }
}

/// A highlighter's pass: a box with each corner rounded its own way (the desktop's radii, in ems).
private struct Swipe: Shape {
    var em: CGFloat
    func path(in r: CGRect) -> Path {
        let tl = CGSize(width: 0.28 * em, height: 0.5 * em), tr = CGSize(width: 0.55 * em, height: 0.3 * em)
        let br = CGSize(width: 0.35 * em, height: 0.55 * em), bl = CGSize(width: 0.6 * em, height: 0.35 * em)
        let k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl.width, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr.width, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + tr.height),
                   control1: CGPoint(x: r.maxX - tr.width * (1 - k), y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + tr.height * (1 - k)))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br.height))
        p.addCurve(to: CGPoint(x: r.maxX - br.width, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - br.height * (1 - k)), control2: CGPoint(x: r.maxX - br.width * (1 - k), y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl.width, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - bl.height),
                   control1: CGPoint(x: r.minX + bl.width * (1 - k), y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - bl.height * (1 - k)))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl.height))
        p.addCurve(to: CGPoint(x: r.minX + tl.width, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + tl.height * (1 - k)), control2: CGPoint(x: r.minX + tl.width * (1 - k), y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - A note in a list

/// A note in a list, as the desktop's NoteRowView: when | its title, its folder (highlighted) and a sentence or two of
/// summary | how long. No box, no icon; rows are parted by hairlines (`first` has none above it). In a compact width
/// (a phone) when and how long share a line over the title. Wrap it in the NavigationLink that opens it. `showFolder`
/// is false on a class's own page; `onFolder` makes the folder a button (it shows a chevron) that moves the note.
struct NoteRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    var lecture: LectureSummary
    var showFolder = true
    var first = false
    var onFolder: (() -> Void)?

    var body: some View {
        let when = Format.parse(lecture.date).map { showFolder ? Format.day($0) : Format.date($0) } ?? ""
        let length = Format.duration(lecture.seconds)
        VStack(spacing: 0) {
            if !first { Rule() }
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        Text(when).textStyle(.when).foregroundStyle(.inkMuted)
                            .frame(width: 108, alignment: .leading).padding(.top, 2)
                        middle
                        Text(length).textStyle(.length).foregroundStyle(.inkSubtle)
                            .frame(minWidth: 64, alignment: .trailing).padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(when).textStyle(.when).foregroundStyle(.inkMuted)
                            Spacer(minLength: 12)
                            Text(length).textStyle(.length).foregroundStyle(.inkSubtle)
                        }
                        middle
                    }
                }
            }
            .padding(.top, first ? 4 : 16)
            .padding(.bottom, 16)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let t = lecture.title, !t.isEmpty { return t }
        return Nouns.untitled(folder: lecture.class, date: lecture.date)
    }

    private var middle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).textStyle(.title).foregroundStyle(.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showFolder { folder }
            summary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var folder: some View {
        let cls = lecture.class ?? ""
        let label = HStack(spacing: 4) {
            if cls.isEmpty || cls == "Unsorted" {
                HStack(spacing: 6) {
                    Icon("inbox", size: 15, relativeTo: .footnote).foregroundStyle(.inkSubtle)
                    Text("Unsorted").textStyle(.folder).foregroundStyle(.inkMuted)
                }
            } else {
                Highlight(cls, hue: app.hue(of: cls))
            }
            if onFolder != nil { Icon("expand_more", size: 14, relativeTo: .footnote).foregroundStyle(.inkSubtle) }
        }
        if let onFolder {
            Button(action: onFolder) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(cls.isEmpty || cls == "Unsorted" ? "Unsorted. Change folder" : "In \(cls). Change folder")
        } else {
            label
        }
    }

    @ViewBuilder private var summary: some View {
        if lecture.status != "done" {
            Text(Format.statusWord(lecture.status)).textStyle(.summary, italic: true).foregroundStyle(.inkSubtle)
        } else if !lecture.summary.isEmpty {
            Text(PlainMath.inline(lecture.summary)).textStyle(.summary).foregroundStyle(.inkMuted)
                .lineLimit(2)
                .frame(maxWidth: 604, alignment: .leading)
        }
    }
}

// MARK: - Headings, rules, boxes

/// A section's heading: "Up next", "Notes", "Lectures". With `trailing`, a quiet link at its end ("See all").
struct SectionHeading: View {
    var title: String
    var trailing: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).textStyle(.h2).foregroundStyle(.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action).buttonStyle(.textLink)
            }
        }
        .padding(.top, 8)
    }
}

/// A group's label over its rows: "This week", "Last week", "October", "Classes".
struct GroupLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textStyle(.group).foregroundStyle(.inkSubtle).accessibilityAddTraits(.isHeader)
    }
}

/// A hairline across: between rows, under tabs.
struct Rule: View {
    var body: some View { Rectangle().fill(.line).frame(height: 1) }
}

/// A grouped box on the page (sunken grey, a hairline round it, the panel's corners): what settings-like rows sit in.
/// Replaces the look before's white Card.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surfaceSunken, in: .rect(cornerRadius: Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(.line))
    }
}

extension View {
    /// A screen's page: the surface behind everything, to the edges.
    func page() -> some View { background(Color.surface.ignoresSafeArea()) }

    /// A List or Form in the look: the page behind it, its rows grouped on sunken grey with hairlines between. Put
    /// `.groupedRows()` on each Section (or on the rows) for their background.
    func groupedList() -> some View {
        scrollContentBackground(.hidden).background(Color.surface.ignoresSafeArea())
    }

    /// A grouped list's rows: sunken grey, hairlines between.
    func groupedRows() -> some View {
        listRowBackground(Color.surfaceSunken).listRowSeparatorTint(.line)
    }
}

// MARK: - Buttons

/// A pill with words (Attach, the calendar's Today, the recording bar's Pause): white, a hairline round it, 48 tall
/// (`small`, 34). `ink`: filled with ink, the page's colour on it (Stop, Pair, Done). Put an `Icon` and a `Text` in it.
struct PillButtonStyle: ButtonStyle {
    var small = false
    var ink = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PillLabelStyle())
            .textStyle(small ? .buttonSmall : .button)
            .foregroundStyle(ink ? Color.surface : .ink)
            .padding(.horizontal, small ? 14 : 18)
            .frame(minHeight: small ? 34 : 48)
            .background(ink ? Color.ink : .surface, in: .capsule)
            .overlay {
                if configuration.isPressed { Capsule().fill(.press) }
                if !ink { Capsule().strokeBorder(configuration.isPressed ? Color.inkSubtle : .line) }
            }
            .opacity(enabled ? (ink && configuration.isPressed ? 0.9 : 1) : 0.45)
            .contentShape(.capsule)
    }
}

/// An icon and words side by side in a pill, 8 apart, the icon at 16 (as the desktop's buttons have it).
private struct PillLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.scaleEffect(size / 24).frame(width: size, height: size)
            configuration.title
        }
    }
}

/// The icon alone, at `size` (the 24-point image drawn smaller, its line with it, as the desktop's icons are).
private struct ScaledIconLabelStyle: LabelStyle {
    var size: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon.scaleEffect(size / 24).frame(width: size, height: size)
    }
}

/// A link in words: muted and bold over a 2-point grey underline; pressed, both turn ink. No accent colour.
struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.buttonSmall)
            .foregroundStyle(configuration.isPressed ? Color.ink : .inkMuted)
            .padding(.bottom, 2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(configuration.isPressed ? Color.ink : .line).frame(height: 2)
            }
            .contentShape(.rect)
    }
}

/// A quiet button with words (Open in Canvas): white, a hairline round it, the control's corners, 34 tall.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PillLabelStyle())
            .textStyle(.buttonSmall)
            .foregroundStyle(.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(.surface, in: .rect(cornerRadius: Radius.control))
            .overlay {
                if configuration.isPressed { RoundedRectangle(cornerRadius: Radius.control).fill(.press) }
                RoundedRectangle(cornerRadius: Radius.control).strokeBorder(configuration.isPressed ? Color.inkSubtle : .line)
            }
            .contentShape(.rect(cornerRadius: Radius.control))
    }
}

/// A menu's button (the notes' filter, the calendar's classes): words and a chevron in a hairline, muted until
/// pressed. Use `PickerLabel("All notes")` as its label.
struct PickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.buttonSmall)
            .foregroundStyle(configuration.isPressed ? Color.ink : .inkMuted)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(.line))
            .contentShape(.rect(cornerRadius: Radius.control))
    }
}

/// A picker's words and its chevron: `Menu { … } label: { PickerLabel("All notes") }.buttonStyle(.picker)`.
struct PickerLabel: View {
    var title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Icon("expand_more", size: 14, relativeTo: .subheadline)
        }
    }
}

/// An icon alone as a button: 32 square (`small`, 24), muted, ink while pressed. Give it an accessibility label.
struct IconButtonStyle: ButtonStyle {
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ScaledIconLabelStyle(size: small ? 16 : 20))
            .foregroundStyle(configuration.isPressed ? Color.ink : .inkMuted)
            .frame(width: small ? 24 : 32, height: small ? 24 : 32)
            .background(configuration.isPressed ? Color.press : .clear, in: .rect(cornerRadius: Radius.control))
            .contentShape(.rect(cornerRadius: Radius.control))
    }
}

/// A whole row as the button (Up next, a rail's row): nothing round it; pressed, it fills with the wash.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background {
                if configuration.isPressed { RoundedRectangle(cornerRadius: Radius.control).fill(.hover).padding(.horizontal, -12) }
            }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// Attach, Today, Pause: a white pill. `.pill(small: true)`, `.pill(ink: true)` (Stop, Done).
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(small: Bool = false, ink: Bool = false) -> PillButtonStyle { PillButtonStyle(small: small, ink: ink) }
}

extension ButtonStyle where Self == TextLinkStyle {
    /// "See these on the calendar", "Try again".
    static var textLink: TextLinkStyle { TextLinkStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    /// "Open in Canvas".
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == PickerButtonStyle {
    /// "All notes ⌄".
    static var picker: PickerButtonStyle { PickerButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    /// An icon alone.
    static var icon: IconButtonStyle { IconButtonStyle() }
    static func icon(small: Bool) -> IconButtonStyle { IconButtonStyle(small: small) }
}

extension ButtonStyle where Self == RowButtonStyle {
    /// A whole row.
    static var row: RowButtonStyle { RowButtonStyle() }
}

// MARK: - Recording

/// What Record shows: ready, recording, or paused.
enum RecordState: Sendable { case idle, recording, paused }

/// Record's dot, one cell of the pixel s (SyftCellShape), never a circle: red with a white cell in it; recording, the
/// centre is a stop square (sharper corners); paused, a red ring round a red centre. 36 across, so its corners stay
/// inside Record's 48-point pill with 6 all round (a circle's 40 would poke out of the pill's round end); `mini`, 32:
/// the floating recorder's and the tab bar's.
struct RecordDot: View {
    var state: RecordState = .idle
    var mini = false

    var body: some View {
        let size: CGFloat = mini ? 32 : 36
        let inner: CGFloat = state == .recording ? (mini ? 10 : 11) : (mini ? 11 : 13)
        ZStack {
            if state == .paused {
                SyftCellShape().strokeBorder(.record, lineWidth: 2)
            } else {
                SyftCellShape().fill(.record)
            }
            RoundedRectangle(cornerRadius: state == .recording ? 2 : inner * SyftCellShape.corner)
                .fill(state == .paused ? Color.record : .onRecord)
                .frame(width: inner, height: inner)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Record: a white pill with red only in its dot, 48 tall. Recording, it's ringed in red and says the folder, the
/// level (three columns of cells) and the time. `action` is the pill; `stop` (while recording) is the dot alone.
struct RecordButton: View {
    var state: RecordState = .idle
    /// "Record", or while recording the folder's name.
    var words = "Record"
    var elapsed: String?
    var levels: [Float] = []
    var action: () -> Void
    var stop: (() -> Void)?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let stop, state != .idle {
                    Button(action: stop) { RecordDot(state: state) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop recording")
                } else {
                    RecordDot(state: state)
                }
                Text(words).textStyle(.button).foregroundStyle(.ink).lineLimit(1)
                if state == .recording, !levels.isEmpty { LevelCells(levels: levels) }
                if state != .idle, let elapsed {
                    Text(elapsed).textStyle(.button).fontWeight(.medium).foregroundStyle(.inkMuted).fixedSize()
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 18)
            .frame(height: 48)
            .background(.surface, in: .capsule)
            .overlay {
                Capsule().strokeBorder(state == .idle ? Color.line : .record, lineWidth: state == .idle ? 1 : 1.5)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(PressWash())
        .accessibilityLabel(state == .idle ? words : "\(words), recording, \(elapsed ?? "")")
    }
}

private struct PressWash: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay { if configuration.isPressed { Capsule().fill(.press).allowsHitTesting(false) } }
    }
}

/// The live level in the pixel s's cells: `columns` columns (3 in a pill, up to 5 in a bar), the last few levels, of
/// four cells each on the mark's grid (cell 6.6, corners 1.8, pitch 8, scaled so four cells are `height` tall), lit
/// from the bottom a whole cell at a time in the recording red over the mesh's quiet fill. Only a cell's opacity
/// changes, quickly (80 ms). Reduce Motion: steady, two of the four lit.
struct LevelCells: View {
    var levels: [Float]
    var columns = 3
    var height: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var still

    nonisolated static let rows = 4

    /// The grid's units across `n` cells: n − 1 pitches and a cell.
    nonisolated static func span(_ n: Int) -> CGFloat { CGFloat(n - 1) * SyftCells.pitch + SyftCells.cell }

    /// How many of a column's four cells a level (0…1) lights: whole cells, rounded up, the bottom one always (it is
    /// recording).
    nonisolated static func lit(_ level: Float) -> Int { max(1, min(rows, Int((Double(level) * Double(rows)).rounded(.up)))) }

    var body: some View {
        let unit = height / Self.span(Self.rows)
        let cell = SyftCells.cell * unit, gap = (SyftCells.pitch - SyftCells.cell) * unit
        let shown = Array(levels.suffix(columns))
        let missing = columns - shown.count
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<columns, id: \.self) { c in
                let lit = still ? 2 : Self.lit(c < missing ? 0 : shown[c - missing])
                VStack(spacing: gap) {
                    ForEach(0..<Self.rows, id: \.self) { row in
                        ZStack {
                            SyftCellShape().fill(Color(syft: SyftPalette.mesh))
                            SyftCellShape().fill(.record).opacity(Self.rows - row <= lit ? 1 : 0)
                        }
                        .frame(width: cell, height: cell)
                    }
                }
                .animation(still ? nil : .linear(duration: 0.08), value: lit)
            }
        }
        .frame(width: Self.span(columns) * unit, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Ask

/// Ask's bar: one pill at the foot of the page, as a messaging app has it. Inside, from left to right: what it asks
/// about as a small chip (`chip`, a menu), the question, which grows to six lines, and the send circle, all lined up on
/// the last line, so nothing moves when the question is sent, cleared or a new chat starts. A hairline round it, no
/// ring with the caret in it. Send (or Return) hands the question to `onSend` and empties the field; the circle is grey
/// with nothing to send, ink with something, and Stop (`onStop`) while an answer is written.
struct AskBar<Chip: View>: View {
    var placeholder: String
    @Binding var text: String
    var busy = false
    var onStop: (() -> Void)?
    /// Puts the caret in it when it appears.
    var focusOnAppear = false
    var onFocus: ((Bool) -> Void)?
    @ViewBuilder var chip: () -> Chip
    var onSend: () -> Void
    @FocusState private var focused: Bool
    @State private var fieldID = UUID()
    @ScaledMetric(relativeTo: .body) private var control: CGFloat = 34

    init(placeholder: String, text: Binding<String>, busy: Bool = false, onStop: (() -> Void)? = nil, focusOnAppear: Bool = false,
         onFocus: ((Bool) -> Void)? = nil, @ViewBuilder chip: @escaping () -> Chip, onSend: @escaping () -> Void) {
        self.placeholder = placeholder
        _text = text
        self.busy = busy
        self.onStop = onStop
        self.focusOnAppear = focusOnAppear
        self.onFocus = onFocus
        self.chip = chip
        self.onSend = onSend
    }

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            chip()
                .frame(minHeight: control)
            field
            send
        }
        .padding(5)
        .background(.surface, in: .rect(cornerRadius: (control + 10) / 2, style: .continuous))
        .lifted(.float, in: RoundedRectangle(cornerRadius: (control + 10) / 2, style: .continuous))
        .contentShape(.rect(cornerRadius: (control + 10) / 2, style: .continuous))
        .onTapGesture { focused = true }
        .onAppear {
            guard focusOnAppear else { return }
            Task { try? await Task.sleep(for: .milliseconds(400)); focused = true }
        }
        .onChange(of: focused) { _, now in onFocus?(now) }
    }

    private var field: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.inkSubtle), axis: .vertical)
            .textStyle(.lede)
            .foregroundStyle(.ink)
            .tint(.ink)
            .lineLimit(1...6)
            .focused($focused)
            .id(fieldID)
            .submitLabel(.send)
            .onSubmit(submit)
            .onChange(of: text) { _, new in
                // Return sends, as the desktop's Enter does (a vertical field puts a line break in instead); a
                // question pasted on several lines becomes one, as the desktop's does.
                guard new.contains(where: \.isNewline) else { return }
                let returned = new.last?.isNewline == true
                text = new.split(whereSeparator: \.isNewline).joined(separator: " ")
                if returned { submit() }
            }
            .accessibilityIdentifier("ask.field")
            .accessibilityLabel(placeholder)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: control, alignment: .leading)
            .layoutPriority(1)
    }

    /// Sends what's typed, and empties the field: a new field at once (what the keyboard was still holding, a
    /// suggestion or dictation, would otherwise bring the question back), and a look a moment later.
    private func submit() {
        guard !busy, !empty else { return }
        let sent = text
        let typing = focused
        onSend()
        text = ""
        // A new field: whatever the keyboard was holding goes with the old one. The caret stays.
        fieldID = UUID()
        if typing { focused = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if text == sent || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = "" }
        }
    }

    private var send: some View {
        let on = busy || !empty
        return Button {
            if busy { onStop?() } else { submit() }
        } label: {
            ZStack {
                Circle().fill(on ? Color.ink : .surfaceSunken)
                if busy {
                    Icon("stop", size: 13, filled: true)
                } else {
                    Icon("arrow_upward", size: 18)
                }
            }
            .foregroundStyle(on ? Color.surface : .inkSubtle)
            .frame(width: control, height: control)
            .contentShape(.circle)
        }
        .buttonStyle(SendStyle())
        .disabled(!on || (busy && onStop == nil))
        .animation(.smooth(duration: 0.15), value: on)
        .accessibilityLabel(busy ? "Stop the answer" : "Send question")
        .accessibilityIdentifier(busy ? "ask.stop" : "ask.send")
    }
}

extension AskBar where Chip == AskScopeChip {
    /// The bar with its scope as a plain chip ("All notes"; nothing with no scope).
    init(placeholder: String, text: Binding<String>, scope: String?, busy: Bool = false, onSend: @escaping () -> Void) {
        self.init(placeholder: placeholder, text: text, busy: busy, chip: { AskScopeChip(title: scope ?? "") }, onSend: onSend)
    }
}

/// What Ask asks about, as the small chip at the start of its bar: a class's swatch, its name, a chevron. Put it in a
/// Menu as its label.
struct AskScopeChip: View {
    var title: String
    var hue: Highlighter?
    var showsSwatch = false
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 30

    var body: some View {
        if !title.isEmpty {
            HStack(spacing: 5) {
                if showsSwatch { Swatch(hue, small: true) }
                Text(title).textStyle(.buttonSmall).lineLimit(1).frame(maxWidth: 120, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                Icon("expand_more", size: 13, relativeTo: .subheadline)
            }
            .foregroundStyle(.inkMuted)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(.surfaceSunken, in: .capsule)
            .overlay(Capsule().strokeBorder(.line))
            .contentShape(.capsule)
        }
    }
}

/// Send and Stop: pressed, a touch lighter.
private struct SendStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The Ask bar as a button that opens Ask somewhere else (a lecture's page opening the Ask sheet): its placeholder,
/// its scope, nothing to type into here.
struct AskBarButton: View {
    var placeholder: String
    var scope: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(placeholder).textStyle(.lede).foregroundStyle(.inkMuted).lineLimit(1)
                Spacer(minLength: 8)
                if let scope { Text(scope).textStyle(.buttonSmall).foregroundStyle(.inkMuted).lineLimit(1) }
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .frame(height: 52)
            .background(.surface, in: .rect(cornerRadius: Radius.panel))
            .lifted(.float, in: RoundedRectangle(cornerRadius: Radius.panel))
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Empty, loading, offline, toasts

/// What a list says when there's nothing in it: one or two plain sentences, muted, at the lede's size. "No lectures
/// yet. Record one here, or attach a recording."
struct EmptyText: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textStyle(.lede).foregroundStyle(.inkMuted)
            .frame(maxWidth: 480, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What an empty state shows over its words: the pixel s, or Odd One Out (its top right cell popped out: something's
/// missing or went wrong).
enum EmptyMark { case mark, oddOneOut }

/// A screen with nothing to show, or that couldn't load: the pixel s (when it has a `mark`), a heading, a sentence, and
/// what to do about it. Replaces ContentUnavailableView.
struct EmptyState: View {
    var title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var mark: EmptyMark?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let mark { SyftMark(height: 96, oddOneOut: mark == .oddOneOut).padding(.bottom, 8) }
            Text(title).textStyle(.h2).foregroundStyle(.ink)
            if let detail, !detail.isEmpty { EmptyText(detail) }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.pill(small: true)).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

/// What a screen shows while a read is loading, failed with nothing saved, or worked.
struct Loaded<T: Codable & Sendable, Content: View>: View {
    var resource: Resource<T>
    var failure: String = "Couldn't load this."
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        if let value = resource.value {
            content(value)
        } else if let error = resource.error {
            EmptyState(title: error.unreachable ? "Can't reach your library" : failure, detail: error.detail, actionTitle: "Try again",
                       action: { Task { await resource.load() } }, mark: .oddOneOut)
        } else {
            StudyLoader(.page, color: .inkSubtle).frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

/// A short message floating at the foot of the screen, as the desktop's: "Moved to Calculus II. Undo", or a title
/// with a sentence under it ("Recording saved" / "Syft Notes is writing it down…"). Words in ink, the sentence muted,
/// an optional link at the end, on a white panel lifted on its shadow.
struct Toast: View {
    var text: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ text: String, detail: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.atkinson(14.5, detail == nil ? .medium : .semibold, relativeTo: .subheadline)).foregroundStyle(.ink)
                if let detail { Text(detail).font(.atkinson(13, relativeTo: .footnote)).foregroundStyle(.inkMuted) }
            }
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.textLink) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.surface, in: .rect(cornerRadius: Radius.panel))
        .lifted(.float, in: RoundedRectangle(cornerRadius: Radius.panel))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Show `message` as a toast at the foot of this view for a few seconds (it sets it back to nil).
    func toast(_ message: Binding<String?>, seconds: Double = 3) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                Toast(text)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(seconds))
                        withAnimation { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.smooth, value: message.wrappedValue)
    }
}

/// "Offline. Showing what was saved before", over a screen whose read couldn't be refreshed.
struct OfflineNote: View {
    var body: some View {
        HStack(spacing: 8) {
            Icon("cloud_off", size: 16, relativeTo: .subheadline).foregroundStyle(.inkSubtle)
            Text("Offline. Showing what was saved before").textStyle(.meta).foregroundStyle(.inkMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.surface, in: .rect(cornerRadius: Radius.panel))
        .lifted(.float, in: RoundedRectangle(cornerRadius: Radius.panel))
    }
}

// MARK: - Tabs, segments, switch

/// Two or three views of one thing under a hairline (Notes | Transcript), the chosen one's words in ink and
/// underlined in ink, the rest muted.
struct TabStrip<Value: Hashable>: View {
    @Binding var selection: Value
    var tabs: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs, id: \.value) { tab in
                let on = tab.value == selection
                Button { selection = tab.value } label: {
                    Text(tab.title).textStyle(.tab)
                        .foregroundStyle(on ? Color.ink : .inkMuted)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? Color.ink : .clear).frame(height: 2) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Rule() }
    }
}

/// Two ways to see one thing side by side (Month | Week, Flashcards | Quiz): in a hairline, the chosen one on the
/// wash.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title).textStyle(.buttonSmall).font(.atkinson(13.5, .bold, relativeTo: .subheadline))
                        .foregroundStyle(on ? Color.ink : .inkMuted)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .background(on ? Color.hover : .clear, in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(.line))
    }
}

/// A switch with its words ("Only my notes"): a small track, grey off, ink on. `.toggleStyle(.ink)`.
struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Capsule().fill(configuration.isOn ? Color.ink : .line)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.surface).frame(width: 14, height: 14).padding(.horizontal, 2)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    }
                configuration.label.textStyle(.buttonSmall).fontWeight(.semibold).foregroundStyle(.inkMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

extension ToggleStyle where Self == InkToggleStyle {
    static var ink: InkToggleStyle { InkToggleStyle() }
}

// MARK: - Kept from before

/// Topics as plain muted words, parted by a dot (no chips: the look has no pill badges).
struct TopicChips: View {
    var topics: [String]
    var limit: Int = .max
    var onTap: ((String) -> Void)?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(topics.prefix(limit).enumerated()), id: \.offset) { i, t in
                HStack(spacing: 6) {
                    if let onTap {
                        Button(t) { onTap(t) }.buttonStyle(.textLink)
                    } else {
                        Text(t).textStyle(.meta).foregroundStyle(.inkMuted)
                    }
                    if i < min(limit, topics.count) - 1 { Text("·").textStyle(.meta).foregroundStyle(.inkSubtle) }
                }
            }
        }
    }
}

/// Lays children out left to right, wrapping like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (i, x) in zip(row.indices, row.xs) {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0, y: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rows[rows.count - 1].height + spacing
                rows.append(Row(y: y))
                x = 0
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].xs.append(x)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
            rows[rows.count - 1].width = x - spacing
        }
        return rows
    }
}

/// The bar's title only once the screen's own big title has scrolled under it.
struct TitleOnScroll: ViewModifier {
    var title: String
    var after: CGFloat = 120
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > after } action: { _, new in
                withAnimation(.easeOut(duration: 0.15)) { shown = new }
            }
            .navigationTitle(shown ? title : "")
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func titleOnScroll(_ title: String, after: CGFloat = 120) -> some View { modifier(TitleOnScroll(title: title, after: after)) }
}
