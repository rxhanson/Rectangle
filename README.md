# Rectangle

[![Build](https://github.com/rxhanson/Rectangle/actions/workflows/build.yml/badge.svg)](https://github.com/rxhanson/Rectangle/actions/workflows/build.yml)

Rectangle is a window management app based on Spectacle, written in Swift.

![Screenshot](https://user-images.githubusercontent.com/13651296/183785536-a67a2e2a-7c55-4c19-9bf8-482e734b1632.png)

## System Requirements

Rectangle supports macOS v10.11+.

## Installation

You can download the latest dmg from <https://rectangleapp.com> or the [Releases page](https://github.com/rxhanson/Rectangle/releases).

Or install with brew cask:

```bash
brew install --cask rectangle
```

## How to use it

The [keyboard shortcuts](https://support.apple.com/guide/mac-help/what-are-those-symbols-shown-in-menus-cpmh0011/mac) are self explanatory, but the snap areas can use some explanation if you've never used them on Windows or other window management apps.

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
1. Open the Rectangle menu and select "Ignore app"

## Execute an action by URL

Open the URL `rectangle://execute-action?name=[name]`. Do not activate Rectangle.

Available values for `[name]`: `left-half`, `right-half`, `center-half`, `top-half`, `bottom-half`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, `first-third`, `center-third`, `last-third`, `first-two-thirds`, `last-two-thirds`, `maximize`, `almost-maximize`, `maximize-height`, `smaller`, `larger`, `center`, `restore`, `next-display`, `previous-display`, `move-left`, `move-right`, `move-up`, `move-down`, `first-fourth`, `second-fourth`, `third-fourth`, `last-fourth`, `first-three-fourths`, `last-three-fourths`, `top-left-sixth`, `top-center-sixth`, `top-right-sixth`, `bottom-left-sixth`, `bottom-center-sixth`, `bottom-right-sixth`, `specified`, `reverse-all`, `top-left-ninth`, `top-center-ninth`, `top-right-ninth`, `middle-left-ninth`, `middle-center-ninth`, `middle-right-ninth`, `bottom-left-ninth`, `bottom-center-ninth`, `bottom-right-ninth`, `top-left-third`, `top-right-third`, `bottom-left-third`, `bottom-right-third`, `top-left-eighth`, `top-center-left-eighth`, `top-center-right-eighth`, `top-right-eighth`, `bottom-left-eighth`, `bottom-center-left-eighth`, `bottom-center-right-eighth`, `bottom-right-eighth`, `tile-all`, `cascade-all`

Example, from a shell: `open -g "rectangle://execute-action?name=left-half"`

## Terminal Commands for Hidden Preferences

See [TerminalCommands.md](TerminalCommands.md)

## Differences with Spectacle

* Rectangle uses [MASShortcut](https://github.com/shpakovski/MASShortcut) for keyboard shortcut recording. Spectacle used its own shortcut recorder.
* Rectangle has additional window actions: move windows to each edge without resizing, maximize only the height of a window, almost maximizing a window.
* Next/prev screen thirds is replaced with explicitly first third, first two thirds, center third, last two thirds, and last third. Screen orientation is taken into account, as in first third will be left third on landscape and top third on portrait.
  * You can however emulate Spectacle's third cycling using first and last third actions. So, if you repeatedly execute first third, it will cycle through thirds (first, center, last) and vice-versa with the last third.
* There's an option to have windows traverse across displays on subsequent left or right executions.
* Windows will snap when dragged to edges/corners of the screen. This can be disabled.

## Common Known Issues

### Rectangle doesn't have the ability to move to other desktops/spaces

Apple never released a public API for Spaces. Other apps that move windows between spaces use unsupported or undesirable ways to achieve this. If Apple decides to release a public API for it, I'll add it in.

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

## Import & export JSON config

There are buttons for importing and exporting the config as a JSON file in the settings tab of the preferences window. 

Upon launch, Rectangle will load a config file at `~/Library/Application Support/Rectangle/RectangleConfig.json` if it is present and will rename that file with a time/date stamp so that it isn't read on subsequent launches.

## Preferences Storage

The configuration for Rectangle is stored using NSUserDefaults, meaning it is stored in the following location:
`~/Library/Preferences/com.knollsoft.Rectangle.plist`
Note that shortcuts in v0.41+ are stored in a different format and will not load in prior versions.

That file can be backed up or transferred to other machines.

If you are using Rectangle v0.44+, you can also use the import/export button in the Preferences pane to share to your preferences and keyboard shortcuts across machines using a JSON file.

## Uninstallation

Rectangle can be uninstalled by moving it to the trash. Prior to moving it to the trash, you might want to uncheck the box for launching on login to unregister the launcher, but this is not necessary. You can remove the Rectangle defaults from your machine with the following terminal command:

```bash
defaults delete com.knollsoft.Rectangle
```

---

## Contributing

Logic from Rectangle is used in the [Multitouch](https://multitouch.app) app. The [Rectangle Pro](https://rectangleapp.com/pro) app is entirely built on top of Rectangle. If you contribute significant code or localizations that get merged into Rectangle, you get a free license of Multitouch or Rectangle Pro. Contributors to Sparkle, MASShortcut, or Spectacle can also receive free Multitouch or Rectangle Pro licenses (just send me a direct message on [Gitter](https://gitter.im)).

### Localization

If you would like to contribute to localization, all of the translations are held in the Main.strings per language. If you would like to add a localization but one doesn't currently exist and you don't know how to create one, create an issue and a translation file can be initialized.

Pull requests for new localizations or improvements on existing localizations are welcome.

### Running the app in Xcode (for developers)

Rectangle uses [CocoaPods](https://cocoapods.org/) to install Sparkle and MASShortcut.

1. Make sure CocoaPods is installed and up to date on your machine (`sudo gem install cocoapods`).
1. Execute `pod install` the root directory of the project.
1. Open the generated xcworkspace file (`open Rectangle.xcworkspace`).
