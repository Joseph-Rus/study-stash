import CoreImage
import Foundation
import ImageIO
import Observation
import UIKit
import Vision

/// Which lecture a photo belongs to, fixed when it's taken: a recording on this phone (its `phone-…` id) or the one
/// the laptop is recording now (`recording_now.id`). The student picks nothing.
struct PhotoTarget: Identifiable, Hashable, Sendable {
    var lecture: String
    var className: String?
    /// "Calculus II" or "Your recording": what the camera screen says the photos are going to.
    var label: String
    var id: String { lecture }
}

/// A photo taken and kept on this phone until the library has it.
struct WaitingPhoto: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var lecture: String
    var className: String?
    var taken: Date
    /// The JPEG, in the store's folder.
    var file: String
    /// The library refused it (not a lecture it knows): kept, not tried again.
    var refused = false
}

/// Making a whiteboard photo ready to send: the board found and straightened (when asked), at most 2560 px on the long
/// side, about 2 MB or less, a JPEG.
enum WhiteboardPhoto {
    static let longSide: CGFloat = 2560
    static let budget = 2_000_000

    static func prepare(_ data: Data, straighten: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              var image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: longSide,
              ] as CFDictionary) else { return nil }
        if straighten, let flat = straightened(image) { image = flat }
        return jpeg(image)
    }

    /// The JPEG, squeezed until it's under the budget.
    static func jpeg(_ image: CGImage) -> Data? {
        let ui = UIImage(cgImage: image)
        var quality: CGFloat = 0.85
        var out = ui.jpegData(compressionQuality: quality)
        while let d = out, d.count > budget, quality > 0.4 {
            quality -= 0.1
            out = ui.jpegData(compressionQuality: quality)
        }
        return out
    }

    /// The board (Vision's document segmentation) cut out and made rectangular; nil when no board is found, so the
    /// plain photo is kept.
    static func straightened(_ image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let board = request.results?.first, board.confidence > 0.6 else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // Too small to be the board (a poster on the wall): not worth cutting to.
        let box = board.boundingBox
        guard box.width * box.height > 0.2 else { return nil }
        func p(_ n: CGPoint) -> CIVector { CIVector(x: n.x * w, y: n.y * h) }
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(p(board.topLeft), forKey: "inputTopLeft")
        filter.setValue(p(board.topRight), forKey: "inputTopRight")
        filter.setValue(p(board.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(p(board.bottomRight), forKey: "inputBottomRight")
        guard let out = filter.outputImage, out.extent.width > 200, out.extent.height > 200 else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }

    /// When a photo from the Photos library was taken: its EXIF time (in the offset it says, else this phone's zone).
    static func takenTime(of data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset = exif["OffsetTimeOriginal" as CFString] as? String, offset.count >= 5 {
            f.timeZone = TimeZone(identifier: "GMT")
            if let base = f.date(from: text) {
                let sign = offset.hasPrefix("-") ? -1.0 : 1.0
                let digits = offset.filter(\.isNumber)
                let hours = Double(digits.prefix(2)) ?? 0, minutes = Double(digits.dropFirst(2).prefix(2)) ?? 0
                return base.addingTimeInterval(-sign * (hours * 3600 + minutes * 60))
            }
        }
        f.timeZone = .current
        return f.date(from: text)
    }
}

/// Photos waiting for the library. Each is kept (the JPEG and an index) in Application Support/Photos, so they survive
/// a restart and no connection, and are sent in the order they were taken once the library can be reached. A photo for
/// a recording made on this phone waits for that recording to reach the library first.
@MainActor @Observable
final class PhotoStore {
    static let shared = PhotoStore()

    private(set) var photos: [WaitingPhoto] = []
    let folder: URL
    @ObservationIgnored private var sending = false
    /// Where a phone recording has got to (nil: no longer kept here). Replaced in tests.
    @ObservationIgnored var recordingState: @MainActor (String) -> Recording.State? = { id in RecordingStore.shared.recordings.first { $0.id == id }?.state }

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Photos")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        photos = ((try? JSONDecoder.iso.decode([WaitingPhoto].self, from: Data(contentsOf: folder.appending(path: "index.json")))) ?? [])
            .filter { FileManager.default.fileExists(atPath: folder.appending(path: $0.file).path) }
    }

    func waiting(for lecture: String) -> Int { photos.filter { $0.lecture == lecture }.count }

    /// Keep a photo (a camera shot, or one from Photos with its own time) for `target`. Returns whether it could be made.
    @discardableResult
    func add(_ data: Data, for target: PhotoTarget, taken: Date, straighten: Bool) async -> Bool {
        let jpeg = await Task.detached { WhiteboardPhoto.prepare(data, straighten: straighten) }.value
        guard let jpeg else { return false }
        let id = UUID().uuidString.lowercased()
        let file = "\(id).jpg"
        guard (try? jpeg.write(to: folder.appending(path: file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return false }
        photos.append(WaitingPhoto(id: id, lecture: target.lecture, className: target.className, taken: taken, file: file))
        writeIndex()
        return true
    }

    func discard(lecture: String) {
        for p in photos where p.lecture == lecture { try? FileManager.default.removeItem(at: folder.appending(path: p.file)) }
        photos.removeAll { $0.lecture == lecture }
        writeIndex()
    }

    private func writeIndex() {
        guard let data = try? JSONEncoder.iso.encode(photos) else { return }
        try? data.write(to: folder.appending(path: "index.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Everything that can go now, oldest first. Stops at the first the library can't be reached for, so the order holds.
    func sendWaiting(api: APIClient) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        for p in photos.sorted(by: { $0.taken < $1.taken }) where !p.refused {
            if p.lecture.hasPrefix("phone-") {
                // Its recording first: the photo is that lecture's only once the lecture is in the library. (A
                // recording no longer kept here was sent, or discarded, which took its photos with it.)
                if let state = recordingState(p.lecture), state != .sent { continue }
            }
            guard let data = try? Data(contentsOf: folder.appending(path: p.file)) else { remove(p); continue }
            do {
                try await api.uploadPhoto(data: data, name: "whiteboard-\(p.id.prefix(8)).jpg",
                                          class: p.lecture.hasPrefix("phone-") ? p.className : nil, lecture: p.lecture, taken: Recording.localISO(p.taken))
                remove(p)
            } catch let e as APIError where !e.unreachable {
                if let i = photos.firstIndex(where: { $0.id == p.id }) { photos[i].refused = true; writeIndex() }
            } catch {
                return
            }
        }
    }

    private func remove(_ p: WaitingPhoto) {
        try? FileManager.default.removeItem(at: folder.appending(path: p.file))
        photos.removeAll { $0.id == p.id }
        writeIndex()
    }
}
