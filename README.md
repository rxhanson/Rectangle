# Rectangle

![](https://github.com/rxhanson/Rectangle/workflows/Build/badge.svg)

Rectangle is a window management app based on Spectacle, written in Swift.

![image](https://user-images.githubusercontent.com/13651296/71896594-7cdb9280-3154-11ea-83a7-70b71c6df9d4.png)

## System Requirements
Rectangle supports macOS v10.11+. If you're willing to test on earlier versions of macOS, this can be updated.

## Installation
You can download the latest dmg from https://rectangleapp.com or the [Releases page](https://github.com/rxhanson/Rectangle/releases).

Or install with brew cask:

```bash
brew cask install rectangle
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

## Keyboard Shortcuts
The default keyboard shortcuts are based on Spectacle, but there is a recommended alternative set of defaults based on the Magnet app. This can be enabled by setting "alternateDefaultShortcuts" to true in NSUserDefaults for Rectangle with the following Terminal command:

```bash
defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
```

Then restart the Rectangle app. 

## Differences with Spectacle
Spectacle used its own keyboard shortcut recorder, while Rectangle uses [MASShortcut](https://github.com/shpakovski/MASShortcut), a well maintained open source library for shortcut recording in macOS apps. This cuts down dramatically on the number of bugs that were only in Spectacle because of the custom shortcut recorder. 

### Additional features
* Additional window actions: move windows to each edge without resizing, maximize only the height of a window, almost maximizing a window. 
* Next/prev screen thirds is replaced with explicitly first third, first two thirds, center third, last two thirds, and last third. Screen orientation is taken into account, as in first third will be left third on landscape and top third on portrait.
* There's an option to have windows traverse across displays on subsequent left or right executions, similar to what Microsoft provided in Windows 7.
* Windows will snap when dragged to edges/corners of the screen. This can be disabled.

### Details on halves to thirds (subsequent execution of half and quarter actions)
Halves to thirds is controlled by the "Cycle displays" setting in the preferences. 
If the cycle displays setting is not checked, then each time you execute a half or quarter action, the width of the window will cycle through the following sizes: 1/2 -> 2/3 -> 1/3.

The cycling behavior can be disabled with the following terminal command:

```bash
defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 2
```

Followed by a restart of the app.

`subsequentExecutionMode` accepts the following values:
0: halves to thirds Spectacle behavior (box unchecked)
1: cycle displays (box checked)
2: disabled
3: cycle displays for left/right actions, halves to thirds for the rest (old Rectangle behavior)

### Details on Almost Maximize
By default, "Almost Maximize" will resize the window to 90% of the screen (width & height). These values can be adjusted with the following terminal commands:

```bash
defaults write com.knollsoft.Rectangle almostMaximizeHeight -float <VALUE_BETWEEN_0_&_1>
```

```bash
defaults write com.knollsoft.Rectangle almostMaximizeWidth -float <VALUE_BETWEEN_0_&_1>
```

Followed by a restart of the app.

### Details on Adding Gaps Between Windows

As of v0.17, gaps between windows can be added with the following command:

```bash
defaults write com.knollsoft.Rectangle gapSize -float <NUM_PIXELS>
```

Followed by a restart of the app.

### Details on Move Up/Down/Left/Right

The current default behavior of these actions is to center the window along the edge that the window is being moved to. 

As of v0.19, the centering can be disabled with the following command:

```bash
defaults write com.knollsoft.Rectangle centeredDirectionalMove -int 2
```
Followed by a restart of the app.

## Contributing
Logic from Rectangle is used in the [Multitouch](https://multitouch.app) app. The [Hookshot](https://hookshot.app) app is entirely built on top of Rectangle. If you contribute significant code or localizations that get merged into Rectangle, you get free licenses of Multitouch and Hookshot. Contributors to Sparkle, MASShortcut, or Spectacle can also receive free Multitouch or Hookshot licenses (just send me a direct message on [Gitter](https://gitter.im)). 

### Localization
Initial localizations were done using [DeepL](https://www.deepl.com/translator) and Google Translate, but many of them have been updated by contributors. Translations that weren't done by humans can definitely be improved. If you would like to contribute to localization, all of the translations are held in the Main.strings per language. If you would like to add a localization but one doesn't currently exist and you don't know how to create one, create an issue and a translation file can be initialized.

Pull requests for new localizations or improvements on existing localizations are welcome.

### Running the app in Xcode (for developers)
Rectangle uses [CocoaPods](https://cocoapods.org/) to install Sparkle and MASShortcut. 

1. Make sure CocoaPods is installed and up to date on your machine (`sudo gem install cocoapods`).
1. Execute `pod install` the root directory of the project. 
1. Open the generated xcworkspace file (`open Rectangle.xcworkspace`).

#### Signing
- When running in Xcode (debug), Rectangle is signed to run locally with no developer ID configured.
- You can run the app out of the box this way, but you might have to authorize the app in System Prefs every time you run it. 
- If you don't want to authorize in System Prefs every time you run it and you have a developer ID set up, you'll want to use that to sign it and additionally add the Hardened Runtime capability to the Rectangle and RectangleLauncher targets. 

## Troubleshooting
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

That file can be backed up or transferred to other machines.
