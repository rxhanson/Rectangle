import Cocoa

/// Warning-only sampling uses WindowServer geometry so a stalled target app
/// cannot block the main run loop after an otherwise completed action.
enum WindowSizeWarningObservation {
    struct Source {
        let frame: () -> CGRect?
        let isCurrent: () -> Bool
    }

    static func sample(frame: @escaping () -> CGRect?, isCurrent: @escaping () -> Bool,
                       completion: @escaping (CGRect) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard isCurrent(), let first = frame() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard isCurrent(), let settled = frame(),
                      WindowGeometry.matches(first, settled, tolerance: 1) else { return }
                completion(settled)
            }
        }
    }
}
