import SwiftUI
import UIKit

@MainActor
enum TabletTheme {
    static let nativeEditor = adaptive(light: 0xFFFFFF, dark: 0x1C1F23)
    static let nativeText = adaptive(light: 0x37474F, dark: 0xE0E2E5)
    static let nativeSecondary = adaptive(light: 0x586B75, dark: 0x9DA6B2)
    static let nativeAccent = adaptive(light: 0x673AB7, dark: 0xD9B97C)
    static let accent = Color(uiColor: nativeAccent)

    private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: 1,
            )
        }
    }
}
