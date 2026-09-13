import Foundation

/// These jobs run on the main queue in the app. Tests control both time and delivery order.
struct WindowFrostScheduler {
    var now: () -> TimeInterval
    var after: (TimeInterval, @escaping () -> Void) -> Void

    static let main = WindowFrostScheduler(now: { ProcessInfo.processInfo.systemUptime }, after: { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    })
}

/// Owns the hold/fade deadlines, independently of AppKit's animation completion timing.
final class WindowFrostDismissal {
    static let hold: TimeInterval = 0.05
    static let fade: TimeInterval = 0.12
    static let timeout: TimeInterval = 0.55
    private let scheduler: WindowFrostScheduler
    private(set) var token: UUID?
    private(set) var started: TimeInterval = 0

    init(scheduler: WindowFrostScheduler = .main) { self.scheduler = scheduler }

    func begin(fade: @escaping (TimeInterval, @escaping () -> Void) -> Void,
               finish: @escaping (_ timedOut: Bool) -> Void) {
        guard token == nil else { return }
        let id = UUID()
        token = id
        started = scheduler.now()
        scheduler.after(Self.hold) { [weak self] in
            guard let self, self.token == id else { return }
            fade(Self.fade) { [weak self] in
                guard let self, self.token == id else { return }
                self.token = nil
                finish(false)
            }
        }
        scheduler.after(Self.timeout) { [weak self] in
            guard let self, self.token == id else { return }
            self.token = nil
            finish(true)
        }
    }

    func invalidate() { token = nil }
}

/// A validation reply and its deadline compete for one decision, including at equal timestamps.
final class FrostedRestoreDragValidation {
    enum Outcome: Equatable { case accepted, rejected, timedOut }
    private let scheduler: WindowFrostScheduler
    private var completion: ((Outcome) -> Void)?
    private var started: TimeInterval?
    private var deadline: TimeInterval = 0

    init(scheduler: WindowFrostScheduler = .main) { self.scheduler = scheduler }

    func begin(timeout: TimeInterval, completion: @escaping (Outcome) -> Void) {
        precondition(started == nil)
        started = scheduler.now()
        deadline = started! + timeout
        self.completion = completion
        scheduler.after(timeout) { [weak self] in self?.resolve(.timedOut) }
    }

    func complete(valid: Bool) {
        guard let started else { return }
        let now = scheduler.now()
        resolve(now > deadline ? .timedOut : (valid && now >= started ? .accepted : .rejected))
    }

    func cancel() { completion = nil }

    private func resolve(_ outcome: Outcome) {
        let pending = completion
        completion = nil
        pending?(outcome)
    }
}

/// Called under the controller's lock; AX work itself runs outside that lock.
struct FrostedRestoreDragAdmission<Candidate> {
    enum GestureState: Equatable { case idle, active, draining }
    enum Completion: Equatable { case stored, discarded, refresh }
    private(set) var candidate: Candidate?
    private var generation: UInt64 = 0
    struct Inspection: Equatable { fileprivate let generation: UInt64; private let id = UUID() }
    private var inspection: Inspection?
    private var refreshRequested = false
    var isInspecting: Bool { inspection != nil }

    mutating func clearCandidate() { candidate = nil }

    mutating func invalidate(refreshAfterInspection: Bool = false) {
        generation &+= 1
        candidate = nil
        refreshRequested = refreshRequested || (isInspecting && refreshAfterInspection)
    }

    mutating func beginInspection(gesture: GestureState, buttonDown: Bool) -> Inspection? {
        guard !isInspecting, gesture != .active, !buttonDown || gesture == .draining else { return nil }
        let next = Inspection(generation: generation)
        inspection = next
        return next
    }

    mutating func completeInspection(_ id: Inspection, candidate: Candidate?, canStore: Bool) -> Completion {
        guard inspection == id else { return .discarded }
        inspection = nil
        if refreshRequested {
            refreshRequested = false
            return .refresh
        }
        guard generation == id.generation, canStore else { return .discarded }
        self.candidate = candidate
        return .stored
    }
}
