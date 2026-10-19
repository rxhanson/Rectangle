import Cocoa

/// Optional window tools communicate through these small integration points;
/// neither module imports or initializes the other.
enum WindowFeatureInteraction {
    static var helperIsPresenting: () -> Bool = { false }
    static var cancelHelper: () -> Void = {}
    static var recordPlacement: (AccessibilityElement, CGWindowID?, CGRect, NSScreen, Bool) -> Void = { _, _, _, _, _ in }
}
