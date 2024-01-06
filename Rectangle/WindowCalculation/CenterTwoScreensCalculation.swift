import Foundation

enum ScreenDirection {
  case up
  case down
  case left
  case right
}

/// Centers a window in between two horizontally or vertically stacked displays.
///
/// # Assumptions
/// - The user only has two screens.
/// - The screens may be different sizes.
/// - The screens can be stacked vertically or horizontally, with the line connecting their centers either vertical or horizontal.
///
/// # Algorithm
/// 1. Get the display that the window started on.
/// 2. Get the next display.
/// 3. Figure out whether the next display is to the left, right, top or bottom of the starting display.
/// 4. Figure out which display is smaller.
/// 5. Position the window in the middle of the two screens.
///
/// # Notes
/// This does not work for vertically stacked monitors and I don't know why.
class CenterTwoScreensCalculation: WindowCalculation {

  override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {

    // Step 1
    let initialScreen = params.usableScreens.currentScreen.frame

    // Step 2
    let secondScreen = params.usableScreens.adjacentScreens?.next.frame

    guard let secondScreen else {
      return WindowCalculationResult(
        rect: params.window.rect,
        screen: params.usableScreens.currentScreen,
        resultingAction: params.action)
    }

    // Step 3
    var directionOfSecondScreen = ScreenDirection.right

    // Check if initial screen is above second screen
    if initialScreen.midY < secondScreen.midY {
      directionOfSecondScreen = ScreenDirection.up
    }
    // Check if initial screen is below second screen
    if initialScreen.midY > secondScreen.midY {
      directionOfSecondScreen = ScreenDirection.down
    }
    // Check if initial screen is left of second screen
    if initialScreen.midX < secondScreen.midX {
      directionOfSecondScreen = ScreenDirection.right
    }
    // Check if initial screen is right of second screen
    if initialScreen.midX > secondScreen.midX {
      directionOfSecondScreen = ScreenDirection.left
    }

    // Step 4
    var smallerScreen = initialScreen

    // If the windows are horizontally stacked, we define the smaller screen as the one that has the smaller width
    if directionOfSecondScreen == ScreenDirection.left
      || directionOfSecondScreen == ScreenDirection.right
    {
      if initialScreen.width < secondScreen.width {
        smallerScreen = initialScreen
      } else {
        smallerScreen = secondScreen
      }
    }
    // If the windows are verticalled stacked, we define the smaller screen as the one that has the smaller height
    if directionOfSecondScreen == ScreenDirection.up
      || directionOfSecondScreen == ScreenDirection.down
    {
      if initialScreen.height < secondScreen.height {
        smallerScreen = initialScreen
      } else {
        smallerScreen = secondScreen
      }
    }

    // Step 5
    // We need to know if the inital screen is the main screen or not because the coordinate system originates on the main screen
    let initialScreenIsMain = initialScreen.origin.equalTo(CGPoint(x: 0, y: 0))

    let rectResult = calculateRect(
      params.asRectParams(visibleFrame: smallerScreen),
      directionOfSecondScreen: directionOfSecondScreen, initialScreenIsMain: initialScreenIsMain)

    let screenFrame = initialScreen.union(secondScreen)

    return WindowCalculationResult(
      rect: rectResult.rect,
      screen: params.usableScreens.currentScreen,
      resultingAction: params.action,
      resultingScreenFrame: screenFrame)
  }

  func calculateRect(
    _ params: RectCalculationParameters, directionOfSecondScreen: ScreenDirection,
    initialScreenIsMain: Bool
  ) -> RectResult {
    var calculatedWindowRect = params.window.rect

    // Make the window as tall as the screen
    calculatedWindowRect.size.height = params.visibleFrameOfScreen.height

    // Make the window as wide as the screen
    calculatedWindowRect.size.width = params.visibleFrameOfScreen.width

    let halfScreenHeight = params.visibleFrameOfScreen.height / 2
    let halfScreenWidth = params.visibleFrameOfScreen.width / 2

    switch directionOfSecondScreen {
    case ScreenDirection.down:
      // Position the bottom of the window at the midpoint of the bottom screen
      calculatedWindowRect.origin.y = initialScreenIsMain ? -1 * halfScreenHeight : halfScreenHeight

      // Position the left side of the window at the left of the screen
      calculatedWindowRect.origin.x = 0

      break
    case ScreenDirection.up:
      // Position the bottom of the window at the midpoint of the bottom screen
      calculatedWindowRect.origin.y = initialScreenIsMain ? halfScreenHeight : -1 * halfScreenHeight

      // Position the left side of the window at the left of the screen
      calculatedWindowRect.origin.x = 0

      break
    case ScreenDirection.left:
      // Position the bottom of the window at the bottom of the screen
      calculatedWindowRect.origin.y = params.visibleFrameOfScreen.origin.y

      // Position the left side of the window at the midpoint of the left screen
      let midpointOfLeftScreen = initialScreenIsMain ? -1 * halfScreenWidth : halfScreenWidth
      calculatedWindowRect.origin.x = midpointOfLeftScreen

      break
    case ScreenDirection.right:
      // Position the bottom of the window at the bottom of the screen
      calculatedWindowRect.origin.y = params.visibleFrameOfScreen.origin.y

      // Position the left side of the window at the midpoint of the left screen
      let midpointOfLeftScreen = initialScreenIsMain ? halfScreenWidth : -1 * halfScreenWidth
      calculatedWindowRect.origin.x = midpointOfLeftScreen

      break
    }

    return RectResult(calculatedWindowRect)
  }
}
