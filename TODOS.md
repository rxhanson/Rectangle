## ~~Phase 1: Ninths, Twelfths, Sixteenths grid positions~~ — DONE
Added 3×3 (9), 3×4 (12), and 4×4 (16) grid layouts with cycling mode,
default keyboard shortcuts for twelfths, and full URL scheme support.

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

## Phase 3: Persistent window pinning
**What:** Pin specific windows to specific grid positions so they always return to their
assigned spot after being moved, minimized, or when the app relaunches.
**Why:** When running 12+ AI coding agents, each in its own terminal, you want agent #3
to always be in position 3. If a window gets moved or the app restarts, it should
snap back to its pinned position automatically.
**Design:** A "pin to position" action (menu item or shortcut) that associates a window
fingerprint with a grid position. Pinned windows resist displacement — if another
window is moved into a pinned slot, the pinned window reclaims it.
**Persistence:** Stored alongside display layout memory (Phase 2) so pins survive
restarts and display changes.

## Phase 4: Batch tiling via URL scheme
**What:** A single URL command to tile N windows into an M-position grid layout.
**Why:** Enables scripting workflows like "open 12 terminals and tile them into twelfths"
from a shell script or automation tool. Critical for Conductor/Claude Code/Codex
workflows where you spin up many agents and need them arranged instantly.
**Design:** New URL scheme action like:
`rectangle://execute-action?name=tile-grid&grid=twelfths&app=com.mitchellh.ghostty`
Tiles all windows of the specified app into the grid, or all windows if no app specified.

## Phase 5: Snap area support for dense grids
**What:** Drag-to-snap zones for twelfths and sixteenths, similar to existing snap areas
for halves, thirds, and eighths.
**Why:** Mouse-based workflows benefit from visual snap targets, especially on large
displays where keyboard shortcuts for 16 positions are hard to memorize.
**Design:** Subdivide existing edge/corner snap zones. Show grid footprint overlay
when dragging near edges. Configurable grid density in preferences.
