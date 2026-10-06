import Cocoa
import ScreenCaptureKit

/// App groups and their internal order remain stable during one assist sequence.
struct LayoutHelperWindowOrder {
    private var groups: [String] = []
    private var windows: [String: [CGWindowID]] = [:]
    mutating func ordered(_ candidates: [(CGWindowID, String)]) -> [CGWindowID] {
        let live = Dictionary(uniqueKeysWithValues: candidates)
        for group in groups { windows[group]?.removeAll { live[$0] != group } }
        for (id, group) in candidates {
            if !groups.contains(group) { groups.append(group) }
            if windows[group]?.contains(id) != true { windows[group, default: []].append(id) }
        }
        return groups.flatMap { windows[$0] ?? [] }
    }
}
