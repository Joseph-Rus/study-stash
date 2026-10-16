import SwiftUI

/// A class's coloured dot.
struct ClassDot: View {
    var color: Color
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(color.gradient).frame(width: size, height: size)
    }
}

/// Topics as small capsules that wrap onto more lines.
struct TopicChips: View {
    var topics: [String]
    var tint: Color = .accentColor
    var limit: Int = .max
    var onTap: ((String) -> Void)?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(topics.prefix(limit)), id: \.self) { t in
                let chip = Text(t)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12), in: .capsule)
                if let onTap {
                    Button { onTap(t) } label: { chip }.buttonStyle(.plain)
                } else {
                    chip
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

/// A lecture in a list: its class's colour down the side, title, when and how long, and its topics (or that its
/// notes are still being written).
struct LectureCard: View {
    var lecture: LectureSummary
    var color: Color
    var showClass = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.gradient)
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(lecture.displayTitle)
                    .font(.headlineSerif)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text([showClass ? lecture.class : nil, Format.lectureMeta(lecture.date, lecture.seconds)]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if lecture.status != "done" {
                    Label(Format.statusWord(lecture.status), systemImage: lecture.status == "failed" ? "exclamationmark.triangle" : "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(lecture.status == "failed" ? .orange : color)
                        .symbolEffect(.pulse, isActive: lecture.isWriting)
                } else if !lecture.topics.isEmpty {
                    Text(lecture.topics.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

/// A rounded card on the paper.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.card, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

/// A section heading over cards: "Recent lectures", "Due soon".
struct SectionHeading: View {
    var title: String
    var trailing: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action).font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
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
            ContentUnavailableView {
                Label(error.unreachable ? "Can't reach your library" : failure, systemImage: error.unreachable ? "wifi.slash" : "exclamationmark.triangle")
            } description: {
                Text(error.detail)
            } actions: {
                Button("Try again") { Task { await resource.load() } }.buttonStyle(.bordered)
            }
        } else {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

/// "Offline: showing what was saved before", over a screen whose read couldn't be refreshed.
struct OfflineNote: View {
    var body: some View {
        Label("Offline — showing what was saved before", systemImage: "icloud.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
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
