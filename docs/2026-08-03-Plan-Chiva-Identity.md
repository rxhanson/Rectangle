# Plan — Chiva Full Identity + `/Applications` Install

Status: Reviewed (Codex green — rev 4)

## Goal

Ship the same working Chiva window-snapper, clearly identified as **Chiva**, installed
at **`/Applications/Chiva.app`**, with bundle ID **`com.perg593.chiva`**. Clean out old
Divvy2 paths, login items, and user-facing Rectangle leftovers. Do **not** change snap /
custom-layout behavior.

## Context

Today the product name is already `Chiva` (`PRODUCT_NAME`, `CFBundleDisplayName`,
`Chiva.app`), but:

- Install path is `~/Applications/Divvy2/Chiva.app`
- Bundle ID is still `com.perg593.divvy2`
- URL scheme is `divvy2`
- Menus/alerts/storyboards still say Rectangle in places
- Dev signing identity / keychain paths still say Divvy2

This plan is an identity cutover, not a feature milestone.

## Hard constraints

1. Do **not** rename the Xcode project/targets/module (`Rectangle*`,
   `PRODUCT_MODULE_NAME = Rectangle`). Internal build plumbing; renaming risks breaking
   imports/tests for no user benefit. Internal type/symbol names containing “Rectangle”
   stay.
2. Do **not** change window-snap / custom-layout logic.
3. Preserve settings via API-based prefs migration (see §D).
4. **Whitelist** (do not replace): shortcut-preset buttons labeled **Rectangle** /
   **Spectacle**; internal module/class/symbol names; historical `docs/2026-06-23-*`.
5. Branch: `feature/chiva-identity` from `origin/main`.

## Identity map

| Surface | From | To |
|---|---|---|
| Install path | `~/Applications/Divvy2/Chiva.app` | `/Applications/Chiva.app` |
| Main bundle ID | `com.perg593.divvy2` | `com.perg593.chiva` |
| Launcher ID | `com.perg593.divvy2.RectangleLauncher` | `com.perg593.chiva.launcher` |
| Tests ID | `com.perg593.divvy2.RectangleTests` | `com.perg593.chiva.tests` |
| Spike helper ID | `com.perg593.divvy2.spikehelper` | `com.perg593.chiva.spikehelper` |
| URL scheme | `divvy2` | `chiva` |
| Custom layouts key + notifications | `com.perg593.divvy2.*` | `com.perg593.chiva.*` |
| Dev signing CN / keychain | `Divvy2 Dev`, `~/.config/divvy2`, `divvy2-signing.keychain-db` | `Chiva Dev`, `~/.config/chiva`, `chiva-signing.keychain-db` |
| Display name / product | already `Chiva` | keep |
| Migration marker key | (new) | `com.perg593.chiva.identityMigrationCompleted` = 1 |

## Implementation steps

### A. Bundle IDs + URL scheme

Update `Rectangle.xcodeproj/project.pbxproj` product bundle identifiers for main /
launcher / tests / spike helper.

Update hardcoded IDs in:

- `Rectangle/AppDelegate.swift` (`launcherAppId`)
- `RectangleLauncher/AppDelegate.swift` (`mainAppIdentifier`)
- `Rectangle/ApplicationToggle.swift` (default `frontAppId`)
- `Rectangle/PrefsWindow/Config.swift` (`bundleId`)
- `Rectangle/Info.plist` (`CFBundleURLSchemes` → `chiva`)
- `Rectangle/CustomLayouts/CustomLayoutStore.swift` (defaults key + notification names)
- `Rectangle/CustomLayouts/CustomLayoutShortcutManager.swift` (notification name)
- Tests / spike suites that hardcode `com.perg593.divvy2…`

### B. Shipped-resource branding audit (user-facing → Chiva)

Replace **product-name** occurrences of Rectangle/Divvy/Divvy2 that a user can see in
shipped UI. Scope:

1. `Rectangle/mul.lproj/Main.xcstrings` — **all locales** for app-menu title, About,
   Quit, Hide, Help, Settings/Preferences window titles, Welcome, authorization copy,
   Todo instructions that name the app, logging titles that name the app. Whitelist:
   preset labels “Rectangle” / “Spectacle” only.
2. `Rectangle/Base.lproj/Main.storyboard` — “Authorize Rectangle”, permission body,
   Welcome, settings titles.
3. `Rectangle/Logging/LogViewer.storyboard` — “Rectangle Logging” → “Chiva Logging”.
4. Swift alert/copy in `AppDelegate.swift`, `MacTilingDefaults.swift`,
   `FootprintWindow.swift`, `InternetAccessPolicy.plist`, export default filename
   (`RectangleConfig` → `ChivaConfig` where it is *this* app’s export).
5. Source strings that feed localization lookups must stay in sync — e.g.
   `SettingsViewController.swift` product-name fallbacks / `NSLocalizedString` keys
   that still say Rectangle (whitelist: Rectangle/Spectacle **preset** buttons only).

Do **not** mass-replace “Rectangle” inside identifiers, types, `@testable import`,
or comments describing upstream architecture.

**Verification scan:** ripgrep shipped resources (`Main.xcstrings` all locales,
storyboards, Swift UI strings) for non-whitelisted product-name “Rectangle” /
“Divvy2” and fail the cutover checklist if any remain.

### C. Install + signing scripts (verified replacement)

`scripts/build-install.sh`:

- `DEST=/Applications`
- identity default `Chiva Dev`
- derived-data / log paths under `chiva-*`
- Stage → codesign verify build product → **replace** `$DEST/Chiva.app` (remove existing
  bundle, then `ditto`; do not merge into a stale tree) → codesign `--verify --deep
  --strict` on the **installed** path → check Info.plist display name / bundle ID /
  URL scheme at destination → `lsregister -f`
- Install only `Chiva.app` to `/Applications` (spike helper stays in derived data)

`scripts/dev-signing-setup.sh`:

- CN / keychain / config dir → Chiva names
- One-time new cert mint (AX re-grant required because bundle ID changes)

Cutover is orchestrated by `scripts/chiva-cutover.sh` (called before/with install).

### D. Prefs migration (MAJOR fix from Codex r1)

**Primary path: in-app, API-based, before any `Defaults` / `CustomLayoutStore` use.**

Add `IdentityMigration.runIfNeeded()` invoked at the very start of
`applicationDidFinishLaunching` (before `Defaults.*` reads):

1. If `UserDefaults.standard.bool(forKey: identityMigrationCompletedKey)` → return.
2. Read old domain via `UserDefaults.standard.persistentDomain(forName:
   "com.perg593.divvy2")`.
3. If old domain is nil/empty → set marker and return (fresh install).
4. Read current new-domain dict (may be partial). Merge strategy:
   - Start from old domain values
   - Overlay any already-present new-domain keys (new wins for conflicts)
   - Remap custom-layouts payload: if old key
     `com.perg593.divvy2.customLayouts` present and new key
     `com.perg593.chiva.customLayouts` absent, copy Data under the new key; always
     drop the old key from the dict written to the new domain
5. `setPersistentDomain(_:forName: "com.perg593.chiva")` then `synchronize`
6. Write marker `identityMigrationCompletedKey = true` **only after** successful
   write
7. **Preserve** the old `com.perg593.divvy2` domain (do not delete); cutover script
   may leave it as backup

Also: shell cutover may pre-copy via `defaults export/import` as a belt-and-suspenders
step, but the in-app path is authoritative and idempotent via the marker.

**Tests:** unit tests covering empty old domain, full migrate + key remap, partial
new-domain overlay, and second-run no-op (marker set).

### E. Login-item cleanup (MAJOR fix from Codex r1–r3)

macOS 13+ uses `SMAppService.mainApp` (`LaunchOnLogin.swift`); pre-13 uses the
embedded launcher via `SMLoginItemSetEnabled`. `SMAppService.mainApp` only
operates on the **executing** app’s identity, so unregister must run under the
**old** bundle ID. Existing installs do **not** yet understand `--unregister-login`
(today the only CLI hook is `--divvy2-spike`).

**`--unregister-login` contract** (handled at the **very start** of
`applicationDidFinishLaunching`, before `IdentityMigration`, `Defaults.*`,
`checkLaunchOnLogin`, UI, or AX):

1. On macOS 13+: `try SMAppService.mainApp.unregister()`. Treat already-unregistered /
   not-found as success. Any other throw → non-zero exit.
2. Always also call
   `SMLoginItemSetEnabled("com.perg593.divvy2.RectangleLauncher" as CFString, false)`
   using an **immutable legacy constant** `legacyLauncherAppId` (not
   `AppDelegate.launcherAppId`, which §A renames to `com.perg593.chiva.launcher` and
   which a `PRODUCT_BUNDLE_IDENTIFIER` xcodebuild override does **not** rewrite in
   compiled Swift). Require the BOOL success flag **or** treat “already disabled” as OK.
3. `exit(0)` only when both steps succeed (or are already clear); otherwise `exit(1)`.
4. Do not run identity migration or register login on this path.

**Transitional old-ID build** (concrete target-scoped overrides — do not rely on a
bare global `PRODUCT_BUNDLE_IDENTIFIER` alone):

```bash
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle -configuration Release \
  -derivedDataPath /tmp/chiva-cutover-dd \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  build \
  PRODUCT_BUNDLE_IDENTIFIER=com.perg593.divvy2
# Then rewrite embedded LoginItem + helper Info.plist IDs before re-sign:
#   Chiva.app Info.plist CFBundleIdentifier = com.perg593.divvy2
#   Contents/Library/LoginItems/*.app Info.plist = com.perg593.divvy2.RectangleLauncher
# Re-sign nested code + app with $IDENTITY (same deepest-first flow as build-install).
```

Install that bundle to `~/Applications/Divvy2/Chiva.app` (verified replace), then:

```bash
"$HOME/Applications/Divvy2/Chiva.app/Contents/MacOS/Chiva" --unregister-login
```

Require exit 0. If the old path cannot be built/run, print manual fallback
(System Settings → Login Items → remove Chiva/Divvy2) and continue only after the
user confirms, or abort cutover cleanup of login but still allow `/Applications`
install.

Then proceed to the **real** Chiva-identity build → verified replace into
`/Applications/Chiva.app` (§C).

After new install: if migrated prefs have `launchOnLogin=true`, the new app’s
existing launch path **re-registers `SMAppService.mainApp` for `com.perg593.chiva`**
— intended.

Remove known old apps only:
- `rm -rf ~/Applications/Divvy2/Chiva.app`
- `rm -rf ~/Applications/Divvy2/Divvy2SpikeHelper.app`
- `rmdir ~/Applications/Divvy2` only if empty

Do **not** use `sfltool resetbtm`.

Reminders: grant Accessibility for `/Applications/Chiva.app`; remove stale AX entry
for the old Divvy2 path if listed.

### F. Light docs

Update `CLAUDE.md` product name / bundle ID / install path. Do not rewrite upstream
Rectangle README wholesale.

## Verification

- `/Applications/Chiva.app` exists; Info.plist shows Chiva + `com.perg593.chiva` + `chiva`
- Installed app passes `codesign --verify --deep --strict` and prints expected Authority
- Embedded LoginItem launcher plist ID is `com.perg593.chiva.launcher`
- Menus / auth sheet / settings titles say Chiva (shipped-resource scan across **all**
  `Main.xcstrings` locales + storyboards + Swift UI strings; whitelist only
  Rectangle/Spectacle preset labels and internal symbols)
- Prefs migration tests pass; second launch does not re-merge destructively
- Hotkeys still snap; custom layouts present post-migration
- Old `~/Applications/Divvy2` apps gone when empty dir removed
- Project build + tests still pass

## Out of scope

- Renaming the git repo folder `divvy-2`
- Renaming `Rectangle.xcodeproj` / Swift module
- App Store / notarized Developer ID distribution
- Touching `/Applications/Divvy.app` (original Mizage Divvy)
- Global `sfltool resetbtm`

## Gate

Adversarial Codex review (`codex exec -s read-only`) before implementation. Target:
zero BLOCKER/MAJOR (GREEN).
