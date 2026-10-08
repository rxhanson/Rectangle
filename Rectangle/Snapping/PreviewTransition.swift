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

final class WindowAnimationCaptureGate {
    static let shared = WindowAnimationCaptureGate()
    private var owners = Set<UUID>()
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    var isPaused: Bool { !owners.isEmpty }

    func begin(_ owner: UUID) { owners.insert(owner) }
    func end(_ owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    @MainActor func waitUntilIdle() async {
        while isPaused && !Task.isCancelled {
            let id = UUID()
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled || !isPaused { continuation.resume() }
                    else { waiters[id] = continuation }
                }
            }, onCancel: { [weak self] in
                Task { @MainActor in self?.waiters.removeValue(forKey: id)?.resume() }
            })
        }
    }
}
