// MyWayTheme colors (Theme.kt). Teal brand, light/dark surfaces.
import SwiftUI

enum Brand {
    static let teal = Color(hex: 0x00A77D)
    static let tealBright = Color(hex: 0x00C99D)
    static let tealDeep = Color(hex: 0x00795A)

    static func background(_ dark: Bool) -> Color { dark ? Color(hex: 0x0F172A) : Color(hex: 0xF0FDFE) }
    static func surface(_ dark: Bool) -> Color { dark ? Color(hex: 0x1E293B) : .white }
    static func onSurface(_ dark: Bool) -> Color { dark ? Color(hex: 0xF1F5F9) : Color(hex: 0x1E293B) }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
