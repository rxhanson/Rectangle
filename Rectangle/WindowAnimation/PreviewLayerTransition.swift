import Cocoa
import QuartzCore

enum PreviewLayerTransition {
    static let deceleration = CAMediaTimingFunction(controlPoints: 1 / 3, 1, 2 / 3, 1)
    static let smoothstep = CAMediaTimingFunction(controlPoints: 1 / 3, 0, 2 / 3, 1)

    static func set(_ layer: CALayer, _ key: String, to value: Any, duration: TimeInterval,
                    timing: CAMediaTimingFunction = WindowPreviewDeceleration.timingFunction) {
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
