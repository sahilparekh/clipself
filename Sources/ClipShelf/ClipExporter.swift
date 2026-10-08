import Foundation

enum ClipExporter {
    static func defaultName(for clip: Clip) -> String {
        switch clip.content {
        case .image: return "image.png"
        case .pdf: return "document.pdf"
        case .files(let paths): return paths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file"
        case nil: return "clips.txt"
        }
    }

    static func write(_ clip: Clip, to url: URL, replaceExisting: Bool = false) throws {
        switch clip.content {
        case .image(let data), .pdf(let data): try data.write(to: url, options: .atomic)
        case .files(let paths):
            guard let path = paths.first, paths.count == 1 else { throw ClipboardError.missingFile }
            let source = URL(fileURLWithPath: path)
            if source.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL { return }
            if replaceExisting && FileManager.default.fileExists(atPath: url.path) {
                let temporary = url.deletingLastPathComponent().appendingPathComponent(".clipshelf-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.copyItem(at: source, to: temporary)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.copyItem(at: source, to: url)
            }
        case nil: try clip.text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func writeFolder(_ clips: [Clip], to directory: URL) throws {
        var created: [URL] = []
        do {
            for (index, clip) in clips.sorted(by: { $0.copiedAt < $1.copiedAt }).enumerated() {
                let items: [Clip]
                if case .files(let paths) = clip.content {
                    items = paths.map { Clip(text: "", content: .files([$0])) }
                } else { items = [clip] }
                for item in items {
                    let name = "\(index + 1)-" + defaultName(for: item)
                    var target = directory.appendingPathComponent(name)
                    var suffix = 2
                    while FileManager.default.fileExists(atPath: target.path) {
                        let base = (name as NSString).deletingPathExtension
                        let ext = (name as NSString).pathExtension
                        target = directory.appendingPathComponent("\(base)-\(suffix)" + (ext.isEmpty ? "" : ".\(ext)"))
                        suffix += 1
                    }
                    try write(item, to: target)
                    created.append(target)
                }
            }
        } catch {
            // Only roll back files this operation created, never existing user files.
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
