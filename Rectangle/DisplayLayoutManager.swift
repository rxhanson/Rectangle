//
//  DisplayLayoutManager.swift
//  Rectangle
//
//  Created by Rectangle contributors.
//

import Cocoa

class DisplayLayoutManager {
    static var shared: DisplayLayoutManager?

    private var currentDisplayConfig: String
    private var screenChangeDebounceWork: DispatchWorkItem?
    private let screenDetection = ScreenDetection()

    init() {
        currentDisplayConfig = NSScreen.displayConfigurationKey

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: nil) { [weak self] _ in
                self?.handleScreenChange()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: nil) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.enforcePinsForApp(bundleID: bundleID)
                }
        }
    }

    // MARK: - Phase 2: Display Layout Memory

    func recordWindowPosition(windowId: CGWindowID, windowElement: AccessibilityElement, action: WindowAction, rect: CGRect) {
        guard let pid = windowElement.pid,
              let fingerprint = WindowFingerprint.from(windowElement: windowElement, pid: pid),
              let screen = screenDetection.detectScreens(using: windowElement)?.currentScreen,
              let displayUUID = screen.displayUUID else { return }

        let saved = SavedWindowPosition(
            fingerprint: fingerprint,
            rect: CodableRect(rect),
            actionRawValue: action.rawValue,
            displayUUID: displayUUID
        )

        var layouts = Defaults.displayLayouts.typedValue ?? [:]
        var positions = layouts[currentDisplayConfig] ?? []
        positions.removeAll { $0.fingerprint == fingerprint && $0.displayUUID == displayUUID }
        positions.append(saved)
        layouts[currentDisplayConfig] = positions
        Defaults.displayLayouts.typedValue = layouts
    }

    private func handleScreenChange() {
        screenChangeDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performDisplayChange()
        }
        screenChangeDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func performDisplayChange() {
        let newConfig = NSScreen.displayConfigurationKey
        guard newConfig != currentDisplayConfig else { return }

        saveAllCurrentPositions(forConfig: currentDisplayConfig)
        currentDisplayConfig = newConfig
        restorePositions(forConfig: newConfig)
        enforcePins()
    }

    private func saveAllCurrentPositions(forConfig config: String) {
        let allWindows = AccessibilityElement.getAllWindowElements()
        var positions = [SavedWindowPosition]()

        for window in allWindows {
            guard window.isWindow == true,
                  window.isMinimized != true,
                  let pid = window.pid,
                  let fingerprint = WindowFingerprint.from(windowElement: window, pid: pid),
                  let screen = screenDetection.detectScreens(using: window)?.currentScreen,
                  let displayUUID = screen.displayUUID else { continue }

            let lastAction = window.getWindowId().flatMap { AppDelegate.windowHistory.lastRectangleActions[$0] }

            positions.append(SavedWindowPosition(
                fingerprint: fingerprint,
                rect: CodableRect(window.frame),
                actionRawValue: lastAction?.action.rawValue,
                displayUUID: displayUUID
            ))
        }

        var layouts = Defaults.displayLayouts.typedValue ?? [:]
        layouts[config] = positions
        Defaults.displayLayouts.typedValue = layouts
    }

    private func restorePositions(forConfig config: String) {
        guard let positions = Defaults.displayLayouts.typedValue?[config], !positions.isEmpty else { return }

        let allWindows = AccessibilityElement.getAllWindowElements().filter { $0.isWindow == true && $0.isMinimized != true }
        var matched = Set<Int>()

        for saved in positions {
            if let (index, window) = bestMatch(fingerprint: saved.fingerprint, among: allWindows, excluding: matched) {
                matched.insert(index)
                window.setFrame(saved.rect.cgRect)
            }
        }
    }

    private func bestMatch(fingerprint: WindowFingerprint, among windows: [AccessibilityElement], excluding: Set<Int>) -> (Int, AccessibilityElement)? {
        // First pass: match by bundleID + title hash
        for (index, window) in windows.enumerated() {
            guard !excluding.contains(index),
                  let pid = window.pid,
                  let candidate = WindowFingerprint.from(windowElement: window, pid: pid),
                  candidate.bundleID == fingerprint.bundleID else { continue }

            if let savedHash = fingerprint.windowTitleHash,
               let candidateHash = candidate.windowTitleHash,
               savedHash == candidateHash {
                return (index, window)
            }
        }

        // Second pass: match by bundleID + window index
        for (index, window) in windows.enumerated() {
            guard !excluding.contains(index),
                  let pid = window.pid,
                  let candidate = WindowFingerprint.from(windowElement: window, pid: pid),
                  candidate.bundleID == fingerprint.bundleID,
                  candidate.windowIndex == fingerprint.windowIndex else { continue }
            return (index, window)
        }

        return nil
    }

    // MARK: - Phase 3: Window Pinning

    func pinCurrentPosition(windowElement: AccessibilityElement, windowId: CGWindowID) {
        guard let lastAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
              let pid = windowElement.pid,
              let fingerprint = WindowFingerprint.from(windowElement: windowElement, pid: pid) else {
            NSSound.beep()
            return
        }

        let screen = screenDetection.detectScreens(using: windowElement)?.currentScreen
        let pinned = PinnedPosition(
            actionRawValue: lastAction.action.rawValue,
            displayUUID: screen?.displayUUID
        )

        var pins = Defaults.pinnedWindows.typedValue ?? [:]
        let key = fingerprintKey(fingerprint)
        pins[key] = pinned
        Defaults.pinnedWindows.typedValue = pins
    }

    func unpinWindow(windowElement: AccessibilityElement) {
        guard let pid = windowElement.pid,
              let fingerprint = WindowFingerprint.from(windowElement: windowElement, pid: pid) else { return }

        var pins = Defaults.pinnedWindows.typedValue ?? [:]
        pins.removeValue(forKey: fingerprintKey(fingerprint))
        Defaults.pinnedWindows.typedValue = pins
    }

    func isWindowPinned(windowElement: AccessibilityElement) -> Bool {
        guard let pid = windowElement.pid,
              let fingerprint = WindowFingerprint.from(windowElement: windowElement, pid: pid) else { return false }
        return Defaults.pinnedWindows.typedValue?[fingerprintKey(fingerprint)] != nil
    }

    func enforcePins() {
        guard let pins = Defaults.pinnedWindows.typedValue, !pins.isEmpty else { return }

        let allWindows = AccessibilityElement.getAllWindowElements().filter { $0.isWindow == true && $0.isMinimized != true }

        for (key, pinned) in pins {
            guard let fingerprint = decodeFingerprint(key),
                  let action = WindowAction(rawValue: pinned.actionRawValue) else { continue }

            let targetScreen: NSScreen?
            if let uuid = pinned.displayUUID {
                targetScreen = NSScreen.screens.first { $0.displayUUID == uuid }
            } else {
                targetScreen = NSScreen.screens.first
            }

            guard let screen = targetScreen else { continue }

            if let (_, matched) = bestMatch(fingerprint: fingerprint, among: allWindows, excluding: []) {
                action.postSnap(windowElement: matched, windowId: matched.getWindowId(), screen: screen)
            }
        }
    }

    func enforcePinsForApp(bundleID: String) {
        guard let pins = Defaults.pinnedWindows.typedValue, !pins.isEmpty else { return }

        let relevantPins = pins.filter { key, _ in
            guard let fp = decodeFingerprint(key) else { return false }
            return fp.bundleID == bundleID
        }
        guard !relevantPins.isEmpty else { return }

        let allWindows = AccessibilityElement.getAllWindowElements().filter { $0.isWindow == true && $0.isMinimized != true }

        for (key, pinned) in relevantPins {
            guard let fingerprint = decodeFingerprint(key),
                  let action = WindowAction(rawValue: pinned.actionRawValue) else { continue }

            let targetScreen: NSScreen?
            if let uuid = pinned.displayUUID {
                targetScreen = NSScreen.screens.first { $0.displayUUID == uuid }
            } else {
                targetScreen = NSScreen.screens.first
            }

            guard let screen = targetScreen else { continue }

            if let (_, matched) = bestMatch(fingerprint: fingerprint, among: allWindows, excluding: []) {
                action.postSnap(windowElement: matched, windowId: matched.getWindowId(), screen: screen)
            }
        }
    }

    // MARK: - Helpers

    private func fingerprintKey(_ fp: WindowFingerprint) -> String {
        let data = try? JSONEncoder().encode(fp)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\(fp.bundleID):\(fp.windowIndex)"
    }

    private func decodeFingerprint(_ key: String) -> WindowFingerprint? {
        guard let data = key.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WindowFingerprint.self, from: data)
    }
}
