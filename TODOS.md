
## Phase 1.5: Prefs UI visibility for individual twelfths shortcuts
**What:** Add storyboard rows + IBOutlets for the 11 twelfths shortcuts that are
functional but invisible in the preferences shortcuts tab.
**Why:** After Phase 1 adds default shortcuts, 11/12 twelfths positions will work
but have no editable row in the Prefs > Shortcuts pane. Only `topLeftTwelfth` shows
(as the cycling entrypoint). This asymmetric state is confusing.
**Current state:** `PrefsViewController.swift` uses hardcoded IBOutlets. Adding 11
rows requires storyboard edits + new IBOutlets. Low complexity, moderate tedium.
**Start here:** `Rectangle/PrefsWindow/PrefsViewController.swift` and `Base.lproj/Main.storyboard`
**Depends on:** Phase 1 (PR with default shortcuts) merged first.

## Phase 2: Per-display layout memory
**What:** Windows automatically remember and restore their positions per display UUID.
Switching from a 49" ultrawide to a 14" MacBook restores windows to their saved
positions on each display, or gracefully adapts to smaller screen density.
**Why:** AI-native workflows with 12+ terminal windows require stable spatial organization
across display configurations. Without this, users must reorganize windows every time
they switch displays.
**Design:** `DisplayLayoutManager` watching display change notifications, window
fingerprinting via `bundleID + AXWindow index` (stable) or `bundleID + lastKnownFrame`
(fallback). UserDefaults JSON keyed by `CGDisplayCreateUUIDFromDisplayID`.
**Codex recommended data model:**
  - `DisplayLayoutProfile { displayUUID, gridType, pages: [LayoutPage] }`
  - `WindowFingerprint { bundleID, windowTitleHash, lastKnownFrame }`
**Skip:** named workspaces, cross-app generalization on day 1, background daemon,
fancy UI editor. Start with Ghostty-first, generalize after.
**Depends on:** Phase 1 merged.
