import SwiftUI

/// The settings examples use the same untinted system style as the real UI.
struct BlurExampleSurface: View {
    var cornerRadius: CGFloat
    var decorated = false
    @AppStorage("liquidGlassForBlur") private var liquidGlass = false

    @AppStorage("blurAppearance") private var blurAppearance = BlurAppearance.system.rawValue
    @Environment(\.colorScheme) private var inheritedColorScheme

    private var materialColorScheme: ColorScheme {
        switch BlurAppearance(rawValue: blurAppearance) ?? .system {
        case .system: return inheritedColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        Group {
            if #available(macOS 26, *), liquidGlass {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        if decorated {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .shadow(color: .black.opacity(decorated ? 0.10 : 0), radius: 5, y: 2)
            }
        }
        .environment(\.colorScheme, materialColorScheme)
    }
}
