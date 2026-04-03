import SwiftUI

/// Adaptive glass colors that work in both light and dark mode.
enum GlassColors {
    /// Card background: white 72% in light, dark 20% in dark
    static var cardBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.white.withAlphaComponent(0.72)
        })
    }

    /// Card border
    static var cardBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.white.withAlphaComponent(0.3)
        })
    }

    /// Dropdown trigger background
    static var dropdownBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.white.withAlphaComponent(0.6)
        })
    }

    /// Dropdown expanded panel
    static var dropdownPanel: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.1)
                : NSColor.white.withAlphaComponent(0.95)
        })
    }

    /// Subtle border for dropdowns
    static var dropdownBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.1)
                : NSColor.black.withAlphaComponent(0.05)
        })
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(GlassColors.cardBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}
