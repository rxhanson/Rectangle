# Rectangle Terminal Commands for Hidden Preferences

The preferences window is purposefully slim, but there's a lot that can be modified via Terminal. After executing a terminal command, restart the app as these values are loaded on application startup. For Rectangle Pro, please replace `com.knollsoft.Rectangle` with `com.knollsoft.Hookshot` for the following commands.

## Contents

- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Adjust Behavior on Repeated Commands](#adjust-behavior-on-repeated-commands)
- [Cycle thirds on repeated Center Half commands](#cycle-thirds-on-repeated-center-half-commands)
- [Resize on Directional Move](#resize-on-directional-move)
- [Enable Todo Mode](#enable-todo-mode)
- [Only allow drag-to-snap when modifier keys are pressed](#only-allow-drag-to-snap-when-modifier-keys-are-pressed)
- [Almost Maximize](#almost-maximize)
- [Add an extra centering command with custom size](#add-an-extra-centering-command-with-custom-size)
- [Add extra "ninths" sizing commands](#add-extra-ninths-sizing-commands)
- [Add extra "eighths" sizing commands](#add-extra-eighths-sizing-commands)
- [Add additional "thirds" sizing commands](#add-additional-thirds-sizing-commands)
- [Modify the "footprint" displayed for drag to snap area](#modify-the-footprint-displayed-for-drag-to-snap-area)
- [Move Up/Down/Left/Right: Don't center on edge](#move-updownleftright-dont-center-on-edge)
- [Make Smaller limits](#make-smaller-limits)
- [Make Smaller/Make Larger size increments](#make-smallermake-larger-size-increments)
- [Make Smaller/Make Larger "curtain resize" with gaps](#make-smallermake-larger-curtain-resize-with-gaps)
- [Disabling window restore when moving windows](#disabling-window-restore-when-moving-windows)
- [Changing the margin for the snap areas](#changing-the-margin-for-the-snap-areas)
- [Setting gaps at the screen edges](#setting-gaps-at-the-screen-edges)
- [Ignore specific drag to snap areas](#ignore-specific-drag-to-snap-areas)
- [Disabling gaps when maximizing](#disabling-gaps-when-maximizing)
- [Enabling snap areas for sixths](#enabling-snap-areas-for-sixths)
- [Move cursor with window](#move-cursor-with-window)
- [Prevent a window that is quickly dragged above the menu bar from going into Mission Control](#prevent-a-window-that-is-quickly-dragged-above-the-menu-bar-from-going-into-mission-control)

## Keyboard Shortcuts

If you wish to change the default shortcuts after first launch click "Restore Default Shortcuts" in the settings tab of the preferences window. Alternatively you can set it with the following terminal command followed by app restart. True is for the recommended shortcuts, false is for Spectacle's.

```bash
defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
```

## Adjust Behavior on Repeated Commands

This is now in the preferences window, but there's an option in the preferences for "Move to adjacent display on repeated left or right commands".
If this setting is not checked, then each time you execute a half or quarter action, the width of the window will cycle through the following sizes: 1/2 -> 2/3 -> 1/3.

The cycling behavior can be disabled entirely with:

```bash
defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 2
```

`subsequentExecutionMode` accepts the following values:
0: halves to thirds Spectacle behavior (box unchecked)
1: cycle displays (box checked) for left/right actions
2: disabled
3: cycle displays for left/right actions, halves to thirds for the rest (old Rectangle behavior)
4: repeat same action on next display

## Cycle thirds on repeated Center Half commands

Set Center Half to cycle thirds sizes: 1/2 -> 2/3 -> 1/3 with:

```bash
defaults write com.knollsoft.Rectangle centerHalfCycles -int 1
```

## Resize on Directional Move

By default, the commands to move to certain edges will not resize the window.
If `resizeOnDirectionalMove` is enabled, the _halves to thirds_ mode is instead used.
This means that when moving to the left/right, the width will be changed, and when moving to the top/bottom, the height will be changed.
This size will cycle between 1/2 -> 2/3 -> 1/3 of the screen’s width/height.

Note that if subsequent execution mode is set to cycle displays when this is enabled, Move Left and Move Right will always resize to 1/2, and pressing it again will move to the next display.

```bash
defaults write com.knollsoft.Rectangle resizeOnDirectionalMove -bool true
```

## Adjust macOS Ventura Stage Manager size

By default, the Stage Manager area will be set to 190, if enabled.

```bash
defaults write com.knollsoft.Rectangle stageSize -float <VALUE>
```

To set it to a proportion of your screen's width, set it to a value between 0 and 1.

```bash
defaults write com.knollsoft.Rectangle stageSize -float <VALUE_BETWEEN_0_AND_1>
```

## Enable Todo Mode

See the [wiki](https://github.com/rxhanson/Rectangle/wiki/Todo-Mode) for more info.

```bash
defaults write com.knollsoft.Rectangle todo -int 1
```

## Only allow drag-to-snap when modifier keys are pressed

Modifier key values can be ORed together.

| Modifier Key | Integer Value |
|--------------|---------------|
| cmd          | 1048576       |
| option       | 524288        |
| ctrl         | 262144        |
| shift        | 131072        |
| fn           | 8388608       |

This command would be for restricting snap to the cmd key:

```bash
defaults write com.knollsoft.Rectangle snapModifiers -int 1048576
```

## Almost Maximize

By default, "Almost Maximize" will resize the window to 90% of the screen (width & height).

```bash
defaults write com.knollsoft.Rectangle almostMaximizeHeight -float <VALUE_BETWEEN_0_&_1>
```

```bash
defaults write com.knollsoft.Rectangle almostMaximizeWidth -float <VALUE_BETWEEN_0_&_1>
```

## Add an extra centering command with custom size

This extra command is not available in the UI. You'll need to know which keycode and modifier flags you want (try the free key codes app: <https://apps.apple.com/us/app/key-codes/id414568915>)

```bash
defaults write com.knollsoft.Rectangle specified -dict-add keyCode -float 8 modifierFlags -float 1966080
```

```bash
defaults write com.knollsoft.Rectangle specifiedHeight -float 1050
defaults write com.knollsoft.Rectangle specifiedWidth -float 1680
```

## Add extra "ninths" sizing commands

Commands for resizing to screen ninths are not available in the UI.  Similar to extra centering you will need to know which keycode and modifier flags you want.

The key codes are:

* topLeftNinth
* topCenterNinth
* topRightNinth
* middleLeftNinth
* middleCenterNinth
* middleRightNinth
* bottomLeftNinth
* bottomCenterNinth
* bottomRightNinth

For example, the command for setting the top left ninth shortcut to `ctrl opt shift 1` would be:

```bash
defaults write com.knollsoft.Rectangle topLeftNinth -dict-add keyCode -float 18 modifierFlags -float 917504
```

## Add extra "eighths" sizing commands

Commands for resizing to screen eighths are not available in the UI. This divides the screen up into a 4x2 grid.

The key codes are:

* topLeftEighth
* topCenterLeftEighth
* topCenterRightEighth
* topRightEighth
* bottomLeftEighth
* bottomCenterLeftEighth
* bottomCenterRightEighth
* bottomRightEighth

For example, the command for setting the top left eighth shortcut to `ctrl opt shift 1` would be:

```bash
defaults write com.knollsoft.Rectangle topLeftEighth -dict-add keyCode -float 18 modifierFlags -float 917504
```

## Add additional "thirds" sizing commands 

These commands for resizing to corner two-thirds are not available in the UI but can be configured via CLI.

The key codes are:

* topLeftThird
* topRightThird
* bottomLeftThird
* bottomRightThird

(these correspond to two-thirds, and when repeated will cycle through each of the calculations)

For example, the command for setting the top left two-thirds shortcut to `ctrl opt shift 1` would be:

```bash
defaults write com.knollsoft.Rectangle topLeftThird -dict-add keyCode -float 18 modifierFlags -float 917504
```

## Modify the "footprint" displayed for drag to snap area

Adjust the alpha (transparency). Default is 0.3.

```bash
defaults write com.knollsoft.Rectangle footprintAlpha -float <VALUE_BETWEEN_0_&_1>
```

Change the border width. Default is 2 (used to be 1).

```bash
defaults write com.knollsoft.Rectangle footprintBorderWidth -float <NUM_PIXELS>
```

Disable the fade.

```bash
defaults write com.knollsoft.Rectangle footprintFade -int 2
```

Change the color.

```bash
defaults write com.knollsoft.Rectangle footprintColor -string "{\"red\":0,\"blue\":0.5,\"green\":0.5}"
```

Change the animation duration. The value is a multiplier. Default is 0 (no animation).

```bash
defaults write com.knollsoft.Rectangle footprintAnimationDurationMultiplier -float <MULTIPLIER>
```

## Move Up/Down/Left/Right: Don't center on edge

By default, the directional move will center the window along the edge that the window is being moved to.

```bash
defaults write com.knollsoft.Rectangle centeredDirectionalMove -int 2
```

## Make Smaller limits

By default, "Make Smaller" will decrease the window until it reaches 25% of the screen (width & height).

```bash
defaults write com.knollsoft.Rectangle minimumWindowWidth -float <VALUE_BETWEEN_0_&_1>
```

```bash
defaults write com.knollsoft.Rectangle minimumWindowHeight -float <VALUE_BETWEEN_0_&_1>
```

## Make Smaller/Make Larger size increments

By default, "Make Smaller" and "Make Larger" change the window height/width by 30 pixels.

```bash
defaults write com.knollsoft.Rectangle sizeOffset -float <NUM_PIXELS>
```

## Make Smaller/Make Larger "curtain resize" with gaps

By default, windows touching the edge of the screen will keep those shared edges the same while only resizing the non-shared edge. With window gaps, this is a little ambiguous since the edges don't actually touch the screen, so you can disable it for traditional, floating resizing:

```bash
defaults write com.knollsoft.Rectangle curtainChangeSize -int 2
```

## Disabling window restore when moving windows

```bash
defaults write com.knollsoft.Rectangle unsnapRestore -int 2
```

## Changing the margin for the snap areas

Each margin is configured separately, and has a default value of 5

```bash
defaults write com.knollsoft.Rectangle snapEdgeMarginTop -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginBottom -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginLeft -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginRight -int 10
```

## Setting gaps at the screen edges

You can specify gaps at the edges of your screen that will be left uncovered by window resizing operations. This is useful if, for example, you use a dock replacement that should not have windows overlapping it.

```bash
defaults write com.knollsoft.Rectangle screenEdgeGapTop -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapBottom -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapLeft -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapRight -int 10
```

If you want these gaps to be applied on your main screen only you can set screenEdgeGapsOnMainScreenOnly. Useful for multi display setups where only one screen has some dock replacement.

```bash
defaults write com.knollsoft.Rectangle screenEdgeGapsOnMainScreenOnly -bool true
```

## Ignore specific drag to snap areas

Each drag to snap area on the edge of a screen can be ignored with a single Terminal command, but it's a bit field setting so you'll have to determine the bit field for which ones you want to disable.

| Bit | Snap Area                 | Window Action       |
|-----|---------------------------|---------------------|
| 0   | Top                       | Maximize            |
| 1   | Bottom                    | Thirds              |
| 2   | Left                      | Left Half           |
| 3   | Right                     | Right Half          |
| 4   | Top Left                  | Top Left Corner     |
| 5   | Top Right                 | Top Right Corner    |
| 6   | Bottom Left               | Bottom Left Corner  |
| 7   | Bottom Right              | Bottom Right Corner |
| 8   | Top Left Below Corner     | Top Half            |
| 9   | Top Right Below Corner    | Top Half            |
| 10  | Bottom Left Above Corner  | Bottom Half         |
| 11  | Bottom Right Above Corner | Bottom Half         |

To disable the top (maximize) snap area, execute:

```bash
defaults write com.knollsoft.Rectangle ignoredSnapAreas -int 1
```

To disable the Top Half and Bottom Half snap areas, the bit field would be 1111 0000 0000, or 3840

```bash
defaults write com.knollsoft.Rectangle ignoredSnapAreas -int 3840
```

## Disabling gaps when maximizing

By default, the "Gaps between windows" setting applies to "Maximize" and "Maximize Height".

To disable the gaps for "Maximize", execute:

```bash
defaults write com.knollsoft.Rectangle applyGapsToMaximize -int 2
```

To disable the gaps for "Maximize Height", execute:

```bash
defaults write com.knollsoft.Rectangle applyGapsToMaximizeHeight -int 2
```

## Enabling snap areas for sixths

To enable snap areas for sixths corners, execute: 

```bash
defaults write com.knollsoft.Rectangle sixthsSnapArea -bool true
```

Once enabled, you can drag a window to the corner, then move it along the edge towards the thirds area to snap to a sixth.

## Move cursor with window

There's an option in the UI for moving the cursor with the window when going across displays, but here's an option for moving it with any shortcut:

```bash
defaults write com.knollsoft.Rectangle moveCursor -int 1
```

## Prevent a window that is quickly dragged above the menu bar from going into Mission Control

Important: This can cause issues with dragging and dropping in certain apps like Adobe Illustrator, and can affect text selection in a select few apps as well. 

Windows that are slowly moved above the menu bar will still go into Mission Control.

Once this is enabled, the checkbox for it is visible in the Snap Areas tab of the Preferences window.

```bash
defaults write com.knollsoft.Rectangle missionControlDragging -int 2
```

Change the allowed off-screen distance. The value is in pixels and is tied to the speed. Default is 25.

```bash
defaults write com.knollsoft.Rectangle missionControlDraggingAllowedOffscreenDistance -float <DISTANCE>
```

Change the disallowed duration. The value is in milliseconds. Default is 250.

```bash
defaults write com.knollsoft.Rectangle missionControlDraggingDisallowedDuration -int <DURATION>
```
