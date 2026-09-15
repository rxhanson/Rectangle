# Window animation paths

**Animate windows (experimental)** animates the actual application's position and size through Accessibility. The contents remain visible throughout the transition. Blur preview animation is maintained separately on `dev/blur-preview`; this branch has no animation-style selector, renderer subprocess, window parking, recovery lease, or preview input interception. Saved `windowAnimationStyle` values are ignored and omitted from configuration export.

**Blur footprint** remains an independent appearance option for the ordinary snap target preview. It uses `NSVisualEffectView`, a 12 pt corner radius and an exterior shadow. Disabling window animation leaves this preference unchanged. Snap previews retain their 260 ms deceleration curve; actual window animation retains its 340 ms curve.

## Placement and interruption

Keyboard, menu and title-bar restores animate. Native drag restore applies the saved size immediately, leaving the held drag's position to macOS. Undersized and oversized readbacks remain pending: restoration retries after native movement makes room, or once after release.

Completion restores the normal Accessibility timeout, performs final AX placement and readback, then reports success. Failed placement requests ordinary fallback. Replacing the same window cancels its older completion; replacing another window finishes the previous placement. A manual grab finishes running motion. Focus changes, Space changes, sleep, display changes and Mission Control stop applicable pending work.

Constrained placement aligns the application's achieved size, including minimum-size and aspect-constrained windows. The size-limit warning remains available. IINA size-changing commands resize once and allow its asynchronous aspect-ratio adjustment to settle, then align through a position-only write. Position-only IINA commands still animate.

Released drag-to-snap actions wait for matching Accessibility and WindowServer frames to remain stable for 33 ms, with a 150 ms soft observation budget. Scheduling and AX reads can extend elapsed time. A same-display snap animates from the settled frame. A cross-display snap, or a settlement timeout, requests ordinary placement. No animation frame writes occur during the wait. A newer request or interruption invalidates settlement; a new grab cancels it without snapping to the previous target.

Drag targeting retains the original mouse-down position and handling window ID. Release-time selection uses the release event's position and display, recomputing the edge target before committing it.

Reduce Motion, VoiceOver and Switch Control disable window animation. Reduce Transparency leaves direct window animation available while the ordinary footprint uses its opaque fallback.

Optional local diagnostics use `RECTANGLE_ANIMATION_TRACE_PATH`. Normal launches do no trace-file work. Automated test fixtures remain outside the repository.
