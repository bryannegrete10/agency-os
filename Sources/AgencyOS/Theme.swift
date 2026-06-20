import SwiftUI

// Dark-glass design tokens. Follows baseline-ui conventions: one fixed spacing
// scale (no arbitrary values), one radius scale, restrained palette.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    static let bg = Color(red: 0.055, green: 0.065, blue: 0.085)
    static let panel = Color.white.opacity(0.04)
    static let panelStroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let accent = Color(red: 0.49, green: 0.55, blue: 1.0)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
}

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}

extension View {
    func glassPanel() -> some View { modifier(GlassPanel()) }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.textSecondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
