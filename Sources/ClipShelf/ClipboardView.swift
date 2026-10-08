import SwiftUI
import AppKit
import PDFKit

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    let dismiss: () -> Void
    @State private var query = ""
    @State private var focused: UUID?
    @State private var selected: Set<UUID> = []
    @State private var pinnedOnly = false
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool

    private var visible: [Clip] {
        store.clips.filter {
            (!pinnedOnly || $0.pinned) && (query.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(query))
        }
    }
    private var current: Clip? {
        visible.first(where: { $0.id == focused }) ?? visible.first
    }
    private var exportIDs: Set<UUID> {
        selected.isEmpty ? Set(current.map { [$0.id] } ?? []) : selected
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.shortcutErrors.isEmpty {
                Text(store.shortcutErrors.joined(separator: "\n"))
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.bottom, 10)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search code, files, and anything copied", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { copyCurrent() }
                    .accessibilityLabel("Search clipboard history")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear search")
                }
                Toggle(isOn: $pinnedOnly) {
                    Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                }
                .toggleStyle(.button).help("Show pinned clips")
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 18).padding(.bottom, 14)

            Divider()
            HStack(spacing: 0) {
                historyList.frame(width: 310)
                Divider()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 0.2, green: 0.65, blue: 0.48))
        .onReceive(NotificationCenter.default.publisher(for: .clipShelfOpened)) { _ in
            query = ""
            focused = visible.first?.id
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipShelfMove)) { notification in
            move(notification.userInfo?["direction"] as? Int ?? 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipShelfChoose)) { _ in copyCurrent() }
        .onChange(of: query) { _ in focused = visible.first?.id }
        .onChange(of: pinnedOnly) { _ in focused = visible.first?.id }
        .onChange(of: store.clips) { clips in
            selected.formIntersection(Set(clips.map(\.id)))
            if !visible.contains(where: { $0.id == focused }) { focused = visible.first?.id }
        }
        .onExitCommand { dismiss() }
        .alert("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear all", role: .destructive) { store.clear(); selected = [] }
        } message: {
            Text("This deletes all saved clips, including pinned ones. Your current system clipboard stays available.")
        }
        .alert("ClipShelf", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button("OK") { store.storageError = nil }
        } message: { Text(store.storageError ?? "") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 42, height: 42)
            } else {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 21))
                    .foregroundStyle(.mint).frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ClipShelf").font(.system(size: 20, weight: .semibold))
                Text("⌘⌥↑ ↓ to cycle from your editor").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(store.paused ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(store.paused ? "Paused" : "Listening").font(.system(size: 11))
            }.foregroundStyle(.secondary)
            Button { store.paused.toggle() } label: {
                Image(systemName: store.paused ? "play.fill" : "pause.fill")
            }.help(store.paused ? "Resume clipboard capture" : "Pause clipboard capture")
            Text("⌘⇧V").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }.padding(18)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(pinnedOnly ? "PINNED" : "RECENT").font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("\(visible.count)").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? (pinnedOnly ? "No pinned clips" : "Copy something to start") : "No matching clips")
                        .font(.system(size: 13, weight: .medium))
                    Text("Text, images, PDFs, and Finder files live here.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                List(selection: $focused) {
                    ForEach(visible) { clip in
                        HStack(alignment: .top, spacing: 9) {
                            Button {
                                if selected.contains(clip.id) { selected.remove(clip.id) }
                                else { selected.insert(clip.id) }
                            } label: {
                                Image(systemName: selected.contains(clip.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selected.contains(clip.id) ? Color.accentColor : Color.secondary)
                            }.buttonStyle(.borderless).help("Select for file export")
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: clip.symbol).foregroundStyle(.secondary).frame(width: 15)
                                    Text(clip.title).font(.system(size: 12, design: clip.content == nil ? .monospaced : .default))
                                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                HStack(spacing: 5) {
                                    Text(clip.copiedAt, style: .relative)
                                    Text("· \(clip.detail)")
                                    Spacer(minLength: 0)
                                    if clip.pinned { Image(systemName: "pin.fill") }
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 7).tag(clip.id).id(clip.id)
                        .contextMenu {
                            Button("Use clip") { if store.copy(clip) { dismiss() } }
                            Button(clip.pinned ? "Unpin" : "Pin") { store.togglePin(clip.id) }
                            Button("Save to file…") { store.export([clip.id]) }
                            Divider()
                            Button("Delete", role: .destructive) { store.remove([clip.id]) }
                        }
                    }
                }.listStyle(.sidebar)
                    .onChange(of: focused) { id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let clip = current {
                HStack {
                    Text("PREVIEW").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.togglePin(clip.id) } label: {
                        Image(systemName: clip.pinned ? "pin.fill" : "pin")
                    }.buttonStyle(.borderless).help(clip.pinned ? "Unpin clip" : "Pin clip")
                    Button { store.remove([clip.id]) } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless).help("Delete clip")
                }.padding(.bottom, 14)
                ClipPreview(clip: clip)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text(clip.content == nil ? "\(clip.text.count) characters" : clip.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use clip ↵") { copyCurrent() }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }.padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "curlybraces").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("A little shelf for your snippets").font(.system(size: 14, weight: .medium))
                    Text("↑ ↓ to choose · Return to use · ⌘V to paste")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if selected.isEmpty {
                Text("↑ ↓ choose   ↵ use   esc close").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("\(selected.count) selected").font(.system(size: 11, weight: .medium))
                Button("Reset") { selected = [] }.buttonStyle(.link).font(.system(size: 11))
            }
            Spacer()
            Button(selected.isEmpty ? "Save clip…" : "Save \(selected.count) clips…") { store.export(exportIDs) }
                .disabled(exportIDs.isEmpty).keyboardShortcut("s", modifiers: .command)
            Menu {
                Text("ClipShelf \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                Button("Test cycling preview") {
                    NotificationCenter.default.post(name: .clipShelfPreview, object: nil)
                }
                Divider()
                Text("⌘⌥↓ / ⌘⌥↑ cycle without opening")
                Text("Stores up to 200 recent clips plus pins locally")
                Button("Clear history…") { confirmClear = true }.disabled(store.clips.isEmpty)
                Divider()
                Button("Quit ClipShelf") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 22)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func copyCurrent() {
        guard let current else { return }
        if store.copy(current) { dismiss() }
    }

    private func move(_ direction: Int) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex(where: { $0.id == current?.id }) ?? 0
        focused = visible[(index + direction + visible.count) % visible.count].id
    }
}

struct ClipPreview: View {
    let clip: Clip
    var compact = false

    var body: some View {
        switch clip.content {
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
            } else { Text("Image preview unavailable").foregroundStyle(.secondary) }
        case .pdf(let data):
            if let page = PDFDocument(data: data)?.page(at: 0) {
                Image(nsImage: page.thumbnail(of: NSSize(width: 500, height: 500), for: .mediaBox))
                    .resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
            } else { Text("PDF preview unavailable").foregroundStyle(.secondary) }
        case .files(let paths):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 13, weight: .medium))
                                if !compact {
                                    Text(path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                if !FileManager.default.fileExists(atPath: path) {
                                    Text("Original file unavailable").font(.system(size: 10)).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if !compact {
                        Text("File clips link to the originals. Keep the files in place to paste them later.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        case nil:
            if compact {
                Text(clip.text).font(.system(size: 13, design: .monospaced)).lineLimit(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(clip.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                }
            }
        }
    }
}
