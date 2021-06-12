# Rectangle

![](https://github.com/rxhanson/Rectangle/workflows/Build/badge.svg)

Rectangle is a window management app based on Spectacle, written in Swift.

![image](https://user-images.githubusercontent.com/13651296/101402672-57ab5300-38d4-11eb-9e8c-6a3147d26711.png)

## System Requirements
Rectangle supports macOS v10.11+.

## Installation
You can download the latest dmg from https://rectangleapp.com or the [Releases page](https://github.com/rxhanson/Rectangle/releases).

Or install with brew cask:

```bash
brew install --cask rectangle
```
## How to use it
The keyboard shortcuts are self explanatory, but the snap areas can use some explanation if you've never used them on Windows or other window management apps.

Drag a window to the edge of the screen. When the mouse cursor reaches the edge of the screen, you'll see a footprint that Rectangle will attempt to resize and move the window to when the click is released.

| Snap Area                                              | Resulting Action                       |
|--------------------------------------------------------|----------------------------------------|
| Left or right edge                                     | Left or right half                     |
| Top                                                    | Maximize                               |
| Corners                                                | Quarter in respective corner           |
| Left or right edge, just above or below a corner       | Top or bottom half                     |
| Bottom left, center, or right third                    | Respective third                       |
| Bottom left or right third, then drag to bottom center | First or last two thirds, respectively |

### Ignore an app

   1. Focus the app that you want to ignore (make a window from that app frontmost).
   2. Open the Rectangle menu and select "Ignore app"

## Differences with Spectacle
* Rectangle uses [MASShortcut](https://github.com/shpakovski/MASShortcut) for keyboard shortcut recording. Spectacle used its own shortcut recorder.
* Rectangle has additional window actions: move windows to each edge without resizing, maximize only the height of a window, almost maximizing a window. 
* Next/prev screen thirds is replaced with explicitly first third, first two thirds, center third, last two thirds, and last third. Screen orientation is taken into account, as in first third will be left third on landscape and top third on portrait.
  * You can however emulate Spectacle's third cycling using first and last third actions. So, if you repeatedly execute first third, it will cycle through thirds (first, center, last) and vice-versa with the last third.
* There's an option to have windows traverse across displays on subsequent left or right executions.
* Windows will snap when dragged to edges/corners of the screen. This can be disabled.

## Terminal commands
The preferences window is purposefully slim, but there's a lot that can be modified via Terminal. After executing a terminal command, restart the app as these values are loaded on application startup.

### Keyboard Shortcuts
If you wish to change the default shortcuts after first launch click "Restore Default Shortcuts" in the settings tab of the preferences window. Alternatively you can set it with the following terminal command followed by app restart. True is for the recommended shortcuts, false is for Spectacle's.

```bash
defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
```

### Adjust Behavior on Repeated Commands
There's an option in the preferences for `Move to adjacent display on repeated left or right commands`.
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

### Cycle thirds on repeated Center Half commands
Set Center Half to cycle thirds sizes: 1/2 -> 2/3 -> 1/3 with:

```bash
defaults write com.knollsoft.Rectangle centerHalfCycles -int 1
```

### Resize on Directional Move
By default, the commands to move to certain edges will not resize the window.
If `resizeOnDirectionalMove` is enabled, the _halves to thirds_ mode is instead used.
This means that when moving to the left/right, the width will be changed, and when moving to the top/bottom, the height will be changed.
This size will cycle between 1/2 -> 2/3 -> 1/3 of the screen’s width/height.

Note that if subsequent execution mode is set to cycle displays when this is enabled, Move Left and Move Right will always resize to 1/2, and pressing it again will move to the next display.

```bash
defaults write com.knollsoft.Rectangle resizeOnDirectionalMove -bool true
```

### Enable Todo Mode
See the [wiki](https://github.com/rxhanson/Rectangle/wiki/Todo-Mode) for more info.

```bash
defaults write com.knollsoft.Rectangle todo -int 1
```


### Only allow drag-to-snap when modifier keys are pressed

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


### Almost Maximize
By default, "Almost Maximize" will resize the window to 90% of the screen (width & height).

```bash
defaults write com.knollsoft.Rectangle almostMaximizeHeight -float <VALUE_BETWEEN_0_&_1>
```

```bash
defaults write com.knollsoft.Rectangle almostMaximizeWidth -float <VALUE_BETWEEN_0_&_1>
```

### Add an extra centering command with custom size
This extra command is not available in the UI. You'll need to know which keycode and modifier flags you want (try the free key codes app: https://apps.apple.com/us/app/key-codes/id414568915)

```bash
defaults write com.knollsoft.Rectangle specified -dict-add keyCode -float 8 modifierFlags -float 1966080
```

```bash
defaults write com.knollsoft.Rectangle specifiedHeight -float 1050
defaults write com.knollsoft.Rectangle specifiedWidth -float 1680
```

### Modify the "footprint" displayed for drag to snap area

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

### Move Up/Down/Left/Right: Don't center on edge

By default, the directional move will center the window along the edge that the window is being moved to. 

```bash
defaults write com.knollsoft.Rectangle centeredDirectionalMove -int 2
```
### Make Smaller limits

By default, "Make Smaller" will decrease the window until it reaches 25% of the screen (width & height).

```bash
defaults write com.knollsoft.Rectangle minimumWindowWidth -float <VALUE_BETWEEN_0_&_1>
```

```bash
defaults write com.knollsoft.Rectangle minimumWindowHeight -float <VALUE_BETWEEN_0_&_1>
```

### Make Smaller/Make Larger size increments

By default, "Make Smaller" and "Make Larger" change the window height/width by 30 pixels.

```bash
defaults write com.knollsoft.Rectangle sizeOffset -float <NUM_PIXELS>
```

### Make Smaller/Make Larger "curtain resize" with gaps

By default, windows touching the edge of the screen will keep those shared edges the same while only resizing the non-shared edge. With window gaps, this is a little ambiguous since the edges don't actually touch the screen, so you can disable it for traditional, floating resizing:

```bash
defaults write com.knollsoft.Rectangle curtainChangeSize -int 2
```

### Disabling window restore when moving windows

```bash
defaults write com.knollsoft.Rectangle unsnapRestore -int 2
```

### Changing the margin for the snap areas

Each margin is configured separately, and has a default value of 5

```bash
defaults write com.knollsoft.Rectangle snapEdgeMarginTop -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginBottom -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginLeft -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginRight -int 10
```

### Setting gaps at the screen edges

You can specify gaps at the edges of your screen that will be left uncovered by window resizing operations. This is useful if, for example, you use a dock replacement that should not have windows overlapping it.

```bash
defaults write com.knollsoft.Rectangle screenEdgeGapTop -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapBottom -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapLeft -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapRight -int 10
```

### Ignore specific drag to snap areas

Each drag to snap area on the edge of a screen can be ignored with a single Terminal command, but it's a bit field setting so you'll have to determine the bit field for which ones you want to disable.


| Bit | Snap Area                 | Window Action       |
|-----|---------------------------|---------------------|
| 1   | Top                       | Maximize            |
| 2   | Bottom                    | Thirds              |
| 3   | Left                      | Left Half           |
| 4   | Right                     | Right Half          |
| 5   | Top Left                  | Top Left Corner     |
| 6   | Top Right                 | Top Right Corner    |
| 7   | Bottom Left               | Bottom Left Corner  |
| 8   | Bottom Right              | Bottom Right Corner |
| 9   | Top Left Below Corner     | Top Half            |
| 10  | Top Right Below Corner    | Top Half            |
| 11  | Bottom Left Above Corner  | Bottom Half         |
| 12  | Bottom Right Above Corner | Bottom Half         |

To disable the top (maximize) snap area, execute:
```bash
defaults write com.knollsoft.Rectangle ignoredSnapAreas -int 1
```

To disable the Top Half and Bottom Half snap areas, the bit field would be 1111 0000 0000, or 3840
```bash
defaults write com.knollsoft.Rectangle ignoredSnapAreas -int 3840
```

## Common Known Issues

### Rectangle doesn't have the ability to move to other desktops/spaces.

Apple never released a public API for Spaces, so any direct interaction with Spaces uses private APIs that are actually a bit shaky. Using the private API adds enough complexity to the app to where I feel it's better off without it. If Apple decides to release a public API for it, I'll add it in.

### Window resizing is off slightly for iTerm2

By default iTerm2 will only resize in increments of character widths. There might be a setting inside iTerm2 to disable this, but you can change it with the following command.

```bash
defaults write com.googlecode.iterm2 DisableWindowSizeSnap -integer 1
```

### Rectangle appears to cause Notification Center to freeze

This appears to affect only a small amount of users. To prevent this from happening, uncheck the box for "Snap windows by dragging".
See issue [317](https://github.com/rxhanson/Rectangle/issues/317).

### Troubleshooting
If windows aren't resizing or moving as you expect, here's some initial steps to get to the bottom of it. Most issues of this type have been caused by other apps.
1. Make sure macOS is up to date, if possible.
1. Restart your machine.
1. Make sure there are no other window manager applications running.
1. Make sure that the app whose windows are not behaving properly does not have any conflicting keyboard shortcuts.
1. Try using the menu items to execute a window action or changing the keyboard shortcut to something different so we can tell if it's a keyboard shortcut issue or not.
1. Enable debug logging, as per the instructions in the following section.
1. The logs are pretty straightforward. If your calculated rect and your resulting rect are identical, chances are that there is another application causing issues. Save your logs if needed to attach to an issue if you create one.
1. If you suspect there may be another application causing issues, try creating and logging in as a new macOS user.

## View Debug Logging
1. Hold down the alt (option) key with the Rectangle menu open. 
1. Select the "View Logging..." menu item, which is in place of the "About" menu item.
1. Logging will appear in the window as you perform Rectangle commands.

## Preferences Storage
The configuration for Rectangle is stored using NSUserDefaults, meaning it is stored in the following location:
`~/Library/Preferences/com.knollsoft.Rectangle.plist`
Note that shortcuts in v0.41+ are stored in a different format and will not load in prior versions.

That file can be backed up or transferred to other machines. 

If you are using Rectangle v0.44+, you can also use the import/export button in the Preferences pane to share to your preferences and keyboard shortcuts across machines using a JSON file.

---

## Contributing
Logic from Rectangle is used in the [Multitouch](https://multitouch.app) app. The [Hookshot](https://hookshot.app) app is entirely built on top of Rectangle. If you contribute significant code or localizations that get merged into Rectangle, you get a free license of Multitouch or Hookshot. Contributors to Sparkle, MASShortcut, or Spectacle can also receive free Multitouch or Hookshot licenses (just send me a direct message on [Gitter](https://gitter.im)). 

### Localization
Initial localizations were done using [DeepL](https://www.deepl.com/translator) and Google Translate, but many of them have been updated by contributors. Translations that weren't done by humans can definitely be improved. If you would like to contribute to localization, all of the translations are held in the Main.strings per language. If you would like to add a localization but one doesn't currently exist and you don't know how to create one, create an issue and a translation file can be initialized.

Pull requests for new localizations or improvements on existing localizations are welcome.

### Running the app in Xcode (for developers)
Rectangle uses [CocoaPods](https://cocoapods.org/) to install Sparkle and MASShortcut. 

1. Make sure CocoaPods is installed and up to date on your machine (`sudo gem install cocoapods`).
1. Execute `pod install` the root directory of the project. 
1. Open the generated xcworkspace file (`open Rectangle.xcworkspace`).
