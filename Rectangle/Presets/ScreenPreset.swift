import Foundation
import CoreGraphics
import AppKit

struct InstalledApp {
    let url: URL
    let bundleId: String
    let name: String
    let icon: NSImage
    let isRunning: Bool
}

struct CodableCGRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

struct AppWindowState: Codable, Identifiable {
    var id: String
    let bundleId: String
    let appName: String
    let screenIndex: Int
    let frame: CodableCGRect
    let relativeFrame: CodableCGRect?
    let windowIndex: Int       // 0-based order in the app's window list at capture time
    let windowTitle: String?   // title at capture time, used for best-effort restore matching

    init(id: String = UUID().uuidString,
         bundleId: String, appName: String, screenIndex: Int,
         frame: CodableCGRect, relativeFrame: CodableCGRect?,
         windowIndex: Int = 0, windowTitle: String? = nil) {
        self.id = id
        self.bundleId = bundleId
        self.appName = appName
        self.screenIndex = screenIndex
        self.frame = frame
        self.relativeFrame = relativeFrame
        self.windowIndex = windowIndex
        self.windowTitle = windowTitle
    }
}

struct ScreenPreset: Codable, Identifiable {
    var id: String
    var name: String
    let screenCount: Int
    var windowStates: [AppWindowState]
    var shortcutDefaultsKey: String?
    var createdAt: Date

    init(name: String, screenCount: Int, windowStates: [AppWindowState]) {
        self.id = UUID().uuidString
        self.name = name
        self.screenCount = screenCount
        self.windowStates = windowStates
        self.shortcutDefaultsKey = nil
        self.createdAt = Date()
    }
}
