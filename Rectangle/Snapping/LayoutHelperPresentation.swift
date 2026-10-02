import Cocoa

enum PreviewLayerTransition {
    static let deceleration = CAMediaTimingFunction(controlPoints: 1 / 3, 1, 2 / 3, 1)
    static let smoothstep = CAMediaTimingFunction(controlPoints: 1 / 3, 0, 2 / 3, 1)

    static func set(_ layer: CALayer, _ key: String, to value: Any, duration: TimeInterval,
                    timing: CAMediaTimingFunction = PreviewLayerTransition.deceleration) {
        let animationKey = "preview." + key
        let current = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: key)
        layer.removeAnimation(forKey: animationKey)
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = current
            animation.toValue = value
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: animationKey)
        }
        CATransaction.commit()
    }
}

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

enum ImmediateFrameOrder {
    static func sizeFirst(from current: CGRect, to target: CGRect, bounds: CGRect,
                          acrossScreens: Bool, preferSizeFirst: Bool) -> Bool {
        // Moving an off-screen window first can make the system resize it against the Dock.
        if acrossScreens || !bounds.insetBy(dx: -1, dy: -1).contains(current) { return true }
        func overflow(_ frame: CGRect) -> CGFloat {
            max(0, bounds.minX - frame.minX) + max(0, frame.maxX - bounds.maxX)
                + max(0, bounds.minY - frame.minY) + max(0, frame.maxY - bounds.maxY)
        }
        let resized = overflow(CGRect(origin: current.origin, size: target.size))
        let moved = overflow(CGRect(origin: target.origin, size: current.size))
        if abs(resized - moved) > 1 { return resized < moved }
        return preferSizeFirst
    }
}
