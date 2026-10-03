import Cocoa

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

enum WindowAnimationSize {
    static func animationSize(_ requested: CGSize, origin: CGSize, hint: CGSize?) -> CGSize {
        guard let hint else { return requested }
        func axis(_ requested: CGFloat, _ origin: CGFloat, _ hint: CGFloat) -> CGFloat {
            guard hint.isFinite, hint > 0, hint <= origin + 2, requested < origin else { return requested }
            return max(requested, min(origin, hint))
        }
        return CGSize(width: axis(requested.width, origin.width, hint.width),
                      height: axis(requested.height, origin.height, hint.height))
    }
}
