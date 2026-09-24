/// ShortcutRecordingObserver.swift

import Cocoa
import MASShortcut

class ShortcutRecordingObserver: NSObject {

    private static var recordingObservationContext = 0
    private var observedViews = [ObjectIdentifier: MASShortcutView]()
    private var recordingViews = Set<ObjectIdentifier>()

    func observe(_ views: [MASShortcutView]) {
        for view in views {
            let viewId = ObjectIdentifier(view)
            guard observedViews[viewId] == nil else { continue }

            observedViews[viewId] = view
            view.addObserver(self,
                             forKeyPath: "recording",
                             options: [.new],
                             context: &Self.recordingObservationContext)
        }
    }

    deinit {
        for view in observedViews.values {
            view.removeObserver(self,
                                forKeyPath: "recording",
                                context: &Self.recordingObservationContext)
        }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard context == &Self.recordingObservationContext,
              keyPath == "recording",
              let view = object as? MASShortcutView
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        let newValue = change?[.newKey]
        let isRecording = (newValue as? Bool) ?? (newValue as? NSNumber)?.boolValue ?? false
        recordingChanged(for: view, isRecording: isRecording)
    }

    func recordingChanged(for view: MASShortcutView, isRecording: Bool) {
        let wasRecording = !recordingViews.isEmpty
        let viewId = ObjectIdentifier(view)
        if isRecording {
            recordingViews.insert(viewId)
        } else {
            recordingViews.remove(viewId)
        }

        let isRecordingAnyView = !recordingViews.isEmpty
        guard wasRecording != isRecordingAnyView else { return }
        Notification.Name.shortcutRecording.post(object: isRecordingAnyView)
    }

}
