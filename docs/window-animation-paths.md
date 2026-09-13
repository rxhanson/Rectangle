# Window animation paths

Snap Areas keeps the **Animate windows (experimental)** checkbox and adds an **Animation style** selector:

- **Blur preview** uses the frosted animation path. A frosted cover animates while recovery manages the real window's hidden placement.
- **Direct resize** is the default when no style is saved. It animates the real window's position and size through Accessibility, using the direct implementation preserved at `fe06e88`. The application's contents remain visible and resize throughout the transition.

Direct resize uses the original full `NSVisualEffectView` blur preview with a 12 pt corner radius and exterior shadow. Blur preview retains its glow outline. Preview geometry keeps the shared 260 ms deceleration curve in both modes; the real direct resize keeps its original 340 ms curve. Direct drag restore applies the saved size immediately; command and title-bar restores animate.

The preference is `windowAnimationStyle`: `0` for frosted, `1` for direct. It participates in configuration export/import; missing or invalid values default to direct; saved selections are preserved. Disabling animation retains the selected style. Only the frosted style requires Blur footprint; the direct style leaves that independent preview preference editable.

## Responsibilities

| File | Responsibility |
| --- | --- |
| `Rectangle/Defaults.swift` | Style values, migration default, accessibility policy and blur dependency. |
| `Rectangle/PrefsWindow/SnapAreaViewController.swift` | Checkbox and style selector, accessibility labels and settings-change notification. |
| `Rectangle/WindowMover/WindowAnimator.swift` | Common entry point, logical destination, style routing and frosted recovery coordination. |
| `Rectangle/WindowMover/WindowAnimationCurves.swift` | Original window easing and shared preview timing, separate from animation routing. |
| `Rectangle/WindowMover/DirectWindowAnimator.swift` | Direct frame interpolation, final AX placement, interruption and Enhanced UI cleanup. |
| `Rectangle/WindowMover/WindowFrostTransition.swift` | Frosted transition lifecycle. |
| `Rectangle/WindowMover/WindowFrostOverlay.swift` | Frosted rendering and input surfaces. |
| `Rectangle/WindowMover/FrostedRestoreDragController.swift` | Owns eligible restore drags only for the frosted path. |
| `Rectangle/Snapping/SnappingManager.swift` | Immediate native drag restoration with placement based on the original grab point. |

## Routing and lifetime

Frosted drag restore requires observed native window movement, including movement first observed at mouse-up. Its native handoff uses a 500 ms observation budget for matching AX and WindowServer frames to remain stable. Observation times are sampled after the reads return; a blocked read can extend elapsed time but cannot backdate stability. Escape waits for settlement before restoring the original snap. If handoff or preview creation fails, ordinary following retains the owned input sequence and completes restoration or snapping at its actual release. Replanning a clamped covered shrink accepts reachable destinations across display seams while continuing to verify every hidden operation.

Keyboard, menu and titlebar actions use the same style selector. Direct resize preserves the original 340 ms curve for maximizing and snapping. Only drag restore applies the saved frame immediately. Explicit Restore, title-bar double-click restore and repeated-maximize restoration animate from the current frame, replacing older direct motion. A frosted recovery lease still delays writes until release. Direct animation supports constrained placement using the application's achieved minimum size, rather than assuming every requested size was accepted.

Direct completion restores the normal Accessibility timeout, then performs its final AX placement and readback before returning success: current callers interpret a non-null frame as already placed. Failed final placement requests ordinary fallback. Replacing the same window cancels the older completion; replacing another window finishes its previous placement. Manual grabs finish a running direct animation. Focus changes, Space changes, sleep, display changes and Mission Control interruption stop applicable pending work.

Released drag-to-snap actions may animate across displays, including endpoints that do not overlap the same screen. Both animation paths wait for matching AX and WindowServer frames to remain stable for 33 ms, with a 150 ms soft observation budget. This accounts for native position or size restoration after mouse-up; main-thread scheduling and AX reads can extend elapsed time. Direct mode compares the displays containing the settled source and final destination, using their largest window intersection. A cross-display released snap requests ordinary placement without starting a movement or resize animation. A same-display released snap starts its animation clock and interpolation from the settled frame. Neither route modifies Accessibility settings or writes animation frames during the wait. If stability cannot be established, it requests ordinary placement. A newer request or interruption invalidates pending settlement; a new mouse grab cancels a pending direct snap before it writes.

Drag target selection retains the mouse-down event's handling window ID and position. A delayed main-queue callback or lookup retry cannot switch to a different window beneath the newer pointer position. Release-time snap selection likewise uses the release event's position and display, recomputing the edge target before committing it.

Frosted restore starts after the original window actually moves. Native handoff requires matching AX and WindowServer frames stable for at least one 60 Hz frame, with a 150 ms observation budget. A delayed callback may confirm a previously matching frame after that budget; a new, changed, missing, or conflicting frame cannot extend the wait. If the app retains a stale AX position while both sources stop changing for 33 ms, the controller may reassert the displayed WindowServer position once, after checking the same focused window and original size. Parking still waits for subsequent matching readback. A very quick release can wait for late native movement, but a click, resize, or gesture that never moves the original window does not force a restore.

After release, the parking planner may use any verified safe corner. It resizes offscreen when possible, otherwise prepares a compact size and grows under the acknowledged destination cover. A restored window taller than the available parking display first shrinks height beneath its source cover while preserving width. Held drags retain their local parking rules. Ordinary placement, fallback completion and already-achieved snaps also dismiss the committed outline; frosted display commands use continuous motion between physically adjacent left/right screens and a fade between other pairs. They prefer a compact source-corner parking route with growth beneath the destination cover. Direct display commands retain their existing path. Escape during an ordinary drag suppresses both preview and release-time snap until the next mouse-down.

If macOS clamps a native drag's covered shrink to keep its titlebar reachable, the source cover allows a 150 ms release grace period. A sustained hold then recovers ordinary pointer following. The released drag can then retry once at a verified hidden corner using its requested restore size. The temporary clamped width is not learned as an application minimum. Cancellation restores through the existing lease; a forced finish drains the waiting state. If no safe route exists or the retry fails, ordinary recovery remains available.

Rapid display-command replacements share a compact preparation and retain the same cover and lease. If a replacement interrupts placement, the pending write finishes under its existing cover; the next movement starts from that verified result. Final placement waits for 180 ms of command quiet after a replacement. This avoids recovery to the original source during ordinary repeated-command handoffs, although system placement and verification still take time.

Direct constrained frames write position before size. Intermediate writes do not read an old size back and use it to reposition the window; final alignment still uses the achieved size. Cross-display released snaps avoid direct animation because native frame adjustments can overwrite accepted Accessibility writes during the transition. Keyboard/menu display commands retain their existing path; drag restore performs one ordinary frame adjustment without interpolating intermediate sizes.

A settings change settles the running animation and updates frosted prewarming and drag admission. A direct request for a window still reserved by frosted recovery waits for release before writing to it. Direct mode does not acquire a frosted lease or start frosted prewarming. Both styles exclude native fullscreen windows and respect Reduce Motion, VoiceOver and Switch Control; Reduce Transparency disables only the frosted style.

The older header classification helpers remain covered by regression fixtures, but do not admit production restore drags. Tabs, toolbar controls and page content retain native input; titlebar guesses do not substitute for observed window movement.

Automatic frosted motion accepts the existing keyboard replacements. Mouse clicks and drags on its protected source, current cover or destination cannot pause, cancel or take over the animation. Consumed mouse sequences drain through their matching release, including releases after the visual closes; fresh presses after completion use the normal mouse path. Escape and environment recovery retain their existing behavior.
