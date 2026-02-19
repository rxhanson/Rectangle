# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rectangle is a macOS window management app written in Swift (based on Spectacle). It uses the macOS Accessibility API to move and resize windows via keyboard shortcuts and drag-to-snap. Requires macOS 10.15+.

- Bundle ID: `com.knollsoft.Rectangle`
- Launcher bundle ID: `com.knollsoft.RectangleLauncher`

## Build & Test

```bash
# Build (unsigned, for local development)
xcodebuild -scheme Rectangle CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Run tests
xcodebuild test -scheme Rectangle

# Build archive (as CI does)
xcodebuild archive -scheme Rectangle -archivePath Rectangle.xcarchive
```

The project uses Xcode with SPM dependencies: a forked MASShortcut (keyboard shortcut recording) and Sparkle (auto-update).

## Architecture

### Core Data Flow

```
User Action → ShortcutManager
           → WindowManager.execute(ExecutionParameters)
           → WindowCalculationFactory (selects calculation by WindowAction)
           → WindowCalculation.calculate() → CGRect
           → WindowMover chain → AccessibilityElement.setFrame()
```

### Key Files

- **`WindowAction.swift`**: Enum of 85+ window actions. Each action maps to a calculation and has a URL name (e.g. `left-half`, `maximize`).
- **`WindowManager.swift`**: Orchestrates window operations. Calls the factory, invokes movers, records history.
- **`WindowCalculationFactory.swift`**: Static registry mapping each `WindowAction` to its `WindowCalculation` subclass.
- **`AccessibilityElement.swift`**: Wrapper around macOS Accessibility API for getting/setting window frames.
- **`Defaults.swift`**: Central registry for 80+ `UserDefaults` preferences (gaps, margins, behavior flags, etc.).
- **`AppDelegate.swift`**: App lifecycle, initialization, menu bar setup, URL scheme handling.
- **`ShortcutManager.swift`**: Registers/unregisters keyboard shortcuts via MASShortcut.
- **`ScreenDetection.swift`**: Determines which display a window is on.

### Window Calculations (`WindowCalculation/`)

78 files, each implementing one positioning strategy as a subclass of `WindowCalculation`. Examples: `LeftHalfCalculation`, `MaximizeCalculation`, `NextDisplayCalculation`. To add a new window action:
1. Add a case to `WindowAction.swift` (with display name, URL name, optional default shortcut)
2. Create a `WindowCalculation` subclass
3. Register it in `WindowCalculationFactory`

### Window Movers (`WindowMover/`)

Chain of responsibility—`StandardWindowMover` is tried first, then `BestEffortWindowMover` as fallback. `CenteringFixedSizedWindowMover` handles fixed-size windows. `QuantizedWindowMover` snaps to pixel boundaries.

### Snap-to-Edge (`Snapping/`)

`SnappingManager` monitors global mouse events to detect window dragging toward screen edges. `FootprintWindow` renders the preview overlay. `SnapAreaModel` defines the hot zones; compound snap areas in `CompoundSnapArea/` handle multi-step drag interactions (e.g., drag to bottom-center after bottom-third).

### Preferences (`PrefsWindow/`)

`SettingsViewController.swift` (~38 KB) is the main preferences UI. `Config.swift` handles JSON import/export of settings. Preferences are stored in `~/Library/Preferences/com.knollsoft.Rectangle.plist`.

## URL Scheme

`rectangle://execute-action?name=[action-name]` — triggers any window action by its URL name. Also supports `rectangle://execute-task?name=ignore-app[&app-bundle-id=...]`.

## Hidden Preferences

Many advanced settings are set via `defaults write com.knollsoft.Rectangle ...`. See `TerminalCommands.md` for the full list. These map to keys in `Defaults.swift`.

## Notable Conventions

- **No async/await**: The codebase predates Swift 5.5 patterns; synchronous Accessibility API calls throughout.
- **Singletons**: `AppDelegate.instance`, `RectangleStatusItem.instance`.
- **Failure signal**: `NSSound.beep()` is used when a window action cannot be applied.
- **Multi-display**: Actions like "Next Display" cycle through `NSScreen.screens`; screen orientation affects which third is "first."
- **Stage Manager**: `StageUtil.swift` handles detection and special-casing for macOS Stage Manager.
- **Desktop widgets**: Excluded from tile-all and cascade-all operations (see `WindowUtil.swift`).
