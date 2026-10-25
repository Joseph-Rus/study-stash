import Foundation
import Testing
import UIKit
@testable import StudyStash

/// What would really hurt a student here: a photo lost on the way to the library, or filed under the wrong lecture.
final class PhotoSpy: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lectures: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "photos.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = DemoLibrary.body(of: request).flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
        if let r = body.range(of: #"name="lecture"\r\n\r\n([^\r]+)"#, options: .regularExpression) {
            let value = body[r].components(separatedBy: "\r\n\r\n").last ?? ""
            Self.lectures.append(value)
            #expect(body.contains("whiteboard"))
            #expect(body.contains(#"name="taken""#))
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"attachments":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized) struct WhiteboardPhotoTests {
    static func jpeg(_ w: CGFloat, _ h: CGFloat, noisy: Bool = false) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).jpegData(withCompressionQuality: 0.9) { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if noisy { for _ in 0..<3000 { UIColor(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 1).setFill(); c.fill(CGRect(x: .random(in: 0..<w), y: .random(in: 0..<h), width: 40, height: 40)) } }
        }
    }

    static func api() -> APIClient {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [PhotoSpy.self]
        return APIClient(base: URL(string: "http://photos.test")!, session: URLSession(configuration: c))
    }

    func folder() -> URL { FileManager.default.temporaryDirectory.appending(path: "photos-\(UUID().uuidString)") }

    @Test func waitingPhotosSurviveARestart() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PhotoStore(folder: dir)
        let target = PhotoTarget(lecture: "phone-20261024-091500-aabbcc", className: "Calculus II", label: "x")
        #expect(await store.add(Self.jpeg(800, 600), for: target, taken: .now, straighten: false))
        let again = PhotoStore(folder: dir)
        #expect(again.photos.count == 1)
        #expect(again.photos[0].lecture == target.lecture)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: again.photos[0].file).path))
    }

    @Test func aPhoneRecordingsPhotosGoAfterItsLecture() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PhotoStore(folder: dir)
        var state: Recording.State? = .waiting
        store.recordingState = { _ in state }
        let phone = PhotoTarget(lecture: "phone-1", className: nil, label: "x")
        let laptop = PhotoTarget(lecture: "rec-laptop", className: nil, label: "x")
        await store.add(Self.jpeg(300, 200), for: phone, taken: Date(timeIntervalSince1970: 1_000), straighten: false)
        await store.add(Self.jpeg(300, 200), for: laptop, taken: Date(timeIntervalSince1970: 2_000), straighten: false)
        PhotoSpy.lectures = []
        await store.sendWaiting(api: Self.api())
        // The laptop's goes at once; the phone's waits for its lecture.
        #expect(PhotoSpy.lectures == ["rec-laptop"])
        #expect(store.photos.map(\.lecture) == ["phone-1"])
        state = .sent
        await store.sendWaiting(api: Self.api())
        #expect(PhotoSpy.lectures == ["rec-laptop", "phone-1"])
        #expect(store.photos.isEmpty)
    }

    @Test func aPhotoIsSmallEnoughToSend() throws {
        let big = Self.jpeg(4000, 3000, noisy: true)
        let out = try #require(WhiteboardPhoto.prepare(big, straighten: false))
        let image = try #require(UIImage(data: out))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 2560)
        #expect(out.count <= 2_000_000)
    }

    @Test func theBannerAppearsFromRecordingNow() throws {
        let json = #"{"name":"L","version":"1","classes":[],"unsorted":0,"writing":0,"ask":true,"recording_now":{"id":"rec-1","class":"Calculus II","title":"T","started":"2026-10-24T09:00:00-07:00"}}"#
        let o = try APIClient.decoder.decode(LibraryOverview.self, from: Data(json.utf8))
        let now = try #require(o.recordingNow)
        let at = try #require(RecordingNowBanner.start(now))
        #expect(RecordingNowBanner.words(now, now: at.addingTimeInterval(12 * 60)) == "Recording on your laptop · Calculus II · 12 min")
        let none = try APIClient.decoder.decode(LibraryOverview.self, from: Data(#"{"name":"L","version":"1","classes":[],"unsorted":0,"writing":0,"ask":true,"recording_now":null}"#.utf8))
        #expect(none.recordingNow == nil)
    }

    @Test func notesShowOnlyThisLecturesPhotos() async {
        let html = #"<p>a</p><img src="/api/v2/attachments/mine/raw" alt="Whiteboard"><img src="/api/v2/attachments/other/raw" alt="x">"#
        let out = await NotePhotos.inline(html, allowed: ["mine"]) { _ in Data([1, 2, 3]) }
        #expect(out.contains("data:image/jpeg;base64,AQID"))
        #expect(!out.contains("other"))
        #expect(!out.contains("/api/v2/attachments"))
    }
}
