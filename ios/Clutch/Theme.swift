import SwiftUI
import UIKit

/// Brand palette. `strawberry` and `matcha` come from the design reference;
/// the AccentColor asset mirrors `matcha` for system tinting.
extension Color {
    /// #F9D1D9 — soft pink.
    static let strawberry = Color(red: 0.976, green: 0.820, blue: 0.851)
    /// #838F58 — muted olive.
    static let matcha = Color(red: 0.514, green: 0.561, blue: 0.345)

    /// The Garden's two-tone text palette: a near-black warm brown for
    /// anything primary/active, a muted taupe for secondary labels.
    static let ink = Color(red: 0.29, green: 0.23, blue: 0.20)
    static let mutedInk = Color(red: 0.61, green: 0.54, blue: 0.50)
}

/// Named fonts that need more than a plain `.custom(...)` call.
enum ClutchFont {
    /// Sofia, a curly monoline script, for the "your name" heading.
    /// Falls back to the script wordmark font if the file ever fails to
    /// load.
    static func nameHeading(size: CGFloat) -> Font {
        let name = UIFont(name: "Sofia-Regular", size: size) != nil ? "Sofia-Regular" : "PinyonScript-Regular"
        return .custom(name, size: size)
    }
}
