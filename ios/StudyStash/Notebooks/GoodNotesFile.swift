import Compression
import CoreGraphics
import Foundation

/// A GoodNotes notebook (.goodnotes), read: its pages in order, each with its size, the PDF page under it (an imported
/// PDF or a template), and its pen and highlighter strokes.
///
/// The format, as worked out from notebooks (with cable729/inkterop's notes, docs/formats/goodnotes.md):
/// - The file is a zip. `notes/<uuid>` is one page's journal, `index.events.pb` the notebook's, `index.attachments.pb`
///   names `attachments/<uuid>` files (PDFs). Every journal is protobuf records, each with a varint length before it.
/// - In `index.events.pb`, field 54 is a page: its id (2), its paper (3 → 1) and its sort key (4 → 1). Its strokes
///   are in `notes/<its id with the last byte one more>`. Field 2 is a paper: its id (2), attachment (4), that PDF's
///   page number (5, from 1) and size (8: width 1, height 2), in the units the strokes use.
/// - In a page's journal, field 7 is a stroke: geometry (2, Apple-LZ4-framed "tpl" blob), colour (4: RGBA floats 1–4,
///   a missing one 0), highlighter (5), and an offset from a lasso move (6: x 1, y 2).
struct GoodNotesNotebook {
    struct Stroke {
        /// Sub-paths, each points with the pen's width there.
        var paths: [[(point: CGPoint, width: CGFloat)]]
        var color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        var highlighter: Bool
    }

    struct Page {
        var size: CGSize
        /// The PDF under the page, and which of its pages (from 1).
        var background: (pdf: Data, page: Int)?
        var strokes: [Stroke]
    }

    var title: String
    var pages: [Page]

    /// GoodNotes' standard paper, for a page whose paper isn't said.
    static let standardPaper = CGSize(width: 834.24, height: 1078.825)

    init(data: Data, title: String) throws {
        self.title = title
        let zip = try ZipReader(data)
        let events = (try? zip.read("index.events.pb")).map(Proto.delimited) ?? []

        var attachmentFiles: [String: String] = [:]
        for r in (try? zip.read("index.attachments.pb")).map(Proto.delimited) ?? [] {
            let f = Proto.fields(r)
            if let id = f.string(1), let path = f.string(2) { attachmentFiles[id] = path }
        }

        struct Paper { var size: CGSize?; var attachment: String?; var pdfPage: Int }
        var papers: [String: Paper] = [:]
        var pageRecords: [(id: String, paper: String?, key: String)] = []
        for r in events {
            let f = Proto.fields(r)
            if let p = f.message(2), let id = p.string(2) {
                let size = p.message(8).flatMap { s in s.float(1).flatMap { w in s.float(2).map { CGSize(width: Double(w), height: Double($0)) } } }
                papers[id] = Paper(size: size, attachment: p.string(4), pdfPage: Int(p.varint(5) ?? 1))
            }
            if let p = f.message(54), let id = p.string(2) {
                pageRecords.append((id, p.message(3)?.string(1), p.message(4)?.string(1) ?? ""))
            }
        }

        // Pages in the notebook's order: by sort key, else the order index.notes.pb lists their journals.
        var journals: [String] = []
        if !pageRecords.isEmpty {
            for p in pageRecords.sorted(by: { $0.key < $1.key }) { journals.append(Self.bumpLastByte(p.id)) }
        } else {
            journals = ((try? zip.read("index.notes.pb")).map(Proto.delimited) ?? []).compactMap { Proto.fields($0).string(1) }
        }
        let paperOf = Dictionary(pageRecords.map { (Self.bumpLastByte($0.id), $0.paper) }, uniquingKeysWith: { a, _ in a })

        var pdfs: [String: Data] = [:]
        pages = journals.compactMap { journal in
            guard zip.has("notes/\(journal)") else { return nil }
            let paper = paperOf[journal].flatMap { $0 }.flatMap { papers[$0] }
            var background: (Data, Int)?
            if let a = paper?.attachment, let path = attachmentFiles[a] {
                if pdfs[path] == nil { pdfs[path] = try? zip.read(path) }
                if let pdf = pdfs[path], pdf.starts(with: Data("%PDF".utf8)) { background = (pdf, paper?.pdfPage ?? 1) }
            }
            let strokes = ((try? zip.read("notes/\(journal)")).map(Proto.delimited) ?? []).compactMap(Self.stroke)
            return Page(size: paper?.size ?? Self.standardPaper, background: background, strokes: strokes)
        }
        if pages.isEmpty { throw GoodNotesError("That notebook has no pages Syft Notes can read.") }
    }

    /// A page record's id names its journal with the last byte one more ("…521" → "…522").
    static func bumpLastByte(_ id: String) -> String {
        guard id.count >= 2, let last = UInt8(id.suffix(2), radix: 16) else { return id }
        return id.dropLast(2) + String(format: "%02X", last &+ 1)
    }

    static func stroke(_ record: Data) -> Stroke? {
        guard let s = Proto.fields(record).message(7), let geometry = s.bytes(2), !geometry.isEmpty,
              let blob = try? AppleLZ4.decode(geometry), let tpl = TPL(blob), tpl.signature.hasPrefix("vA(v)A(u)A(u)"),
              tpl.sections.count > 3 else { return nil }
        let flags = tpl.sections[1].ints
        let p = tpl.sections[3].floats
        var points: [(x: Double, y: Double, w: Double)] = []
        if let f = flags.first, f & 4 != 0, !p.isEmpty, p.count % 9 == 0 {
            // Pressure pen: (x1, y1, w1, x2, y2, w2, rot1, rot2, k) a pair of samples at a time.
            for i in stride(from: 0, to: p.count, by: 9) {
                points.append((Double(p[i]), Double(p[i + 1]), Double(p[i + 2])))
                points.append((Double(p[i + 3]), Double(p[i + 4]), Double(p[i + 5])))
            }
        } else if !p.isEmpty, p.count % 3 == 0 {
            for i in stride(from: 0, to: p.count, by: 3) { points.append((Double(p[i]), Double(p[i + 1]), Double(p[i + 2]))) }
        } else if p.count % 4 == 0, let w = tpl.sections[2].floats.first {
            // Constant-width pen: segments (x1, y1, x2, y2), the width alone.
            for i in stride(from: 0, to: p.count, by: 4) {
                points.append((Double(p[i]), Double(p[i + 1]), Double(w)))
                points.append((Double(p[i + 2]), Double(p[i + 3]), Double(w)))
            }
        }
        let offset = s.message(6).map { CGPoint(x: Double($0.float(1) ?? 0), y: Double($0.float(2) ?? 0)) } ?? .zero
        // A point at (~0, ~0) breaks the stroke into sub-paths.
        var paths: [[(point: CGPoint, width: CGFloat)]] = [[]]
        for pt in points {
            if abs(pt.x) <= 0.5 && abs(pt.y) <= 0.5 {
                if !(paths.last ?? []).isEmpty { paths.append([]) }
                continue
            }
            paths[paths.count - 1].append((CGPoint(x: pt.x + offset.x, y: pt.y + offset.y), CGFloat(max(pt.w, 0.3))))
        }
        paths.removeAll { $0.isEmpty }
        guard !paths.isEmpty else { return nil }
        let c = s.message(4)
        let highlighter = (s.varint(5) ?? 0) != 0
        let color = (CGFloat(c?.float(1) ?? 0), CGFloat(c?.float(2) ?? 0), CGFloat(c?.float(3) ?? 0), CGFloat(c?.float(4) ?? 1))
        return Stroke(paths: paths, color: color, highlighter: highlighter)
    }
}

struct GoodNotesError: Error, LocalizedError {
    var words: String
    init(_ words: String) { self.words = words }
    var errorDescription: String? { words }
}

// MARK: - protobuf, the little that's needed

enum Proto {
    enum Value { case varint(UInt64), fixed64(UInt64), bytes(Data), fixed32(UInt32) }

    struct Fields {
        var all: [(Int, Value)]

        func first(_ n: Int) -> Value? { all.first { $0.0 == n }?.1 }
        func bytes(_ n: Int) -> Data? { if case .bytes(let d)? = first(n) { d } else { nil } }
        func string(_ n: Int) -> String? { bytes(n).flatMap { String(data: $0, encoding: .utf8) } }
        func message(_ n: Int) -> Fields? { bytes(n).map(Proto.fields) }
        func varint(_ n: Int) -> UInt64? { if case .varint(let v)? = first(n) { v } else { nil } }
        func float(_ n: Int) -> Float? { if case .fixed32(let v)? = first(n) { Float(bitPattern: v) } else { nil } }
    }

    static func varint(_ d: Data, _ p: inout Int) -> UInt64? {
        var result: UInt64 = 0, shift: UInt64 = 0
        while p < d.endIndex {
            let c = d[p]; p += 1
            result |= UInt64(c & 0x7f) << shift
            if c & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    /// The fields of one message; a message that doesn't parse gives what was read before it broke.
    static func fields(_ d: Data) -> Fields {
        var out: [(Int, Value)] = []
        var p = d.startIndex
        while p < d.endIndex {
            guard let key = varint(d, &p) else { break }
            let n = Int(key >> 3)
            switch key & 7 {
            case 0: guard let v = varint(d, &p) else { return Fields(all: out) }; out.append((n, .varint(v)))
            case 1:
                guard p + 8 <= d.endIndex else { return Fields(all: out) }
                out.append((n, .fixed64(d[p..<p + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }))); p += 8
            case 2:
                guard let len = varint(d, &p), p + Int(len) <= d.endIndex else { return Fields(all: out) }
                out.append((n, .bytes(Data(d[p..<p + Int(len)])))); p += Int(len)
            case 5:
                guard p + 4 <= d.endIndex else { return Fields(all: out) }
                out.append((n, .fixed32(d[p..<p + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))); p += 4
            default: return Fields(all: out)
            }
        }
        return Fields(all: out)
    }

    /// Records each with a varint length before it.
    static func delimited(_ d: Data) -> [Data] {
        var out: [Data] = []
        var p = d.startIndex
        while p < d.endIndex, let len = varint(d, &p), p + Int(len) <= d.endIndex {
            out.append(Data(d[p..<p + Int(len)]))
            p += Int(len)
        }
        return out
    }
}

// MARK: - Apple's LZ4 frames ("bv41" compressed, "bv4-" stored, "bv4$" the end)

enum AppleLZ4 {
    struct Bad: Error {}

    static func decode(_ d: Data) throws -> Data {
        let d = Data(d)
        var out = Data()
        var p = 0
        func u32(_ at: Int) throws -> Int {
            guard at + 4 <= d.count else { throw Bad() }
            return Int(d[at..<at + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        }
        while p + 4 <= d.count {
            let magic = String(decoding: d[p..<p + 4], as: UTF8.self)
            switch magic {
            case "bv4$": return out
            case "bv41":
                let size = try u32(p + 4), packed = try u32(p + 8)
                guard p + 12 + packed <= d.count else { throw Bad() }
                out.append(try block(d[(p + 12)..<(p + 12 + packed)], size: size))
                p += 12 + packed
            case "bv4-":
                let size = try u32(p + 4)
                guard p + 8 + size <= d.count else { throw Bad() }
                out.append(d[(p + 8)..<(p + 8 + size)])
                p += 8 + size
            default: throw Bad()
            }
        }
        return out
    }

    /// One raw LZ4 block.
    static func block(_ src: Data, size: Int) throws -> Data {
        let s = [UInt8](src)
        var out = [UInt8]()
        out.reserveCapacity(size)
        var p = 0
        while p < s.count {
            let token = s[p]; p += 1
            var literals = Int(token >> 4)
            if literals == 15 { while p < s.count { let c = Int(s[p]); p += 1; literals += c; if c != 255 { break } } }
            guard p + literals <= s.count else { throw Bad() }
            out += s[p..<p + literals]; p += literals
            if p >= s.count { break }
            guard p + 2 <= s.count else { throw Bad() }
            let offset = Int(s[p]) | Int(s[p + 1]) << 8; p += 2
            var length = Int(token & 15) + 4
            if token & 15 == 15 { while p < s.count { let c = Int(s[p]); p += 1; length += c; if c != 255 { break } } }
            let start = out.count - offset
            guard offset > 0, start >= 0 else { throw Bad() }
            for i in 0..<length { out.append(out[start + i]) }
        }
        guard out.count == size else { throw Bad() }
        return Data(out)
    }
}

// MARK: - tpl blobs (Troy Hanson's tpl: "tpl\0", a length, a signature, then the values)

struct TPL {
    struct Section { var ints: [Int] = []; var floats: [Float] = [] }
    var signature: String
    var sections: [Section]

    init?(_ blob: Data) {
        let b = [UInt8](blob)
        guard b.count > 9, b[0] == 0x74, b[1] == 0x70, b[2] == 0x6c, b[3] == 0,
              let end = b[8...].firstIndex(of: 0) else { return nil }
        signature = String(decoding: b[8..<end], as: UTF8.self)
        var p = end + 1
        func u32() -> Int? {
            guard p + 4 <= b.count else { return nil }
            defer { p += 4 }
            return Int(UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24)
        }
        func f32() -> Float? { u32().map { Float(bitPattern: UInt32($0)) } }
        func u16() -> Int? {
            guard p + 2 <= b.count else { return nil }
            defer { p += 2 }
            return Int(b[p]) | Int(b[p + 1]) << 8
        }
        var secs: [Section] = []
        var i = signature.startIndex
        while i < signature.endIndex {
            let rest = signature[i...]
            if rest.hasPrefix("A(S(") {
                guard let close = rest.range(of: "))") else { return nil }
                let width = rest.distance(from: rest.index(i, offsetBy: 4), to: close.lowerBound)
                guard let count = u32() else { return nil }
                var s = Section()
                for _ in 0..<(count * width) { guard let f = f32() else { return nil }; s.floats.append(f) }
                secs.append(s)
                i = close.upperBound
            } else if rest.hasPrefix("A(") {
                let kind = rest[rest.index(i, offsetBy: 2)]
                guard let count = u32() else { return nil }
                var s = Section()
                for _ in 0..<count {
                    if kind == "v" { guard let v = u16() else { return nil }; s.ints.append(v) } else { guard let f = f32() else { return nil }; s.floats.append(f) }
                }
                secs.append(s)
                i = signature.index(i, offsetBy: 4)
            } else {
                var s = Section()
                if signature[i] == "v" { guard let v = u16() else { return nil }; s.ints = [v] } else { guard let f = f32() else { return nil }; s.floats = [f] }
                secs.append(s)
                i = signature.index(after: i)
            }
        }
        sections = secs
    }
}

// MARK: - zip, read only (stored and deflated entries)

struct ZipReader {
    struct Bad: Error {}
    private let data: Data
    private var entries: [String: (offset: Int, method: Int, packed: Int, size: Int)] = [:]

    init(_ data: Data) throws {
        self.data = Data(data)
        let b = self.data
        func u16(_ p: Int) -> Int { Int(b[p]) | Int(b[p + 1]) << 8 }
        func u32(_ p: Int) -> Int { u16(p) | u16(p + 2) << 16 }
        // The end of central directory record, in the last 64 KB.
        guard b.count >= 22 else { throw Bad() }
        var eocd = -1
        for p in stride(from: b.count - 22, through: max(0, b.count - 65_557), by: -1) where u32(p) == 0x0605_4b50 { eocd = p; break }
        guard eocd >= 0 else { throw Bad() }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x0201_4b50 else { throw Bad() }
            let method = u16(p + 10), packed = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32), local = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            entries[name] = (local, method, packed, size)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    func has(_ name: String) -> Bool { entries[name] != nil }

    func read(_ name: String) throws -> Data {
        guard let e = entries[name] else { throw Bad() }
        let b = data
        func u16(_ p: Int) -> Int { Int(b[p]) | Int(b[p + 1]) << 8 }
        let start = e.offset + 30 + u16(e.offset + 26) + u16(e.offset + 28)
        guard start + e.packed <= b.count else { throw Bad() }
        let packed = b[start..<(start + e.packed)]
        switch e.method {
        case 0: return Data(packed)
        case 8:
            if e.size == 0 { return Data() }
            var out = Data(count: e.size)
            let n = out.withUnsafeMutableBytes { dst in
                packed.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, e.packed, nil, COMPRESSION_ZLIB)
                }
            }
            guard n == e.size else { throw Bad() }
            return out
        default: throw Bad()
        }
    }
}
