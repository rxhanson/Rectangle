# Plan for Converting SettingsViewController to SwiftUI

This document outlines the steps and structure for migrating the current `SettingsViewController` (AppKit) to a modern SwiftUI implementation.

## Goals
- Replace all checkboxes with SwiftUI `Toggle` components.
- Group settings into logical `Section` elements instead of using horizontal separators.
- Maintain existing functionality by binding directly to the underlying `Defaults` model via a ViewModel.
- Implement responsive layouts that follow macOS design guidelines.

## Proposed Data Model: `SettingsViewModel`
A new `@ObservableObject` or `@Observable` class will act as the mediator between SwiftUI and the current `Defaults` system. It will include:
- `@Published` properties for all setting values (e.g., `launchOnLogin`, `gapSize`).
- Bindings that update `Defaults` whenever a value is changed by the user.
- Logic migrated from `@IBAction` methods to handle side effects (e.g., refreshing visibility, posting notifications).

## UI Structure (SwiftUI Form)

### 1. General Section
- **Launch on login**: `Toggle`
- **Subsequent execution mode**: `Picker`
- **Allow any shortcut**: `Toggle`
- **Check for updates automatically**: `Toggle`

### 2. Gap Section
- **Gap size**: `Slider` with a label indicating current value in pixels.
- **Skip gap top edge**: `Toggle` (visible only when gap size > 0).

### 3. Window & Display Section
- **Move cursor across displays**: `Toggle`
- **Use cursor screen detection**: `Toggle` (visible only if enabled by system/defaults).
- **Double click title bar**: `Picker` or `Menu` for different window actions.
- **Treat multiple displays as one**: `Toggle` with description text underneath.
- **Green stoplight button maximizes instead of Full Screen**: `Toggle` with description text underneath.
- **Preserve maximize state when moving across displays**: `Toggle`.

### 4. Stage Section (Conditional)
*Only visible if `StageUtil.stageCapable` is true.*
- **Stage size**: `Slider` with a label indicating current value in pixels.

### 5. Cycle Sizes Section
- **Cycle sizes selection**: A horizontal collection of `Toggles` for each available `CycleSize`.
- **Cyclic corner shortcuts expand**: `Picker` (Segmented style) for Horizontal/Vertical axes.
- **Resize adjacent windows when cycling side or corner shortcuts**: `Toggle`.

### 6. Todo Section
*Visible only if "Todo mode" is enabled.*
- **Todo Mode Toggle**: Master toggle for the section.
- **Sidebar width**: `TextField` + `Picker` for units (px, etc.).
- **Sidebar side**: `Picker` for position (left/right).
- *Note: MASShortcut views will require `NSViewRepresentable` to integrate with SwiftUI.*

## Implementation Steps
1. [ ] Create `SettingsViewModel.swift`.
2. [ ] Implement `@Published` properties and bindings in the ViewModel.
3. [ ] Create `SettingsView.swift` using a `Form` layout.
4. [ ] Migrate all `@IBAction` logic from `SettingsViewController` into the ViewModel or via SwiftUI actions.
5. [ ] Implement `NSViewRepresentable` for complex components like `MASShortcutView` if needed.
6. [ ] Verify that all settings correctly update `Defaults` and trigger necessary notifications/side effects.
7. [ ] Run linting and type checking to ensure correctness.
