import SwiftUI

enum TrackpadChoiceEntry {
    case option(String, Int)
    case separator
    case submenu(String, [TrackpadChoiceEntry])
}
