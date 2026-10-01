import AppKit
import SwiftUI

enum Theme {
    static let background = Color(hex: 0x171A1D)
    static let editor = Color(hex: 0x1C1F23)
    static let panel = Color(hex: 0x22262B)
    static let border = Color(hex: 0x343A41)
    static let text = Color(hex: 0xE0E2E5)
    static let secondary = Color(hex: 0x9DA6B2)
    static let muted = Color(hex: 0x737D89)
    static let accent = Color(hex: 0xD9B97C)
    static let green = Color(hex: 0xA3BE8C)
    static let red = Color(hex: 0xE29A9A)
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
}

@MainActor
enum IconStore {
    private static var images: [String: NSImage] = [:]
    private static var missing: Set<String> = []
    static func image(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        if missing.contains(name) { return nil }
        var directory = Bundle.main.resourceURL?.appendingPathComponent("Icons")
        #if DEBUG
        if directory.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Icons")
        }
        #endif
        guard let url = directory?.appendingPathComponent("\(name).pdf"), let image = NSImage(contentsOf: url) else {
            missing.insert(name); return nil
        }
        // Native menu labels may use the NSImage directly and ignore the
        // surrounding SwiftUI frame. PDF assets have a 256 pt artboard.
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        images[name] = image
        return image
    }
}

struct PhosphorIcon: View {
    let name: String
    var size: CGFloat = 18
    var body: some View {
        if let image = IconStore.image(name) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
        } else { Color.clear.frame(width: size, height: size).accessibilityHidden(true) }
    }
}

struct QuietButton: View {
    let icon: String
    let help: String
    var shortcut: String? = nil
    var detail: String? = nil
    var active = false
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            PhosphorIcon(name: icon).foregroundStyle(active ? Theme.accent : Theme.secondary)
                .frame(width: 30, height: 30)
                .background(hovering || active ? Theme.border.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityLabel(help).learningHelp(help, shortcut: shortcut, detail: detail).onHover { hovering = $0 }
    }
}

struct Keycap: View {
    let value: String
    var body: some View {
        Text(value).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Theme.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border.opacity(0.7)))
    }
}
