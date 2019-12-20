# Rectangle

Rectangle is a window management app based on Spectacle, written in Swift.

## System Requirements
Rectangle arbitrarily supports macOS v10.12+. If you're willing to test on earlier versions of macOS, this can be updated.

## Keyboard Shortcuts
The default keyboard shortcuts are based on Spectacle, but there is a recommended alternative set of defaults based on the Magnet app. This can be enabled by setting "alternateDefaultShortcuts" to true in NSUserDefaults for Rectangle with the following Terminal command:

`defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true`

Then restart the Rectangle app. 

## Differences with Spectacle
Spectacle used its own keyboard shortcut recorder, while Rectangle uses [MASShortcut](https://github.com/shpakovski/MASShortcut), a well maintained open source library for shortcut recording in macOS apps. This cuts down dramatically on the number of bugs that were only in Spectacle because of the custom shortcut recorder. 

### Additional features
* Additional window actions: move windows to each edge without resizing, maximize only the height of a window, almost maximizing a window. 
* Next/prev screen thirds is replaced with explicitly first third, first two thirds, center third, last two thirds, and last third. Screen orientation is taken into account, as in first third will be left third on landscape and top third on portrait.
* There's an option to have windows traverse across displays on subsequent left or right executions, similar to what Microsoft provided in Windows 7.
* Windows will snap when dragged to edges/corners of the screen. This can be disabled.

### Details on halves to thirds (subsequent execution of half and quarter actions)
The default behavior for Rectangle is based on Spectacle. Each time you execute a half or quarter action, the width of the window will cycle through the following sizes: 1/2 -> 2/3 -> 1/3.

This behavior can be disabled with the following terminal command:

`defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 2`

Followed by a restart of the app.

Note that the `subsequentExecutionMode` is also tied to the setting for traversing displays in the prefs.

### Details on Almost Maximize
By default, "Almost Maximize" will resize the window to 90% of the screen (width & height). These values can be adjusted with the following terminal commands:

`defaults write com.knollsoft.Rectangle almostMaximizeHeight -float <VALUE_BETWEEN_0_&_1>`

`defaults write com.knollsoft.Rectangle almostMaximizeWidth -float <VALUE_BETWEEN_0_&_1>`

Followed by a restart of the app.

## Contributing
Logic from Rectangle is used in the [Multitouch](https://multitouch.app) app. If you contribute code or localizations that get merged into Rectangle, you get a free license of Multitouch. Contributors to Sparkle, MASShortcut, or Spectacle can also receive a free license of Multitouch (just send me a direct message on [Gitter](https://gitter.im)). 

### Localization
Localization was done using [DeepL](https://www.deepl.com/translator) and Google Translate. Since it wasn't done by a person, it's likely that the translations can be improved. If you would like to contribute to localization, all of the translations are held in the Main.strings per language.

Pull requests for new localizations or improvements on existing localizations are welcome.

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

## Installation
You can download the latest dmg from https://rectangleapp.com or the [Releases page](https://github.com/rxhanson/Rectangle/releases).

Or install with brew cask:

`brew cask install rectangle`
