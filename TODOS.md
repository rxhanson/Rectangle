
## ~~Phase 1.5: Prefs UI visibility for individual twelfths shortcuts~~ — DONE
Added 11 individual shortcut rows to Settings → Extra (Grid Positions section) in
`SettingsViewController.swift`. Popover now scrollable via NSScrollView.

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
