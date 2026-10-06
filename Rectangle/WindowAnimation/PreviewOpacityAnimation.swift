import Cocoa
import QuartzCore

/// Cancelling a fade invalidates its completion before removing the animation.
final class PreviewOpacityAnimation {
    private weak var layer: CALayer?
    private var generation = UUID()
    private(set) var isAnimating = false

    func cancel() {
        generation = UUID()
        isAnimating = false
        if let layer {
            let opacity = layer.presentation()?.opacity ?? layer.opacity
            PreviewLayerTransition.set(layer, "opacity", to: opacity, duration: 0)
        }
    }

    func set(_ layer: CALayer, to opacity: CGFloat, duration: TimeInterval,
             timing: CAMediaTimingFunction = PreviewLayerTransition.deceleration,
             completion: (() -> Void)? = nil) {
        cancel()
        self.layer = layer
        let generation = generation
        guard duration > 0, abs(CGFloat(layer.opacity) - opacity) > 0.001 else {
            PreviewLayerTransition.set(layer, "opacity", to: Float(opacity), duration: 0)
            completion?()
            return
        }
        isAnimating = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.isAnimating = false
                completion?()
            }
        }
        PreviewLayerTransition.set(layer, "opacity", to: Float(opacity), duration: duration, timing: timing)
        CATransaction.commit()
    }
}
