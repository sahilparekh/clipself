import AppKit
import Combine

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var history = ClipHistory()
    @Published var paused = false {
        didSet { lastChange = NSPasteboard.general.changeCount }
    }
    @Published var storageError: String?
    @Published var shortcutErrors: [String] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let file: URL
    private var cycle = ClipCycle()

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipShelf", isDirectory: true)
        file = directory.appendingPathComponent("history.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) {
                history = try JSONDecoder().decode(ClipHistory.self, from: Data(contentsOf: file))
            }
        } catch {
            storageError = "Couldn’t load local history: \(error.localizedDescription)"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    var clips: [Clip] { history.clips }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        guard !paused else { return }
        cycle.reset([])
        guard let clip = ClipboardCodec.read(from: board) else { return }
        history.record(clip)
        persist()
    }

    @discardableResult
    func copy(_ clip: Clip, promote: Bool = true) -> Bool {
        let board = NSPasteboard.general
        do {
            try ClipboardCodec.write(clip, to: board)
            lastChange = board.changeCount
            if promote {
                history.record(clip)
                cycle.reset([])
                persist()
            }
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }

    func cycleClip(_ direction: Int) -> (Clip, Int, Int)? {
        poll() // Capture any new copy before deciding which history to cycle through.
        let ids = history.clips.map(\.id)
        if cycle.ids != ids { cycle.reset(ids) }
        guard let id = cycle.move(direction), let clip = clips.first(where: { $0.id == id }),
              copy(clip, promote: false) else { return nil }
        return (clip, cycle.index + 1, cycle.ids.count)
    }

    func togglePin(_ id: UUID) {
        guard let index = history.clips.firstIndex(where: { $0.id == id }) else { return }
        history.clips[index].pinned.toggle()
        persist()
    }

    func remove(_ ids: Set<UUID>) {
        history.clips.removeAll { ids.contains($0.id) }
        persist()
    }

    func clear() {
        history.clips.removeAll()
        persist()
    }

    func export(_ ids: Set<UUID>) {
        let clips = history.clips.filter { ids.contains($0.id) }
        guard !clips.isEmpty else { return }
        let allText = clips.allSatisfy { $0.content == nil }
        let fileGroup: Bool
        if case .files(let paths) = clips[0].content { fileGroup = paths.count > 1 }
        else { fileGroup = false }
        NSApp.activate(ignoringOtherApps: true)
        if !allText && (clips.count > 1 || fileGroup) {
            let panel = NSOpenPanel()
            panel.title = "Save clips to a folder"
            panel.prompt = "Save here"
            panel.message = "Each item is saved separately. Existing files are kept."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try ClipExporter.writeFolder(clips, to: url) }
            catch { storageError = "Couldn’t save clips: \(error.localizedDescription)" }
            return
        }
        let panel = NSSavePanel()
        panel.title = ids.count == 1 ? "Save clip" : "Save \(ids.count) clips"
        panel.nameFieldStringValue = ClipExporter.defaultName(for: clips[0])
        panel.message = allText ? "Clips are joined with a blank line, oldest first. Use any filename extension." : "Save this item to a file."
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if allText { try history.export(ids: ids).write(to: url, atomically: true, encoding: .utf8) }
            else { try ClipExporter.write(clips[0], to: url, replaceExisting: true) }
        } catch {
            storageError = "Couldn’t save clips: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            storageError = nil
        } catch {
            storageError = "Couldn’t save local history: \(error.localizedDescription)"
        }
    }
}
