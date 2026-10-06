import SwiftUI

/// The settings examples use the same untinted system style as the real UI.
struct BlurExampleSurface: View {
    var cornerRadius: CGFloat
    var decorated = false
    @AppStorage("liquidGlassForBlur") private var liquidGlass = false

    var body: some View {
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
}
