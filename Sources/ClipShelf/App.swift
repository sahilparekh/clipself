import AppKit
import Carbon
import SwiftUI

#if !DESIGN_PREVIEW
@main
struct ClipShelfApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let store = ClipboardStore()
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var hud: NSPanel?
    private var hudTimer: Timer?
    private var previewObserver: NSObjectProtocol?
    private let launchedAt = Date()
    private var shortcutEventCount = 0
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipShelf")
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 760, height: 560)
        popover.contentViewController = NSHostingController(rootView: ClipboardView(store: store, dismiss: { [weak self] in
            self?.closeAndRestore()
        }))
        previewObserver = NotificationCenter.default.addObserver(forName: .clipShelfPreview, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cycle(1) }
        }
        // A binary launched via `swift run` may not have our bundle identifier.
        // Retire old ClipShelf processes before registering the new shortcuts.
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            ($0.bundleIdentifier == "dev.clipshelf.app" || $0.executableURL?.lastPathComponent == "ClipShelf")
        }
        for app in others { app.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (others.isEmpty ? 0 : 1)) { [weak self] in
            guard let self else { return }
            self.installShortcuts()
            self.showHUD(title: "ClipShelf \(self.version) is ready", subtitle: "⌘⌥↑ ↓ to cycle · ⌘V to paste", clip: nil)
        }
    }

    private func installShortcuts() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x434C4950 else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                switch id.id {
                case 1: delegate.toggle()
                case 2: delegate.cycle(1)
                case 3: delegate.cycle(-1)
                default: break
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerResult == noErr else {
            store.shortcutErrors.append("Keyboard handler unavailable (\(handlerResult)). Restart ClipShelf.")
            return
        }
        let shortcuts: [(Int, Int, UInt32, String)] = [
            (kVK_ANSI_V, cmdKey | shiftKey, 1, "⌘⇧V"),
            (kVK_DownArrow, cmdKey | optionKey, 2, "⌘⌥↓"),
            (kVK_UpArrow, cmdKey | optionKey, 3, "⌘⌥↑")
        ]
        for (key, modifiers, id, label) in shortcuts {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(modifiers),
                                            EventHotKeyID(signature: 0x434C4950, id: id),
                                            GetEventDispatcherTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
            else { store.shortcutErrors.append("\(label) is unavailable (\(result)). Another app may be using it.") }
        }
        writeDiagnostics()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown,
                      event.window == self.popover.contentViewController?.view.window else { return false }
                if event.keyCode == UInt16(kVK_ANSI_Q),
                   event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
                    NSApp.terminate(nil)
                    return true
                }
                guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
                switch Int(event.keyCode) {
                case kVK_DownArrow, kVK_UpArrow:
                    NotificationCenter.default.post(name: .clipShelfMove, object: nil,
                                                    userInfo: ["direction": event.keyCode == UInt16(kVK_DownArrow) ? 1 : -1])
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    NotificationCenter.default.post(name: .clipShelfChoose, object: nil)
                case kVK_Escape: self.closeAndRestore()
                default: return false
                }
                return true
            }
            return handled ? nil : event
        }
    }

    @objc private func statusClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp, let button = item.button else { toggle(); return }
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open ClipShelf", action: #selector(toggle), keyEquivalent: "")
        open.target = self
        let older = menu.addItem(withTitle: "Cycle older clip  ⌘⌥↓", action: #selector(cycleOlder), keyEquivalent: "")
        older.target = self
        let newer = menu.addItem(withTitle: "Cycle newer clip  ⌘⌥↑", action: #selector(cycleNewer), keyEquivalent: "")
        newer.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit ClipShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @objc private func cycleOlder() { cycle(1) }
    @objc private func cycleNewer() { cycle(-1) }

    @objc func toggle() {
        if popover.isShown {
            closeAndRestore()
        } else if let button = item.button {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            NotificationCenter.default.post(name: .clipShelfOpened, object: nil)
        }
    }

    private func closeAndRestore() {
        popover.performClose(nil)
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        previousApp = nil
    }

    private func cycle(_ direction: Int) {
        shortcutEventCount += 1
        if popover.isShown { closeAndRestore() }
        if let (clip, position, count) = store.cycleClip(direction) {
            showHUD(title: clip.title, subtitle: clip.detail, clip: clip, position: position, count: count)
        } else {
            showHUD(title: store.storageError ?? "No clipboard history yet", subtitle: "Copy something to begin", clip: nil)
            store.storageError = nil
        }
    }

    private func showHUD(title: String, subtitle: String, clip: Clip?, position: Int = 0, count: Int = 0) {
        hudTimer?.invalidate()
        if hud == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 112),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.title = "ClipShelf cycling preview"
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            hud = panel
        }
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 112))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .vibrantDark)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        let content = NSHostingView(rootView: CycleHUD(title: title, subtitle: subtitle, clip: clip,
                                                      position: position, count: count))
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        hud?.contentView = glass
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            // Keep it steady while cycling. A new cycle starts in the farthest corner.
            if hud?.isVisible != true || !(hud.map { frame.contains($0.frame) } ?? false) ||
                (hud?.frame.contains(NSEvent.mouseLocation) ?? false) {
                let margin: CGFloat = 18
                let corners = [
                    NSPoint(x: frame.minX + margin, y: frame.minY + margin),
                    NSPoint(x: frame.maxX - 340 - margin, y: frame.minY + margin),
                    NSPoint(x: frame.minX + margin, y: frame.maxY - 112 - margin),
                    NSPoint(x: frame.maxX - 340 - margin, y: frame.maxY - 112 - margin)
                ]
                let pointer = NSEvent.mouseLocation
                let origin = corners.max { left, right in
                    let a = hypot(left.x + 170 - pointer.x, left.y + 56 - pointer.y)
                    let b = hypot(right.x + 170 - pointer.x, right.y + 56 - pointer.y)
                    return a < b
                }
                if let origin { hud?.setFrameOrigin(origin) }
            }
        }
        hud?.orderFrontRegardless()
        writeDiagnostics()
        hudTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hud?.orderOut(nil)
                self?.writeDiagnostics()
            }
        }
    }

    private func writeDiagnostics() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipShelf")
        let url = directory.appendingPathComponent("runtime.json")
        let values: [String: Any] = [
            "version": version, "launchedAt": launchedAt.timeIntervalSince1970,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "executable": Bundle.main.executableURL?.path ?? "unknown",
            "shortcutErrors": store.shortcutErrors,
            "registeredShortcuts": hotKeys.count,
            "cycleEvents": shortcutEventCount, "previewVisible": hud?.isVisible ?? false,
            "previewSize": [hud?.frame.width ?? 0, hud?.frame.height ?? 0]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let previewObserver { NotificationCenter.default.removeObserver(previewObserver) }
    }
}

extension Notification.Name {
    static let clipShelfOpened = Notification.Name("ClipShelfOpened")
    static let clipShelfMove = Notification.Name("ClipShelfMove")
    static let clipShelfChoose = Notification.Name("ClipShelfChoose")
    static let clipShelfPreview = Notification.Name("ClipShelfPreview")
}

struct CycleHUD: View {
    let title: String
    let subtitle: String
    let clip: Clip?
    let position: Int
    let count: Int
    private let mint = Color(red: 0.49, green: 0.91, blue: 0.77)
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: clip?.symbol ?? "square.stack.3d.up.fill").foregroundStyle(mint)
                Text(clip?.detail ?? "CLIPSHELF").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if count > 0 {
                    HStack(spacing: 3) {
                        Text("\(position)").foregroundStyle(mint)
                        Text("/ \(count)").foregroundStyle(.secondary)
                    }.font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
            HStack(spacing: 10) {
                if let image = thumbnail {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                }
                Text(clip?.content == nil && clip != nil ? (clip?.text ?? title) : title)
                    .font(.system(size: 12, weight: .medium, design: clip?.content == nil ? .monospaced : .default))
                    .lineLimit(2).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if clip?.pinned == true { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(mint) }
            }.frame(height: 36, alignment: .top)
            HStack(spacing: 4) {
                Text("⌘⌥ ↑ ↓").font(.system(size: 10, design: .monospaced))
                Text("cycle").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if clip != nil {
                    Text("⌘V").font(.system(size: 10, design: .monospaced)).foregroundStyle(mint)
                    Text("paste").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(width: 340, height: 112)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
            LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .environment(\.colorScheme, .dark)
    }

    private var thumbnail: NSImage? {
        switch clip?.content {
        case .image(let data), .pdf(let data): return NSImage(data: data)
        case .files(let paths): return paths.first.map { NSWorkspace.shared.icon(forFile: $0) }
        case nil: return nil
        }
    }
}

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.15)))
    }
}
