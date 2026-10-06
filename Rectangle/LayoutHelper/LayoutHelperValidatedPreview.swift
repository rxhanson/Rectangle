import Cocoa
import ScreenCaptureKit

/// Only worker-side validation constructs images delivered to the main owner.
struct LayoutHelperValidatedPreview {
    let image: CGImage
    init?(_ image: CGImage) {
        guard LayoutHelperPreviewValidation.isValid(image) else { return nil }
        self.image = image
    }
}
