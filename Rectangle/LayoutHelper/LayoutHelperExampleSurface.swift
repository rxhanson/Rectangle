import AppKit
import SwiftUI

struct LayoutHelperExampleSurface: View {
    var cornerRadius: CGFloat
    var decorated = false
    var body: some View {
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
