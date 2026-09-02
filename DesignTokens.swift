import SwiftUI

enum Grid {
    static let x0_5: CGFloat = 4
    static let x1: CGFloat = 8
    static let x1_5: CGFloat = 12
    static let x2: CGFloat = 16
    static let x3: CGFloat = 24
    static let x4: CGFloat = 32
    static let x5: CGFloat = 40
    static let x6: CGFloat = 48
    static let x8: CGFloat = 64
}

enum LandlineColor {
    // Figma/window spec: #ABABAB at 60% over a blurred desktop backdrop.
    static let windowBase = Color(red: 171.0 / 255.0, green: 171.0 / 255.0, blue: 171.0 / 255.0)
    static let windowTint = windowBase.opacity(0.60)

    static let panel = Color(red: 0.08, green: 0.085, blue: 0.083)
    static let panelSoft = Color(red: 0.13, green: 0.135, blue: 0.132)
    static let inactive = Color(red: 0.47, green: 0.49, blue: 0.47)
    static let green = Color(red: 0.02, green: 0.75, blue: 0.22)
    static let red = Color(red: 1.0, green: 0.34, blue: 0.33)

    // Figma WT Max VU zones. These are kept separate from the broader
    // interface colours so restoring the meter warning colours does not
    // unexpectedly alter the PTT button or other existing controls.
    static let vuGreen = Color(red: 23.0 / 255.0, green: 178.0 / 255.0, blue: 57.0 / 255.0)   // #17B239
    static let vuOrange = Color(red: 255.0 / 255.0, green: 150.0 / 255.0, blue: 1.0 / 255.0) // #FF9601
    static let vuRed = Color(red: 255.0 / 255.0, green: 97.0 / 255.0, blue: 87.0 / 255.0)    // #FF6157

    static let white = Color.white
}
