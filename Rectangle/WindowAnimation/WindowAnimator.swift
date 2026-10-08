import Cocoa
import QuartzCore

/// Lifecycle and display callbacks run on main; animation writes use one serial
/// worker. When busy, the worker skips old frames and uses the latest timestamp.
final class WindowAnimator {
    static let shared = WindowAnimator()

    static var enabled: Bool {
        Defaults.experimentalWindowAnimations.enabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !NSWorkspace.shared.isVoiceOverEnabled
            && !NSWorkspace.shared.isSwitchControlEnabled
    }


    func finishForNewDrag() { cancel() }


    typealias WindowLookup = (pid_t, CGWindowID, TimeInterval, AXUIElement?, () -> Bool) -> WindowAccessibilityLookup.Result
    private struct Active {
        let element: AccessibilityElement
        let destination: CGRect
        let request: WindowAnimationRequest
        let offset: () -> CGPoint
        let pid: pid_t
    }
    private let queue: DispatchQueue
    private var active: Active?
    private var retiring: [(AccessibilityElement, CGRect, WindowAnimationRequest)] = []
    private var displayCleanup: (() -> Void)?
    private var generation: UInt64 = 0
    private var tickPending = false
    private var nextTick: TimeInterval = 0
    private var pacing = WindowAnimationPacing(maximumRate: 60)
    private var mouseMonitor: Any?
    private var observation: WindowAnimationObservation?
    private var responses = WindowAnimationResponseHistory()
    private var observingLifecycle = false
    private func observeLifecycle() {
        guard !observingLifecycle else { return }
        observingLifecycle = true
        for name in [Notification.Name.windowAnimationPreferencesChanged, .configImported] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.finish()
            }
        }
        for name in [NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancel()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancel()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.cancelIfTargetDiffers(from: app?.processIdentifier)
        }
    }

    private let lookupWindow: WindowLookup

    init(queue: DispatchQueue = DispatchQueue(label: "Rectangle.WindowAnimation", qos: .userInteractive),
         lookupWindow: @escaping WindowLookup = { pid, id, launch, preferred, isCurrent in
        WindowAccessibilityLookup.resolveResult(pid: pid, id: id, launch: launch, preferred: preferred, isCurrent: isCurrent)
    }) {
        self.queue = queue
        self.lookupWindow = lookupWindow
    }

    // Accessed exclusively by queue.
    private var workerTime: TimeInterval = 0
    private var workerWindow: WindowAnimationWorkerElement?
    private var workerScreens: [CGRect] = []
    private var workerNativeResize = false
    private var workerOffset = CGPoint.zero
    private lazy var core = DirectWindowAnimator(enabled: { true }, clock: { [weak self] in self?.workerTime ?? ProcessInfo.processInfo.systemUptime }, automaticallyAdvances: false, smoothResize: true,
        environmentIsSafe: { !WindowAnimationInterruptionPolicy.missionControlActive },
        crossesDisplays: { [weak self] a, b in
            let screens = self?.workerScreens ?? []
            return WindowDisplayTransition.display(containing: a, displays: screens)
                != WindowDisplayTransition.display(containing: b, displays: screens)
        }, minimumHint: { ($0 as? WindowAnimationWorkerElement)?.hint },
        isNativeResizeApp: { [weak self] _ in self?.workerNativeResize == true })


    func logicalFrame(for element: AccessibilityElement) -> CGRect? { destination(for: element) }

    func destination(for element: AccessibilityElement) -> CGRect? {
        if let active, active.element == element { return active.destination }
        return retiring.last(where: { $0.0 == element })?.1
    }
    func afterPendingWrites(cancellation: (() -> Void)? = nil, _ body: @escaping () -> Void) {
        if active == nil && retiring.isEmpty && !tickPending { body(); return }
        let expected = generation
        queue.async { [self] in
            DispatchQueue.main.async { [self] in
                guard generation == expected else { cancellation?(); return }
                body()
            }
        }
    }

    func cancel(for element: AccessibilityElement) {
        guard active?.element == element else { return }
        cancel()
    }
    func cancel() {
        generation &+= 1
        guard let previous = active else { return }
        retiring.append((previous.element, previous.destination, previous.request))
        active = nil
        stopDisplay()
        previous.request.cancel()
        let drained = retiring.map { $0.2 }
        queue.async { [self] in
            core.cancel(); workerWindow = nil
            DispatchQueue.main.async { [self] in retiring.removeAll { entry in drained.contains { $0 === entry.2 } } }
        }
    }
    func cancelIfTargetDiffers(from pid: pid_t?) {
        if let pid, let active, active.pid != pid { cancel() }
    }
    func finish() {
        guard let current = active else { return }
        stopDisplay()
        queue.async { [self] in
            guard current.request.isCurrent else { return }
            core.finish()
            DispatchQueue.main.async { [self] in clear(current.request, cancelled: true) }
        }
    }
    func mouseDown() { cancel() }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration, resizeOnly: Bool = false, releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement? = nil, profile: WindowAnimationProfile = .standard,
                 offset: @escaping () -> CGPoint = { .zero }, curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
                 cancellation: (() -> Void)? = nil, completion: @escaping (CGRect) -> Void) {
        guard WindowAnimator.enabled, let pid = element.pid, let id = element.windowId,
              let launch = WindowProcessIdentity.launchTime(for: pid) else { completion(.null); return }
        observeLifecycle()
        generation &+= 1
        let sameWindow = active?.element == element
        if let previous = active {
            previous.request.cancel()
            retiring.append((previous.element, previous.destination, previous.request))
        }
        let drained = retiring.map { $0.2 }
        let request = WindowAnimationRequest(cancellation: cancellation)
        let key = WindowAnimationResponseKey(pid: pid, window: id, launch: launch)
        let response = responses.entry(for: key, at: ProcessInfo.processInfo.systemUptime)
        active = Active(element: element, destination: destination, request: request, offset: offset, pid: pid)
        let screens = NSScreen.screens.map { $0.frame.screenFlipped }
        let bundle = element.bundleIdentifier
        let native = bundle.map { Defaults.directAnimationNativeResizeApps.typedValue?.contains($0) == true } ?? false
        let enhanced = Defaults.enhancedUI.value
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        let initialOffset = offset()
        let preferredWindow = element.axElement
        startDisplay(destination: destination, initialPacing: response?.pacing)
        let displayInterval = 1 / Double(pacing.maximumRate)
        queue.async { [self] in
            guard request.isCurrent else { return }
            workerScreens = screens; workerNativeResize = native; workerOffset = initialOffset
            if !sameWindow || workerWindow?.windowId != id || workerWindow?.process != pid || workerWindow?.launch != launch {
                core.cancel(); workerWindow = nil
                var raw: AXUIElement?

                if raw == nil {
                    switch lookupWindow(pid, id, launch, preferredWindow, { request.isCurrent }) {
                    case .found(let element): raw = element
                    case .unavailable: break
                    case .timedOut, .cancelled:
                        // Do not send a stalled or obsolete target back to a
                        // synchronous placement fallback on the main thread.
                        DispatchQueue.main.async { [self] in
                            retiring.removeAll { entry in drained.contains { $0 === entry.2 } }
                            clear(request, cancelled: true)
                        }
                        return
                    }
                }
                if let raw {
                    workerWindow = WindowAnimationWorkerElement(raw, pid: pid, id: id, launch: launch,
                        bundle: bundle, enhancedUI: enhanced, assistiveTechnology: assistive, request: request)
                    workerWindow?.resizeCost = response?.resizeCost ?? 0
                }
            }
            guard request.isCurrent else { return }
            DispatchQueue.main.async { [self] in
                retiring.removeAll { entry in drained.contains { $0 === entry.2 } }
            }
            guard let window = workerWindow else {
                DispatchQueue.main.async { [self] in
                    guard active?.request === request else { return }
                    clear(request); completion(.null)
                }
                return
            }
            window.request = request
            window.hint = window.readMinimumSizeHint()
            guard request.isCurrent else { return }
            let watch = WindowAnimationObservation(pid: pid, element: window.axElement, request: request)
            DispatchQueue.main.async { [self] in
                if active?.request === request { observation = watch }
            }
            workerTime = ProcessInfo.processInfo.systemUptime
            window.frameBudget = WindowAnimationFrameBudget()
            window.resizeCadence = WindowAnimationResizeCadence(frameInterval: displayInterval, cost: window.resizeCost)
            window.animationSizeInterval = window.resizeCadence.interval
            core.animate(window, from: startingFrame, to: destination, duration: duration,
                resizeOnly: resizeOnly, releasedSnap: releasedSnap, placement: placement, profile: profile,
                offset: { [weak self] in self?.workerOffset ?? .zero }, curve: curve) { [weak self] frame in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.active?.request === request, request.isCurrent else { return }
                        self.clear(request); completion(frame)
                    }
                }
        }
    }
    private func clear(_ request: WindowAnimationRequest, cancelled: Bool = false) {
        retiring.removeAll { $0.2 === request }
        guard active?.request === request else { return }
        active = nil; stopDisplay()
        if cancelled { request.cancel() }
        else { request.complete() }
    }
    private func tick(targetTimestamp: TimeInterval? = nil) {
        guard let current = active else { return }
        if !WindowAnimator.enabled { finish(); return }
        let now = ProcessInfo.processInfo.systemUptime
        guard !tickPending, now >= nextTick else { return }
        tickPending = true
        let offset = current.offset()
        let rate = pacing.rate
        let interval = pacing.interval
        let displayInterval = 1 / Double(pacing.maximumRate)
        let deadline = targetTimestamp.map { now + ($0 - CACurrentMediaTime()) }
        queue.async { [self] in
            let start = ProcessInfo.processInfo.systemUptime
            if current.request.isCurrent {
                workerOffset = offset
                workerWindow?.animationYieldRequested = false
                workerWindow?.resizeWork = 0
                let reads = workerWindow?.readCount ?? 0, writes = workerWindow?.writeCount ?? 0
                if current.request.consumeGeometryChange() { workerWindow?.animationPolicy?.geometryChanged = true }
                if current.request.consumeResizeChange() {
                    workerWindow?.animationResizeNotified = true
                    WindowAnimationDiagnostics.event("animation-resize-notification", fields: ["windowID": workerWindow?.windowId ?? 0])
                }
                workerTime = start
                workerWindow?.animationVerificationTime = start
                workerWindow?.animationResizeResponse.frameInterval = interval
                workerWindow?.frameBudget.deadline = deadline.map { min($0, start + displayInterval) } ?? (start + displayInterval)
                // Only motion samples look ahead; feedback and timeout checks use real time.
                let sampleTime = WindowAnimationPacing.sampleTime(now: start, deadline: deadline, displayInterval: displayInterval)
                core.advance(at: workerTime, presentationTime: sampleTime)
                WindowAnimationDiagnostics.event("animation-executor-tick", fields: [
                    "windowID": workerWindow?.windowId ?? 0, "rate": rate,
                    "queueMilliseconds": (start - now) * 1000,
                    "sizeFrameCount": workerWindow?.resizeCadence.frames ?? 1,
                    "milliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000,
                    "reads": (workerWindow?.readCount ?? 0) - reads,
                    "writes": (workerWindow?.writeCount ?? 0) - writes])
            }
            let end = ProcessInfo.processInfo.systemUptime
            let finished = workerWindow.map { core.destination(for: $0) == nil } ?? true
            let sizeCost = workerWindow?.resizeCost ?? 0
            let movementCost = max(0, end - start - (workerWindow?.resizeWork ?? 0))
            let key = workerWindow.map { WindowAnimationResponseKey(pid: $0.process, window: $0.windowId ?? 0, launch: $0.launch) }
            DispatchQueue.main.async { [self] in
                tickPending = false
                guard active?.request === current.request else { return }
                pacing.observe(cost: movementCost); nextTick = now + pacing.interval * 0.9
                if let key { responses.record(key, pacing: pacing, resizeCost: sizeCost, at: end) }
                // Normal completion was queued by the core before this block.
                // A still-active request whose core stopped was cancelled instead.
                if finished { clear(current.request, cancelled: true) }
            }
        }
    }
    private func stopDisplay() {
        observation = nil
        displayCleanup?(); displayCleanup = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }; mouseMonitor = nil
    }
    private func startDisplay(destination: CGRect, initialPacing: WindowAnimationPacing?) {
        stopDisplay()
        nextTick = 0
        let screen = NSScreen.screens.max {
            let a = $0.frame.screenFlipped.intersection(destination), b = $1.frame.screenFlipped.intersection(destination)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        let maximumRate = screen?.maximumFramesPerSecond ?? 60
        if let initialPacing, initialPacing.maximumRate == maximumRate { pacing = initialPacing }
        else { pacing = WindowAnimationPacing(maximumRate: maximumRate, initialRate: initialPacing?.rate) }
        if let screen {
            let target = WindowAnimationDisplayLinkTarget { [weak self] in self?.tick(targetTimestamp: $0) }
            let link = screen.displayLink(target: target, selector: #selector(WindowAnimationDisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(pacing.maximumRate),
                maximum: Float(pacing.maximumRate), preferred: Float(pacing.maximumRate))
            link.add(to: .main, forMode: .common)
            displayCleanup = { link.invalidate(); _ = target }
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common); displayCleanup = { timer.invalidate() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.cancel() }
    }
}
