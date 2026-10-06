import Cocoa

/// Query each active desktop once, including its minimized windows. Ordinary
/// onscreen candidates do not depend on these optional WindowServer symbols.
/// This scope is deliberately read-only: the helper never moves a window to a Space.
enum LayoutHelperDesktopScope {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias Windows = @convention(c) (UInt32, Int32, CFArray, UInt32,
        UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)

    private static func lookup<T>(_ names: [String], as type: T.Type) -> T? {
        guard let library else { return nil }
        for name in names {
            if let address = dlsym(library, name) { return unsafeBitCast(address, to: type) }
        }
        return nil
    }

    static func read(displays: [String: CGDirectDisplayID], separateSpaces: Bool) -> [CGWindowID: Set<CGDirectDisplayID>] {
        guard let connection = lookup(["SLSMainConnectionID", "CGSMainConnectionID"], as: Connection.self),
              let displayList = lookup(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: Displays.self),
              let windows = lookup(["SLSCopyWindowsWithOptionsAndTags", "CGSCopyWindowsWithOptionsAndTags"], as: Windows.self),
              let rows = displayList(connection())?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        let desktops = activeDesktops(rows, displays: displays, separateSpaces: separateSpaces)
        var result: [CGWindowID: Set<CGDirectDisplayID>] = [:]
        for (space, screens) in desktops {
            var requiredTags: UInt64 = 0, excludedTags: UInt64 = 0
            // 0x7 includes minimized windows; scope remains the selected desktop.
            guard let list = windows(connection(), 0, [NSNumber(value: space)] as CFArray,
                                     0x7, &requiredTags, &excludedTags)?.takeRetainedValue() as? [NSNumber] else { continue }
            for number in list where number.uint32Value != 0 {
                result[number.uint32Value, default: []].formUnion(screens)
            }
        }
        return result
    }

    static func activeDesktops(_ rows: [[String: Any]], displays: [String: CGDirectDisplayID],
                               separateSpaces: Bool) -> [UInt64: Set<CGDirectDisplayID>] {
        var result: [UInt64: Set<CGDirectDisplayID>] = [:]
        for row in rows {
            guard let current = row["Current Space"] as? [String: Any],
                  let number = current["id64"] as? NSNumber, number.uint64Value > 0,
                  (current["type"] as? NSNumber)?.intValue == 0,
                  let name = row["Display Identifier"] as? String else { continue }
            let screens: Set<CGDirectDisplayID>
            if !separateSpaces || name == "Main" { screens = Set(displays.values) }
            else if let display = displays[name] { screens = [display] }
            else { continue }
            result[number.uint64Value, default: []].formUnion(screens)
        }
        return result
    }
}
