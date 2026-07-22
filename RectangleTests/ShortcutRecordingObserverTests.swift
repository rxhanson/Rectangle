/// ShortcutRecordingObserverTests.swift

import MASShortcut
import XCTest
@testable import Rectangle

class ShortcutRecordingObserverTests: XCTestCase {

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
}
