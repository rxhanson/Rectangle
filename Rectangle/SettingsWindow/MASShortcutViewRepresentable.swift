/// MASShortcutViewRepresentable.swift

import SwiftUI
import MASShortcut

struct MASShortcutViewRepresentable: NSViewRepresentable {
    let defaultsKey: String
    let validator: MASShortcutValidator?
    /// Suspends the bound shortcuts while this view records, so a shortcut
    /// already in use can be recorded instead of triggering its action.
    let recordingObserver: ShortcutRecordingObserver
    /// Lets a window action's recorder take a mouse button as well as a key.
    var recordsMouseButtons = false

    func makeNSView(context: Context) -> MASShortcutView {
        let view = recordsMouseButtons ? WindowActionShortcutView() : MASShortcutView()
        view.setAssociatedUserDefaultsKey(defaultsKey, withTransformerName: MASDictionaryTransformerName)
        if let validator = validator {
            view.shortcutValidator = validator
        }
        recordingObserver.observe([view])
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(recordingObserver: recordingObserver)
    }

    /// The observer keeps its views alive, so a view SwiftUI removes - when
    /// its section collapses, say - has to be let go of here, and stopped
    /// first if it was recording, or it would go on recording unseen with
    /// every other shortcut suspended.
    static func dismantleNSView(_ nsView: MASShortcutView, coordinator: Coordinator) {
        nsView.isRecording = false
        coordinator.recordingObserver.unobserve(nsView)
    }

    final class Coordinator {
        let recordingObserver: ShortcutRecordingObserver

        init(recordingObserver: ShortcutRecordingObserver) {
            self.recordingObserver = recordingObserver
        }
    }

    func updateNSView(_ nsView: MASShortcutView, context: Context) {
        if let validator = validator {
            nsView.shortcutValidator = validator
        }
    }
}
