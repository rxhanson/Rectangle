import Cocoa
import QuartzCore

/// Advances by elapsed time, skipping missed frames.
final class WindowFrameAnimation {
    let destination: CGRect
    private let origin: CGRect
    private let startTime: TimeInterval
    private let duration: TimeInterval
    private let offset: () -> CGPoint
    private let curve: (Double) -> CGFloat
    private let write: (CGRect, CGFloat) -> Bool
    private let finishNotBefore: () -> TimeInterval
    private let finishedEarly: () -> Bool
    private let finalize: ((CGRect) -> Void)?
    private let cleanup: () -> Void
    private let completion: (CGRect) -> Void
    private let maximumFrameInterval: (() -> TimeInterval)?
    private let maximumDuration: TimeInterval?
    private let didApplyFrame: () -> Bool
    private let independentSizeProgress: Bool
    private let catchesUp: Bool
    private var previousTime: TimeInterval
    private var elapsed: TimeInterval = 0
    private(set) var isFinished = false

    var remainingDuration: TimeInterval { max(0, duration - elapsed) }

    init(from: CGRect, to: CGRect, startTime: TimeInterval, duration: TimeInterval,
         offset: @escaping () -> CGPoint = { .zero },
         curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
         maximumFrameInterval: (() -> TimeInterval)? = nil,
         maximumDuration: TimeInterval? = nil,
         didApplyFrame: @escaping () -> Bool = { true },
         independentSizeProgress: Bool = false,
         catchesUp: Bool = false,
         write: @escaping (CGRect, CGFloat) -> Bool,
         finishNotBefore: @escaping () -> TimeInterval = { -.infinity },
         finishedEarly: @escaping () -> Bool = { false },
         finalize: ((CGRect) -> Void)? = nil,
         cleanup: @escaping () -> Void,
         completion: @escaping (CGRect) -> Void) {
        origin = from
        destination = to
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
        self.curve = curve
        self.maximumFrameInterval = maximumFrameInterval
        self.maximumDuration = maximumDuration
        self.didApplyFrame = didApplyFrame
        self.independentSizeProgress = independentSizeProgress
        self.catchesUp = catchesUp
        previousTime = startTime
        self.write = write
        self.finishNotBefore = finishNotBefore
        self.finishedEarly = finishedEarly
        self.finalize = finalize
        self.cleanup = cleanup
        self.completion = completion
    }

    func tick(at time: TimeInterval) {
        guard !isFinished else { return }
        if let maximumDuration, time - startTime >= maximumDuration {
            finish()
            return
        }
        let previousElapsed = elapsed
        if let maximumFrameInterval {
            // Slow Accessibility replies must not turn the next frame into a
            // catch-up jump when a caller opts into bounded playback steps.
            let delta = max(0, time - previousTime)
            let debt = max(0, previousTime - startTime - elapsed)
            let catchUp = catchesUp && delta <= 0.025 ? min(0.004, debt * 0.25) : 0
            elapsed += min(delta + catchUp, max(0, maximumFrameInterval()))
        } else {
            elapsed = max(0, time - startTime)
        }
        previousTime = max(previousTime, time)
        let progress = duration > 0 ? min(1, elapsed / duration) : 1
        if progress >= 1 && time >= finishNotBefore() {
            finish()
            return
        }
        let eased = curve(progress)
        let sizeProgress = independentSizeProgress && duration > 0 ? min(1, max(progress, (time - startTime) / duration)) : progress
        let sizeEased = curve(sizeProgress)
        let delta = offset()
        let frame = CGRect(x: origin.minX + (destination.minX - origin.minX) * eased + delta.x,
                           y: origin.minY + (destination.minY - origin.minY) * eased + delta.y,
                           width: origin.width + (destination.width - origin.width) * sizeEased,
                           height: origin.height + (destination.height - origin.height) * sizeEased)
        let accepted = write(frame, eased)
        if !didApplyFrame() { elapsed = previousElapsed }
        if !accepted || finishedEarly() {
            // Let the normal mover settle the destination after a refused AX write.
            finish()
        }
    }

    func finish() {
        guard !isFinished else { return }
        let delta = offset()
        isFinished = true
        let finalFrame = destination.offsetBy(dx: delta.x, dy: delta.y)
        finalize?(finalFrame)
        cleanup()
        completion(finalFrame)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()
    }
}
