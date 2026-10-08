import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor static func main() throws {
        let clip = Clip(text: "git log --oneline --graph --decorate\n\n# Inspect your last five commits\ngit diff HEAD~5..HEAD --stat")
        let view = CycleHUD(title: clip.title, subtitle: clip.detail, clip: clip, position: 3, count: 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: "dist/cycling-preview.png"))
        print("Rendered dist/cycling-preview.png")
    }
}
