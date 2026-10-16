import SwiftUI
import UIKit

// The iPad's sidebar, as the desktop's: Home, Due, Ask and Search, then each class under its group (Classes, Clubs,
// Work, or the student's own), and Coming up at its foot with where the library is and when Canvas last synced.

/// A group of classes in the sidebar: "Classes" (the library's own, or "Folders" when it isn't for school), then
/// the groups the student made on the computer, in the order the library lists them.
struct FolderGroup: Identifiable {
    var name: String
    var classes: [ClassInfo]
    var id: String { name }
}

extension AppModel {
    var folderGroups: [FolderGroup] {
        var groups: [FolderGroup] = []
        for c in classes {
            let name = (c.group ?? "").isEmpty ? words.classes : c.group!
            if let i = groups.firstIndex(where: { $0.name == name }) { groups[i].classes.append(c) } else { groups.append(FolderGroup(name: name, classes: [c])) }
        }
        return groups
    }
}

/// A class's swatch as an image, for where only an image goes (a sidebar tab's icon): light and dark.
enum SwatchImage {
    @MainActor static func of(_ hue: Highlighter?) -> UIImage {
        let asset = UIImageAsset()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let fill = (hue?.swatchUI ?? UIColor(hex: "#808080")).resolvedColor(with: traits)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 14), format: format).image { r in
                let c = r.cgContext
                c.translateBy(x: 9, y: 7)
                c.rotate(by: -8 * .pi / 180)
                c.translateBy(x: -9, y: -7)
                fill.setFill()
                UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 14, height: 10), cornerRadius: 3.5).fill()
            }.withRenderingMode(.alwaysOriginal)
            asset.register(image, with: traits)
        }
        return asset.image(with: .current)
    }
}

/// Coming up, at the foot of the iPad's sidebar: the next two events (a tap records one, into its class), then where
/// the library is and when Canvas last synced.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let now = Date.now
        let next = (app.upcoming?.events ?? []).filter { !$0.allDay && (Format.parse($0.end) ?? .distantPast) > now }.prefix(2)
        VStack(alignment: .leading, spacing: 10) {
            if !next.isEmpty {
                GroupLabel("Coming up")
                ForEach(Array(next)) { e in
                    let cls = app.className(ofEvent: e)
                    let start = Format.parse(e.start) ?? now
                    let soon = start > now && start.timeIntervalSince(now) <= 15 * 60
                    Button { app.record(for: cls, title: "\(e.title), \(Format.words(start, "EEE d MMM"))") } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 7) {
                                Swatch(app.hue(of: cls), small: true)
                                Text(e.title).textStyle(.buttonSmall).foregroundStyle(.ink).lineLimit(1)
                            }
                            Text(start <= now ? "Now" : soon ? Nouns.capital(Format.inMinutes(start.timeIntervalSince(now))) : "\(Format.day(start)) \(Format.time(start))")
                                .textStyle(.micro).fontWeight(soon ? .bold : .medium)
                                .foregroundStyle(soon ? Color.ink : .inkSubtle)
                                .padding(.leading, 16)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.row)
                    .accessibilityLabel("Record \(e.title)")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.isDemo ? "Sample classes" : "Library: \(app.libraryName)").textStyle(.micro)
                if let synced = ResponseCache.shared.read("due", as: DueList.self)?.synced.flatMap(Format.parse) {
                    Text("Canvas synced at \(Format.time(synced))").textStyle(.micro)
                }
            }
            .foregroundStyle(.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
