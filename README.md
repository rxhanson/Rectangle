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

## Contributing
I use the logic from Rectangle in the [Multitouch](https://multitouch.app) app. If you contribute to Rectangle, or contributed to Spectacle, then you get a Multitouch license for free. 
