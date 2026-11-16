import Cocoa

enum WindowAnimationInterruptionPolicy {
    static func shouldCancel(activatedPID: pid_t?, targetPID: pid_t) -> Bool {
        guard let activatedPID else { return false }
        return activatedPID != targetPID
    }
}
