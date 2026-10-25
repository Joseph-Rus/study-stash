import SwiftUI
import UIKit

/// Home's banner while the laptop is recording: "Recording on your laptop · Calculus II · 12 min", and a big camera
/// button. The photos go to that recording; the student picks nothing.
struct RecordingNowBanner: View {
    var info: RecordingNow
    var now: Date
    var onCamera: () -> Void

    /// "Recording on your laptop · Calculus II · 12 min": the class left out when there isn't one.
    static func words(_ info: RecordingNow, now: Date) -> String {
        var parts = ["Recording on your laptop"]
        if let c = info.class, !c.isEmpty, c != "Unsorted" { parts.append(c) }
        if let started = start(info) { parts.append(Format.duration(max(60, now.timeIntervalSince(started)))) }
        return parts.joined(separator: " · ")
    }

    static func start(_ info: RecordingNow) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: info.started) ?? fractional.date(from: info.started)
    }

    /// Where its photos go.
    static func target(_ info: RecordingNow) -> PhotoTarget {
        PhotoTarget(lecture: info.id, className: info.class, label: "Recording on your laptop")
    }

    var body: some View {
        Panel {
            HStack(spacing: 12) {
                PulseDot(pulsing: true, size: 10)
                Text(Self.words(info, now: now)).textStyle(.nav).foregroundStyle(.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCamera) { Label("Photo", icon: "photo_camera") }
                    .buttonStyle(.pill(ink: true))
                    .accessibilityLabel("Take photos of the board")
            }
        }
        .accessibilityIdentifier("banner.recordingNow")
    }
}

/// A lecture's whiteboard photos in time order, each labelled with its moment in the lecture ("12:34"); a tap opens
/// one full size.
struct WhiteboardStrip: View {
    @Environment(AppModel.self) private var app
    var photos: [Attachment]
    @State private var preview: URL?

    /// In the order they were taken in the lecture.
    static func ordered(_ files: [Attachment]) -> [Attachment] {
        files.filter(\.isWhiteboard).sorted { ($0.at ?? .greatestFiniteMagnitude, $0.taken ?? "") < ($1.at ?? .greatestFiniteMagnitude, $1.taken ?? "") }
    }

    /// "12:34" into the lecture; a photo whose lecture isn't known yet says when it was taken.
    static func label(_ p: Attachment) -> String {
        if let at = p.at { return Format.clock(at) }
        if let t = p.taken, let d = WhiteboardPhotoTime.parse(t) { return Format.time(d) }
        return ""
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(photos) { p in
                    Button { Task { await open(p) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PhotoThumb(id: p.id).frame(width: 150, height: 112).clipShape(.rect(cornerRadius: Radius.control))
                            Text(Self.label(p)).textStyle(.micro).foregroundStyle(.inkSubtle)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Whiteboard photo at \(Self.label(p))")
                }
            }
        }
        .quickLookPreview($preview)
    }

    private func open(_ p: Attachment) async {
        guard let api = app.api, let (data, _) = try? await AppModel.session.data(for: URLRequest(url: api.attachmentURL(p.id), timeoutInterval: 300)) else { return }
        let dir = FileManager.default.temporaryDirectory.appending(path: p.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "Whiteboard \(Self.label(p).replacingOccurrences(of: ":", with: "-")).jpg")
        if (try? data.write(to: file)) != nil { preview = file }
    }
}

enum WhiteboardPhotoTime {
    static func parse(_ s: String) -> Date? { RecordingNowBanner.start(RecordingNow(id: "", class: nil, title: nil, started: s)) }
}

/// One photo's picture, fetched through the app's session (so over Google Drive and in the demo too).
private struct PhotoThumb: View {
    @Environment(AppModel.self) private var app
    var id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.surfaceSunken)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: id) {
            guard image == nil, let api = app.api,
                  let (data, _) = try? await AppModel.session.data(for: URLRequest(url: api.attachmentURL(id), timeoutInterval: 120)) else { return }
            image = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 450, height: 336)) }.value
        }
    }
}

/// Notes with a photo in them (`<img src="/api/v2/attachments/<id>/raw">`): the web view has no pairing and can't reach
/// the library, so each is fetched through the app's session and put in as a picture the page holds itself. Only
/// this lecture's own attachments are shown; any other source is dropped.
enum NotePhotos {
    static let pattern = try! NSRegularExpression(pattern: #"<img\b[^>]*?src="/api/v2/attachments/([^"/]+)/raw"[^>]*>"#)

    /// The ids of the photos the notes embed.
    static func ids(in html: String) -> [String] {
        let ns = html as NSString
        return pattern.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The notes with each photo of `allowed` (this lecture's attachments) as a data: picture; an embed of anything else is removed.
    @MainActor static func inline(_ html: String, allowed: Set<String>, fetch: (String) async -> Data?) async -> String {
        var out = html
        let ns = html as NSString
        for m in pattern.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let id = ns.substring(with: m.range(at: 1)).removingPercentEncoding ?? ns.substring(with: m.range(at: 1))
            let tag = ns.substring(with: m.range)
            var replacement = ""
            if allowed.contains(id), let data = await fetch(id) {
                replacement = tag.replacingOccurrences(of: #"src="[^"]*""#, with: "src=\"data:image/jpeg;base64,\(data.base64EncodedString())\"", options: .regularExpression)
            }
            out = (out as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return out
    }

    /// The notes with every embedded library photo taken out (until the photos are in).
    static func strip(_ html: String) -> String {
        pattern.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
    }

    /// The size a photo is shown at in notes: 1200 px wide is plenty for a phone, and keeps the page light.
    static func small(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let scale = min(1, 1200 / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.7) { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
