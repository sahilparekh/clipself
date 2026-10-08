import Foundation
import AppKit
#if SWIFT_PACKAGE
import XCTest
#else
// The standalone runner also works on Macs with only Command Line Tools.
class XCTestCase {}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(lhs) to equal \(rhs)", file: file, line: line)
}
#endif
#if SWIFT_PACKAGE
@testable import ClipShelf
#endif

final class ClipHistoryTests: XCTestCase {
    func testRecopyMovesClipToFrontWithoutLosingPinOrIdentity() {
        var history = ClipHistory()
        history.record("git status")
        let id = history.clips[0].id
        history.clips[0].pinned = true
        history.record("swift build")
        history.record("git status")
        XCTAssertEqual(history.clips.count, 2)
        XCTAssertEqual(history.clips[0].id, id)
        XCTAssertTrue(history.clips[0].pinned)
    }

    func testRetentionKeepsPinsAndLatest200Clips() {
        var history = ClipHistory()
        history.record("keep this")
        history.clips[0].pinned = true
        for i in 0..<210 { history.record("command \(i)") }
        XCTAssertEqual(history.clips.count, 201)
        XCTAssertTrue(history.clips.contains { $0.text == "keep this" })
        XCTAssertFalse(history.clips.contains { $0.text == "command 9" })
        XCTAssertTrue(history.clips.contains { $0.text == "command 10" })
    }

    func testExportPreservesExactTextAndChronologicalOrder() {
        var history = ClipHistory()
        history.record("  echo 'hello'\n", at: Date(timeIntervalSince1970: 1))
        history.record("ignored", at: Date(timeIntervalSince1970: 2))
        history.record("\tlet x = 1", at: Date(timeIntervalSince1970: 3))
        let ids = Set(history.clips.filter { $0.text != "ignored" }.map(\.id))
        XCTAssertEqual(history.export(ids: ids), "  echo 'hello'\n\n\n\tlet x = 1")
    }

    func testEmptyClipsAreIgnoredAndHistoryRoundTrips() throws {
        var history = ClipHistory()
        history.record(" \n\t")
        XCTAssertTrue(history.clips.isEmpty)
        history.record("日本語 🧑‍💻\nexport PATH=\"$PATH\"")
        history.clips[0].pinned = true
        let restored = try JSONDecoder().decode(ClipHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(restored.clips, history.clips)
    }

    func testOldTextHistoryStillLoads() throws {
        let json = #"{"clips":[{"id":"00000000-0000-0000-0000-000000000001","text":"git status","copiedAt":1,"pinned":true}]}"#
        let history = try JSONDecoder().decode(ClipHistory.self, from: Data(json.utf8))
        XCTAssertEqual(history.clips[0].text, "git status")
        XCTAssertEqual(history.clips[0].content, nil)
        XCTAssertTrue(history.clips[0].pinned)
    }

    func testCycleWrapsInBothDirectionsAndResets() {
        let ids = (0..<5).map { _ in UUID() }
        var cycle = ClipCycle()
        XCTAssertEqual(cycle.move(1), nil)
        cycle.reset(ids)
        XCTAssertEqual(cycle.move(1), ids[1])
        XCTAssertEqual(cycle.move(1), ids[2])
        XCTAssertEqual(cycle.move(-1), ids[1])
        XCTAssertEqual(cycle.move(-1), ids[0])
        XCTAssertEqual(cycle.move(-1), ids[4])
        XCTAssertEqual(cycle.move(1), ids[0])
        XCTAssertEqual(cycle.ids, ids)
        cycle.reset([ids[3]])
        XCTAssertEqual(cycle.move(1), ids[3])
    }

    func testBinaryAndFileClipsRemainDistinctAndRoundTrip() throws {
        var history = ClipHistory()
        history.record(Clip(text: "", content: .image(Data([1, 2, 3]))))
        history.record(Clip(text: "", content: .pdf(Data([1, 2, 3]))))
        history.record(Clip(text: "", content: .files(["/tmp/image.png", "/tmp/document.pdf"])))
        XCTAssertEqual(history.clips.count, 3)
        let originalID = history.clips[2].id
        history.record(Clip(text: "", content: .image(Data([1, 2, 3]))))
        XCTAssertEqual(history.clips.count, 3)
        XCTAssertEqual(history.clips[0].id, originalID)
        let restored = try JSONDecoder().decode(ClipHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(restored.clips, history.clips)
    }

    func testExportMixedItemsWithoutOverwritingExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("example.pdf")
        let bytes = Data([0, 1, 2, 255])
        try bytes.write(to: source)
        let existing = output.appendingPathComponent("1-example.pdf")
        try "keep me".write(to: existing, atomically: true, encoding: .utf8)
        let file = Clip(text: "", copiedAt: Date(timeIntervalSince1970: 1), content: .files([source.path]))
        let text = Clip(text: "\tcode\n", copiedAt: Date(timeIntervalSince1970: 2))
        let image = Clip(text: "", copiedAt: Date(timeIntervalSince1970: 3), content: .image(bytes))
        try ClipExporter.writeFolder([image, file, text], to: output)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep me")
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("1-example-2.pdf")), bytes)
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("2-clips.txt"), encoding: .utf8), "\tcode\n")
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("3-image.png")), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        try ClipExporter.write(file, to: source, replaceExisting: true)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        try ClipExporter.write(file, to: existing, replaceExisting: true)
        XCTAssertEqual(try Data(contentsOf: existing), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    @discardableResult
    func checkClipboardTypesAndMissingFileProtection() throws -> Bool {
        let board = NSPasteboard(name: NSPasteboard.Name("ClipShelfTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        guard board.setString("probe", forType: .string), board.string(forType: .string) == "probe" else { return false }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("document.pdf")
        let archive = root.appendingPathComponent("source.zip")
        try Data([1, 2]).write(to: pdf)
        try Data([3, 4]).write(to: archive)
        let files = Clip(text: "", content: .files([pdf.path, archive.path]))
        try ClipboardCodec.write(files, to: board)
        XCTAssertEqual(ClipboardCodec.read(from: board)?.content, files.content)
        let imageRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = imageRep.representation(using: .png, properties: [:])!
        let image = Clip(text: "", content: .image(png))
        try ClipboardCodec.write(image, to: board)
        XCTAssertEqual(ClipboardCodec.read(from: board)?.content, image.content)
        let rawPDF = Clip(text: "", content: .pdf(Data("%PDF-1.4\n%%EOF".utf8)))
        try ClipboardCodec.write(rawPDF, to: board)
        XCTAssertEqual(ClipboardCodec.read(from: board)?.content, rawPDF.content)
        try ClipboardCodec.write(Clip(text: "safe"), to: board)
        do {
            try ClipboardCodec.write(Clip(text: "", content: .files([root.appendingPathComponent("missing").path])), to: board)
            preconditionFailure("Missing file should fail")
        } catch { XCTAssertEqual(board.string(forType: .string), "safe") }
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        XCTAssertEqual(ClipboardCodec.read(from: board), nil)
        return true
    }
}
