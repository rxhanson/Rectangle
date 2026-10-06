import Cocoa
import ScreenCaptureKit

final class LayoutHelperCaptureQueue<Key: Hashable, Value> {
    var load: (Key) async -> Value?
    var completed: (Key, Value) -> Void = { _, _ in }
    var failed: (Key) -> Void = { _ in }
    private var waiting: [Key] = []
    private var running = Set<Key>()
    private var runningGeneration: [Key: Int] = [:]
    private var generation = 0
    private var tasks: [Key: Task<Void, Never>] = [:]
    private(set) var activeCount = 0
    init(load: @escaping (Key) async -> Value?) { self.load = load }

    func replace(with keys: [Key]) {
        var seen = Set<Key>()
        // Scrolling changes priority even when the candidate set stays the same.
        waiting = keys.filter { runningGeneration[$0] != generation && seen.insert($0).inserted }
        pump()
    }
    func stop(discardResults: Bool = false) {
        waiting.removeAll()
        generation += 1
        for task in tasks.values { task.cancel() }
    }
    private func pump() {
        while activeCount < 2, let index = waiting.firstIndex(where: { !running.contains($0) }) {
            let key = waiting.remove(at: index)
            running.insert(key); activeCount += 1
            let epoch = generation
            runningGeneration[key] = epoch
            tasks[key] = Task { @MainActor [weak self] in
                guard let self else { return }
                let value = Task.isCancelled ? nil : await self.load(key)
                self.tasks[key] = nil
                self.running.remove(key); self.runningGeneration[key] = nil; self.activeCount -= 1
                if !Task.isCancelled, self.generation == epoch {
                    if let value { self.completed(key, value) } else { self.failed(key) }
                }
                self.pump()
            }
        }
    }
}
