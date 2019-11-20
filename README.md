# Rectangle

Rectangle is a window management app based on Spectacle, written in Swift.

## System Requirements
Rectangle arbitrarily supports macOS v10.12+. If you're willing to test on earlier versions of macOS, this can be updated.

##  Keyboard Shortcuts
The default keyboard shortcuts are based on Spectacle, but there is a recommended alternative set of defaults based on the Magnet app. This can be enabled by setting "alternateDefaultShortcuts" to true in NSUserDefaults for Rectangle with the following Terminal command:

`defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true`

Then restart the Rectangle app.

##  Differences with Spectacle
Spectacle used its own keyboard shortcut recorder, while Rectangle uses [MASShortcut](https://github.com/shpakovski/MASShortcut), a well maintained open source library for shortcut recording in macOS apps. This cuts down dramatically on the number of bugs that were only in Spectacle because of the custom shortcut recorder. 

### Additional features
* Additional window actions: move windows to each edge without resizing, maximize only the height of a window, almost maximizing a window. 
* Next/prev screen thirds is replaced with explicitly first third, first two thirds, center third, last two thirds, and last third. Screen orientation is taken into account, as in first third will be left third on landscape and top third on portrait.
* There's an option to have windows traverse across displays on subsequent left or right executions, similar to what Microsoft provided in Windows 7.
* Windows will snap when dragged to edges/corners of the screen. This can be disabled.

## Contributing
Logic from Rectangle is used in the [Multitouch](https://multitouch.app) app. Code contributors to Rectangle or Spectacle are entitled to a free license of Multitouch. 

### Localization
Localization was done using [DeepL](https://www.deepl.com/translator). Since it wasn't done by a person, it's likely that the translations can be improved. If you would like to contribute to localization, all of the translations are held in the Main.strings per language.

Pull requests for localizations are welcome. Japanese, Chinese, and Korean localizations are needed.

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

## Debug Logging
To enable debug logging (starting in v0.9.1), execute the following Terminal command:

`defaults write com.knollsoft.Rectangle debug -bool true`

Then restart the app.

To view logs:
1. Open Console.app
1. Select Action -> Include Debug Messages in the menu
1. Enter this in the search bar: `process:Rectangle any:calculatedRect`

## Installation
You can download the latest dmg from https://rectangleapp.com or the [Releases page](https://github.com/rxhanson/Rectangle/releases).

Or install with brew cask:

`brew cask install rectangle`
