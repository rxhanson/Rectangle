/// ShortcutRecordingObserverTests.swift

import MASShortcut
import XCTest
@testable import Rectangle

class ShortcutRecordingObserverTests: XCTestCase {

    private func withRegisteredTodoShortcuts(
        _ assertions: (MASShortcutMonitor, MASShortcut, MASShortcut) throws -> Void
    ) throws {
        let userDefaults = UserDefaults.standard
        let previousToggleShortcut = userDefaults.object(forKey: TodoManager.toggleDefaultsKey)
        let previousReflowShortcut = userDefaults.object(forKey: TodoManager.reflowDefaultsKey)
        let previousTodoEnabled = Defaults.todo.enabled
        let previousTodoModeEnabled = Defaults.todoMode.enabled
        let binder = try XCTUnwrap(MASShortcutBinder.shared())
        let previousBindingOptions = binder.bindingOptions
        binder.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]

        TodoManager.setShortcutBindingsSuspended(true)
        defer {
            TodoManager.setShortcutBindingsSuspended(true)

            if let previousToggleShortcut {
                userDefaults.set(previousToggleShortcut, forKey: TodoManager.toggleDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: TodoManager.toggleDefaultsKey)
            }
            if let previousReflowShortcut {
                userDefaults.set(previousReflowShortcut, forKey: TodoManager.reflowDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: TodoManager.reflowDefaultsKey)
            }

            Defaults.todo.enabled = previousTodoEnabled
            Defaults.todoMode.enabled = previousTodoModeEnabled
            TodoManager.setShortcutBindingsSuspended(false)
            binder.bindingOptions = previousBindingOptions
        }

        let monitor = try XCTUnwrap(binder.shortcutMonitor)
        let shortcuts = try availableTodoShortcuts(monitor: monitor)
        let transformer = try XCTUnwrap(
            ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))
        )

        userDefaults.set(
            transformer.reverseTransformedValue(shortcuts.toggle),
            forKey: TodoManager.toggleDefaultsKey
        )
        userDefaults.set(
            transformer.reverseTransformedValue(shortcuts.reflow),
            forKey: TodoManager.reflowDefaultsKey
        )
        Defaults.todo.enabled = true
        Defaults.todoMode.enabled = true
        TodoManager.setShortcutBindingsSuspended(false)

        XCTAssertTrue(monitor.isShortcutRegistered(shortcuts.toggle))
        XCTAssertTrue(monitor.isShortcutRegistered(shortcuts.reflow))

        try assertions(monitor, shortcuts.toggle, shortcuts.reflow)
    }

    private func availableTodoShortcuts(
        monitor: MASShortcutMonitor
    ) throws -> (toggle: MASShortcut, reflow: MASShortcut) {
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let keyCodes = [
            kVK_ANSI_U,
            kVK_ANSI_I,
            kVK_ANSI_O,
            kVK_ANSI_P,
            kVK_ANSI_J,
            kVK_ANSI_K,
            kVK_ANSI_L,
            kVK_ANSI_M
        ]
        let windowShortcutIdentities = Set(
            ShortcutCycle.shortcutsByAction().values.map { ShortcutCycle.ShortcutIdentity($0) }
        )
        let availableShortcuts = keyCodes
            .map { MASShortcut(keyCode: $0, modifierFlags: modifiers) }
            .filter {
                !windowShortcutIdentities.contains(ShortcutCycle.ShortcutIdentity($0))
                    && !monitor.isShortcutRegistered($0)
            }

        let toggle = try XCTUnwrap(availableShortcuts.first)
        let reflow = try XCTUnwrap(availableShortcuts.dropFirst().first)
        return (toggle, reflow)
    }

    func testPostsRecordingChangesForObservedShortcutViews() {
        let observer = ShortcutRecordingObserver()
        let firstShortcutView = MASShortcutView()
        let secondShortcutView = MASShortcutView()
        var recordingChanges = [Bool]()
        let notificationObserver = NotificationCenter.default.addObserver(
            forName: .shortcutRecording,
            object: nil,
            queue: nil
        ) { notification in
            recordingChanges.append(notification.object as! Bool)
        }
        defer {
            NotificationCenter.default.removeObserver(notificationObserver)
            firstShortcutView.setValue(false, forKey: "recording")
            secondShortcutView.setValue(false, forKey: "recording")
        }

        observer.observe([firstShortcutView, secondShortcutView])

        firstShortcutView.setValue(true, forKey: "recording")
        firstShortcutView.setValue(false, forKey: "recording")
        secondShortcutView.setValue(true, forKey: "recording")
        secondShortcutView.setValue(false, forKey: "recording")

        XCTAssertEqual(recordingChanges, [true, false, true, false])
    }

    func testObservingSameShortcutViewTwiceDoesNotDuplicateNotifications() {
        let observer = ShortcutRecordingObserver()
        let shortcutView = MASShortcutView()
        var recordingChanges = [Bool]()
        let notificationObserver = NotificationCenter.default.addObserver(
            forName: .shortcutRecording,
            object: nil,
            queue: nil
        ) { notification in
            recordingChanges.append(notification.object as! Bool)
        }
        defer {
            NotificationCenter.default.removeObserver(notificationObserver)
            shortcutView.setValue(false, forKey: "recording")
        }

        observer.observe([shortcutView])
        observer.observe([shortcutView])

        shortcutView.setValue(true, forKey: "recording")
        shortcutView.setValue(false, forKey: "recording")

        XCTAssertEqual(recordingChanges, [true, false])
    }

    func testOverlappingShortcutRecordingsStayActiveUntilAllViewsStopRecording() {
        let observer = ShortcutRecordingObserver()
        let firstShortcutView = MASShortcutView()
        let secondShortcutView = MASShortcutView()
        var recordingChanges = [Bool]()
        let notificationObserver = NotificationCenter.default.addObserver(
            forName: .shortcutRecording,
            object: nil,
            queue: nil
        ) { notification in
            recordingChanges.append(notification.object as! Bool)
        }
        defer {
            NotificationCenter.default.removeObserver(notificationObserver)
        }

        observer.recordingChanged(for: firstShortcutView, isRecording: true)
        XCTAssertEqual(recordingChanges, [true])

        observer.recordingChanged(for: secondShortcutView, isRecording: true)
        XCTAssertEqual(recordingChanges, [true])

        observer.recordingChanged(for: firstShortcutView, isRecording: false)
        XCTAssertEqual(recordingChanges, [true])

        observer.recordingChanged(for: secondShortcutView, isRecording: false)
        XCTAssertEqual(recordingChanges, [true, false])
    }

    func testTodoShortcutBindingsAreSuspendedAndRestored() throws {
        try withRegisteredTodoShortcuts { monitor, toggleShortcut, reflowShortcut in
            TodoManager.setShortcutBindingsSuspended(true)

            XCTAssertFalse(monitor.isShortcutRegistered(toggleShortcut))
            XCTAssertFalse(monitor.isShortcutRegistered(reflowShortcut))

            TodoManager.setShortcutBindingsSuspended(false)

            XCTAssertTrue(monitor.isShortcutRegistered(toggleShortcut))
            XCTAssertTrue(monitor.isShortcutRegistered(reflowShortcut))
        }
    }

    func testTodoShortcutBindingsCannotRebindWhileSuspended() throws {
        try withRegisteredTodoShortcuts { monitor, toggleShortcut, reflowShortcut in
            TodoManager.setShortcutBindingsSuspended(true)

            TodoManager.registerUnregisterToggleShortcut()
            TodoManager.registerUnregisterReflowShortcut()

            XCTAssertFalse(monitor.isShortcutRegistered(toggleShortcut))
            XCTAssertFalse(monitor.isShortcutRegistered(reflowShortcut))
        }
    }

    func testResumingTodoShortcutBindingsHonorsTodoState() throws {
        try withRegisteredTodoShortcuts { monitor, toggleShortcut, reflowShortcut in
            TodoManager.setShortcutBindingsSuspended(true)
            Defaults.todoMode.enabled = false
            TodoManager.setShortcutBindingsSuspended(false)

            XCTAssertTrue(monitor.isShortcutRegistered(toggleShortcut))
            XCTAssertFalse(monitor.isShortcutRegistered(reflowShortcut))

            TodoManager.setShortcutBindingsSuspended(true)
            Defaults.todo.enabled = false
            TodoManager.setShortcutBindingsSuspended(false)

            XCTAssertFalse(monitor.isShortcutRegistered(toggleShortcut))
            XCTAssertFalse(monitor.isShortcutRegistered(reflowShortcut))
        }
    }
}
