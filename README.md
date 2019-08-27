# Rectangle

Rectangle is a window management app based on Spectacle, written in Swift.

## System Requirements
Rectangle arbitrarily supports macOS v10.12+. If you're willing to test on earlier versions of macOS, this can be updated.

##  Keyboard Shortcuts
The default keyboard shortcuts are based on Spectacle, but there is an alternative set of defaults based on the Magnet app. This can be enabled by setting "alternateDefaultShortcuts" to true in NSUserDefaults for Rectangle with the following Terminal command:

`defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true`

Then restart the Rectangle app.

##  Differences with Spectacle
Spectacle used it's own keyboard shortcut recorder, while Rectangle uses [MASShortcut](https://github.com/shpakovski/MASShortcut), a well maintained open source library for shortcut recording in macOS apps. This cuts down dramatically on the number of bugs that were only in Spectacle because of the custom shortcut recorder. 

Spectacle had everything localized, and Rectangle is still lacking localization. Feel free to send a pull request for this or anything else missing.

Rectangle has a few additional actions, including moving windows to screen edges without resizing them, maximizing only the height of a window, and almost (90%) maximizing a window. Additionally, next/prev screen thirds is replaced with explicitly first third, first two thirds, center third, last two thirds, and last third. Note that these thirds actions take into account screen orientation, as in first third will be left third on landscape and top third on portrait.

## Contributing
Logic from Rectangle is used in the [Multitouch](https://multitouch.app) app. Contributors to Rectangle or Spectacle are entitled to a free license of Multitouch. 
