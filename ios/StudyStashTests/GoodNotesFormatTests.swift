import Foundation
import Testing
@testable import StudyStash

/// The pieces of the .goodnotes format, from bytes made here.
@Suite struct GoodNotesFormatTests {
    func varint(_ v: UInt64) -> Data {
        var v = v, out = Data()
        repeat { var b = UInt8(v & 0x7f); v >>= 7; if v > 0 { b |= 0x80 }; out.append(b) } while v > 0
        return out
    }
    func field(_ n: Int, _ bytes: Data) -> Data { varint(UInt64(n << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }
    func field(_ n: Int, float f: Float) -> Data { varint(UInt64(n << 3 | 5)) + withUnsafeBytes(of: f.bitPattern.littleEndian) { Data($0) } }
    func field(_ n: Int, int v: UInt64) -> Data { varint(UInt64(n << 3)) + varint(v) }
    func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }

    @Test func protobufFieldsAndDelimitedRecords() {
        let msg = field(1, Data("ABC".utf8)) + field(4, float: 0.5) + field(5, int: 300)
        let f = Proto.fields(msg)
        #expect(f.string(1) == "ABC" && f.float(4) == 0.5 && f.varint(5) == 300)
        let records = Proto.delimited(varint(UInt64(msg.count)) + msg + varint(2) + Data([8, 1]))
        #expect(records.count == 2 && Proto.fields(records[1]).varint(1) == 1)
    }

    @Test func appleLZ4FramesStoredAndCompressed() throws {
        // "abcabcabcabc": 3 literals, then a match of 9 at offset 3.
        let block = Data([0x35, 0x61, 0x62, 0x63, 0x03, 0x00])
        let framed = Data("bv41".utf8) + le32(12) + le32(block.count) + block + Data("bv4-".utf8) + le32(2) + Data("!!".utf8) + Data("bv4$".utf8)
        #expect(String(decoding: try AppleLZ4.decode(framed), as: UTF8.self) == "abcabcabcabc!!")
        #expect(throws: (any Error).self) { try AppleLZ4.decode(Data("nope".utf8)) }
    }

    @Test func tplSections() {
        func f32(_ x: Float) -> Data { withUnsafeBytes(of: x.bitPattern.littleEndian) { Data($0) } }
        func u16(_ x: Int) -> Data { withUnsafeBytes(of: UInt16(x).littleEndian) { Data($0) } }
        let sig = "vA(v)A(u)A(u)"
        let body = u16(2) + le32(1) + u16(4) + le32(1) + f32(0.4) + le32(6) + [1, 2, 0.5, 3, 4, 0.6].map { f32($0) }.reduce(Data(), +)
        let blob = Data("tpl\0".utf8) + le32(0) + Data(sig.utf8) + Data([0]) + body
        let t = TPL(blob)
        #expect(t?.signature == sig)
        #expect(t?.sections[1].ints == [4])
        #expect(t?.sections[3].floats == [1, 2, 0.5, 3, 4, 0.6])
    }

    @Test func aStrokeRecordBecomesPointsWithItsColour() throws {
        func f32(_ x: Float) -> Data { withUnsafeBytes(of: x.bitPattern.littleEndian) { Data($0) } }
        func u16(_ x: Int) -> Data { withUnsafeBytes(of: UInt16(x).littleEndian) { Data($0) } }
        // Flat (x, y, width) points, the middle one a (0, 0) break between two sub-paths.
        let pts: [Float] = [10, 20, 0.7, 12, 22, 0.7, 0, 0, 0.7, 30, 40, 0.8, 31, 41, 0.8]
        let body = u16(2) + le32(1) + u16(1) + le32(0) + le32(pts.count) + pts.map(f32).reduce(Data(), +)
        let tpl = Data("tpl\0".utf8) + le32(0) + Data("vA(v)A(u)A(u)".utf8) + Data([0]) + body
        let geometry = Data("bv4-".utf8) + le32(tpl.count) + tpl + Data("bv4$".utf8)
        let color = field(1, float: 1) + field(4, float: 1)
        let stroke = field(2, geometry) + field(4, color) + field(6, field(1, float: 5) + field(2, float: 0))
        let s = try #require(GoodNotesNotebook.stroke(field(7, stroke)))
        #expect(s.paths.count == 2)
        #expect(s.paths[0].map(\.point) == [CGPoint(x: 15, y: 20), CGPoint(x: 17, y: 22)])
        #expect(s.color.r == 1 && s.color.g == 0 && s.color.a == 1 && !s.highlighter)
    }

    @Test func pageRecordsNameTheirJournalOneHigher() {
        #expect(GoodNotesNotebook.bumpLastByte("3BA5508E-EDC7-5F77-A1DD-1C8181184521") == "3BA5508E-EDC7-5F77-A1DD-1C8181184522")
        #expect(GoodNotesNotebook.bumpLastByte("X-FF") == "X-00")
    }
}
