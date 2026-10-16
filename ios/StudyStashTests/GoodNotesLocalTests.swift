import Foundation
import PencilKit
import Testing
@testable import StudyStash

/// Against a real notebook on this Mac, not in the repo: GOODNOTES_SAMPLE names it. Skipped without one.
@Suite struct GoodNotesLocalTests {
    @Test func aRealNotebookBecomesInkYouCanSee() throws {
        guard let path = ProcessInfo.processInfo.environment["GOODNOTES_SAMPLE"], FileManager.default.fileExists(atPath: path) else { return }
        let book = try GoodNotesNotebook(data: Data(contentsOf: URL(fileURLWithPath: path)), title: "s")
        #expect(!book.pages.isEmpty)
        let page = book.pages[0]
        let d = NotebookStore.drawing(from: page.strokes)
        #expect(d.strokes.count == page.strokes.reduce(0) { $0 + $1.paths.count })
        var solid = 0
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            let cg = d.image(from: CGRect(origin: .zero, size: page.size), scale: 1).cgImage!
            let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            let px = ctx.data!.bindMemory(to: UInt8.self, capacity: cg.width * cg.height * 4)
            for i in 0..<(cg.width * cg.height) where px[i * 4 + 3] > 128 { solid += 1 }
        }
        // PencilKit draws nothing for too-thin strokes made in code: every stroke has to show.
        #expect(solid > page.strokes.count * 15)
    }
}
