import Foundation

enum ClipContent: Codable, Equatable {
    case files([String])
    case image(Data)
    case pdf(Data)
}

struct Clip: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var copiedAt = Date()
    var pinned = false
    // Optional so histories created by version 1 continue to decode.
    var content: ClipContent? = nil

    var title: String {
        switch content {
        case .files(let paths):
            let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
            return names.joined(separator: ", ")
        case .image: return "Copied image"
        case .pdf: return "Copied PDF"
        case nil: break
        }
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }

    var lineCount: Int { text.components(separatedBy: "\n").count }
    var detail: String {
        switch content {
        case .files(let paths): return "\(paths.count) \(paths.count == 1 ? "file" : "files")"
        case .image(let data): return "Image · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        case .pdf(let data): return "PDF · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        case nil: return "\(lineCount) \(lineCount == 1 ? "line" : "lines")"
        }
    }
    var searchableText: String {
        if case .files(let paths) = content { return paths.joined(separator: "\n") }
        return title + "\n" + text
    }
    var symbol: String {
        switch content {
        case .files: return "doc.on.doc"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case nil: return "text.alignleft"
        }
    }
}

struct ClipHistory: Codable {
    var clips: [Clip] = []
    static let limit = 200

    mutating func record(_ text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        record(Clip(text: text), at: date)
    }

    mutating func record(_ incoming: Clip, at date: Date = Date()) {
        if let index = clips.firstIndex(where: { $0.text == incoming.text && $0.content == incoming.content }) {
            var clip = clips.remove(at: index)
            clip.copiedAt = date
            clips.insert(clip, at: 0)
        } else {
            var clip = incoming
            clip.copiedAt = date
            clips.insert(clip, at: 0)
        }
        var unpinned = 0
        var storedBytes = 0
        clips = clips.filter { clip in
            if clip.pinned { return true }
            unpinned += 1
            switch clip.content {
            case .image(let data), .pdf(let data): storedBytes += data.count
            default: storedBytes += clip.text.utf8.count
            }
            return unpinned <= Self.limit && storedBytes <= 100_000_000
        }
    }

    func export(ids: Set<UUID>) -> String {
        clips.filter { ids.contains($0.id) && $0.content == nil }
            .sorted { $0.copiedAt < $1.copiedAt }
            .map(\.text).joined(separator: "\n\n")
    }
}

// A fixed order prevents cycling from reshuffling when a clip is put on the clipboard.
struct ClipCycle {
    private(set) var ids: [UUID] = []
    private(set) var index = 0

    mutating func reset(_ ids: [UUID]) { self.ids = ids; index = 0 }
    mutating func move(_ direction: Int) -> UUID? {
        guard !ids.isEmpty else { return nil }
        index = (index + direction % ids.count + ids.count) % ids.count
        return ids[index]
    }
}
