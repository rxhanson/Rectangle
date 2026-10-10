import Cocoa

extension AccessibilityElement {
    var rememberedMinimumSize: CGSize? {
        WindowSizeConstraints.shared.rememberedMinimum(for: self)
    }
}
