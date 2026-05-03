# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Rectangle is a macOS Xcode project (Swift 5, deployment target 10.15+). Dependencies are managed via Swift Package Manager (MASShortcut, Sparkle).

```bash
# Build from command line (ad-hoc signing)
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle archive CODE_SIGN_IDENTITY="-" -archivePath build/Rectangle.xcarchive

# Run tests
xcodebuild test -project Rectangle.xcodeproj -scheme Rectangle

# Open in Xcode (preferred for debug builds)
open Rectangle.xcodeproj
```

CI runs on GitHub Actions (`macos-26` runner) and builds on every push/PR. There is no linter or formatter configured.

### Accessibility Permission

Rectangle requires Accessibility permission (System Settings > Privacy > Accessibility). Debug builds get a fresh bundle ID, so macOS won't remember the grant. **You must reset TCC before each debug relaunch:**

```bash
tccutil reset Accessibility com.knollsoft.Rectangle
```

Then re-grant when prompted. Without this, the app launches but cannot move or resize windows.

## Architecture

Rectangle is a Spectacle-derived macOS window manager. The core loop is:

**User input** (keyboard shortcut / drag-to-snap / URL scheme / menu click) -> **WindowAction** -> **WindowCalculation** -> **WindowMover** -> **Accessibility API**

### Key types and their roles

- **`WindowAction`** (`WindowAction.swift`) - Int-backed enum defining every possible window action (120+ cases: `leftHalf`, `topLeftSixth`, `bottomCenterRightTwelfth`, etc.). Each case has a `name` string, a `category` (for menu grouping), and default keyboard shortcuts. The `active` static array controls menu ordering. New grid positions require adding an enum case here (with a stable raw value), plus entries in `name`, `category`, `defaultShortcut`, `isMoveToEdgeAction`, `firstInGroup`, and `WindowAction.active`.

- **`WindowCalculation`** (`WindowCalculation/WindowCalculation.swift`) - Base class implementing the `Calculation` protocol. The central method is `calculateRect(_ params: RectCalculationParameters) -> RectResult`. Each grid position gets its own `WindowCalculation` subclass (e.g., `TopLeftSixthCalculation`). Subclasses typically override only `calculateRect` to compute the window frame from `visibleFrameOfScreen`.

- **`WindowCalculationFactory`** (`WindowCalculation/WindowCalculation.swift`) - Static map from `WindowAction` to `WindowCalculation` instance (`calculationsByAction`). Every new calculation must be registered here.

- **`WindowManager`** (`WindowManager.swift`) - Orchestrates execution. Detects screens, gets the frontmost window via Accessibility APIs, looks up the calculation, applies gaps, and delegates to the `WindowMover` chain. Tracks action history per window ID for repeated-execution cycling.

- **`WindowMover`** protocol (`WindowMover/WindowMover.swift`) - Chain of responsibility: `StandardWindowMover` tries first, then `BestEffortWindowMover` handles windows that don't cooperate. `CenteringFixedSizedWindowMover` handles fixed-size windows.

- **`ShortcutManager`** (`ShortcutManager.swift`) - Binds keyboard shortcuts to actions using MASShortcut. Posts `NSNotification` when triggered.

- **`SnappingManager`** (`Snapping/SnappingManager.swift`) - Handles drag-to-snap: monitors mouse events, determines snap areas at screen edges/corners, shows the "footprint" preview window.

- **`Defaults`** (`Defaults.swift`) - All user preferences as typed static properties. Preferences are stored in `UserDefaults` and configurable via Terminal commands (`defaults write com.knollsoft.Rectangle ...`). See `TerminalCommands.md` for the full list.

### The Calculation pattern

Grid-position calculations follow a consistent pattern:

1. Subclass `WindowCalculation`
2. Conform to `OrientationAware` (landscape vs portrait screen handling)
3. Override `landscapeRect` and `portraitRect` to compute the grid cell as a fraction of `visibleFrameOfScreen`
4. Apply gaps via `GapCalculation.applyGaps()` with appropriate `sharedEdges`

Example for a twelfth: divide width by 4, height by 3, offset by column/row, declare shared edges where the cell borders other cells (not screen edges).

### Position cycling

When a user repeats the same action (e.g., pressing left-half multiple times), behavior is controlled by `SubsequentExecutionMode`:
- **resize** (default): cycles through sizes (1/2 -> 2/3 -> 1/3) via `RepeatedExecutionsCalculation`
- **acrossMonitor**: moves window to the next display
- **resizeAndCycleQuadrants**: for corner actions, cycles through grid positions

Grid divisions (8ths, 9ths, 12ths, 16ths) use `*Repeated` protocols (`EighthsRepeated`, `NinthsRepeated`, `TwelfthsRepeated`, `SixteenthsRepeated`) that define cycling order - left and right directional cycling through all positions in that grid tier.

### Screen detection

`ScreenDetection` handles multi-monitor setups. It orders screens by position, finds which screen contains the frontmost window, and provides adjacent screen references for cross-display actions.

### Menu system

The status bar menu is built dynamically in `AppDelegate.addWindowActionMenuItems()`. Actions are grouped by `WindowActionCategory`. The "Show additional sizes" preference toggles visibility of 8ths/9ths/12ths/16ths via submenus.

### Gap system

`GapCalculation.applyGaps()` applies configurable gaps between windows. The `sharedEdges` parameter (an `Edge` OptionSet) reduces gaps at edges where two windows meet, so adjacent windows have consistent spacing rather than double gaps.

### URL scheme

Rectangle supports `rectangle://execute-action?name=[action-name]` for external automation. Action names use kebab-case (e.g., `top-left-sixth`).

## Adding a new window action

The full checklist for adding a new grid position:

1. Add enum case to `WindowAction` with a unique stable `Int` raw value
2. Add to `WindowAction.name` switch
3. Add to `WindowAction.category` switch
4. Add to `WindowAction.active` array (order determines menu position)
5. Create `*Calculation.swift` in `WindowCalculation/`, conforming to `OrientationAware`
6. Add static instance to `WindowCalculationFactory`
7. Add mapping in `WindowCalculationFactory.calculationsByAction`
8. If the action participates in position cycling, add to the relevant `*Repeated` protocol extension
9. Add default shortcut in `WindowAction.defaultShortcut` if desired
10. Add localization key in `Base.lproj/Main.strings`

## Project structure

- `Rectangle/` - Main app target
- `RectangleLauncher/` - Helper app for launch-at-login (LSUIElement)
- `RectangleTests/` - XCTest target (minimal - mostly placeholder tests)
- `build/` - Xcode build artifacts and SPM checkouts
- `TerminalCommands.md` - Documentation for hidden `defaults write` preferences

## Coding conventions

- Match the existing style. The project does not use SwiftLint or any formatter.
- Window action enum raw values must be stable integers (serialized to UserDefaults).
- Calculation classes are one-per-file, named `{Position}Calculation.swift`.
- Localization strings use `NSLocalizedString` with `tableName: "Main"`.
- The codebase uses `CGRect` in "screen-flipped" coordinates (origin at top-left, y increases downward) - the macOS Accessibility API convention, not the AppKit convention. The `.screenFlipped` extension handles conversion.
