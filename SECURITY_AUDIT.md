# Rectangle — Security Audit

**Scope:** Source-level security review of the Rectangle repository
(`rxhanson/Rectangle`) at the commit checked out under this branch.
**Auditor:** Jakub Anderwald, May 2026.
**Methodology:** static review of every Swift file, all `.plist` and
`.entitlements` files, the Xcode project, CI workflow, and dependency
references. Search patterns enumerated common risk indicators
(URL/IPC/AppleScript/Process spawn, telemetry/analytics SDKs,
network APIs, unsafe Swift, secrets, ATS overrides, etc.).

This document records every finding plus, for High/Medium severity items,
the actual code change that was applied in this same branch.

---

## TL;DR — What this app sends off your machine

Rectangle is a window manager. By design it stays local. The full-source
sweep confirmed the following:

| Channel | Destination | Trigger | What's sent | Notes |
|---|---|---|---|---|
| Sparkle update check | `https://rectangleapp.com/downloads/updates.xml` | App launch (if "Automatically check for updates" is on) + manual "Check for Updates…" + every `SUScheduledCheckInterval` (172800s / 2 days) | HTTPS GET with default Sparkle User-Agent and `If-Modified-Since`. **No system profile.** | EdDSA-signed appcast (`SUPublicEDKey` in `Info.plist`). `SUSendProfileInfo` / `SUEnableSystemProfiling` are **not set**, so Sparkle's default (no profile) applies. Declared in `Rectangle/InternetAccessPolicy.plist`. |
| Sparkle update download | URL specified by the signed appcast | When user accepts an update | HTTPS GET of the new DMG | Signature is verified before install. |
| `DistributedNotificationCenter` "killLauncher" | **Local IPC only** (mach port broadcast on this machine) | Main app launch tells the legacy launcher helper to exit | Notification name only | Not network traffic. |

**No telemetry, no crash reporting, no analytics, no third-party data
sharing.** Searched the entire tree for `URLSession`, `URLRequest`,
`dataTask`, `CFNetwork`, `NWConnection`, `Socket`, `sendto`, plus every
common SDK name (Sentry, Crashlytics, Firebase, Mixpanel, Amplitude,
Bugsnag, AppCenter, PostHog, generic `Analytics`/`Telemetry`). Zero hits
in app code.

**No ATS bypass** (`NSAppTransportSecurity` not set). **No network
entitlements** anywhere (the app is intentionally un-sandboxed because the
Accessibility API requires it; the bundled launcher *is* sandboxed). No
XPC services, no Mach service exports, no AppleScript bridge enabled
(`LSAppleScriptEnabled` absent). No `Process`, `NSAppleScript`, shell
invocation, or dynamic library loading.

The user's wallpaper, window positions, shortcuts, ignored-app list,
exported config files, and accessibility-API data **never leave the
machine**.

> One caveat: third-party dependencies (`MASShortcut`, `Sparkle`) are
> source-imported via SPM. Sparkle is widely audited and only fetches the
> update feed. `MASShortcut` has no documented network code, but until
> Finding #1 (below) was fixed in this branch, every Rectangle build
> pulled the latest tip of its `master` branch — meaning a future
> upstream change could in principle introduce egress without our
> review. The pin-to-commit fix in this PR removes that exposure.

---

## Findings summary

| # | Severity | Area | Title | Status |
|---|----------|------|-------|--------|
| 1 | **High** | Supply chain | `MASShortcut` SPM dep pinned to moving `master` branch | **Fixed in this PR** |
| 2 | **Medium** | URL scheme | `execute-task` mutates state silently when triggered by external URL | **Fixed in this PR** |
| 3 | **Medium** | Config | `loadFromSupportDir()` silently auto-loads any JSON dropped in Application Support | **Fixed in this PR** |
| 4 | Low | Config | `String(contentsOf:)` reads config with no size cap (OOM via giant file) | **Fixed in this PR** (folded into #3 / `load`) |
| 5 | Low | URL scheme | No explicit scheme check / bundle-id shape validation | Documented, patch suggested below; not committed |
| 6 | Low | CI | `codesign --force --deep` in `build.yml` hides per-bundle signing errors | Documented, patch suggested below; not committed |
| 7 | Info | Sparkle | Version range `upToNextMajorVersion(2.0.0)` | OK — EdDSA-signed appcast makes this safe |
| 8 | Info | Telemetry | None present | Confirmed by audit |
| 9 | Info | Logger | Untrusted strings echoed into `LogViewer` `NSTextView` | OK — text view is `isEditable=false` and plain-text |

---

## Detailed findings

### 1. [High] `MASShortcut` SPM dependency pinned to moving `master` branch

**Location:** `Rectangle.xcodeproj/project.pbxproj`, `XCRemoteSwiftPackageReference "MASShortcut"`.

**Before:**
```
requirement = {
    branch = master;
    kind   = branch;
};
```

**Risk.** SPM with `kind = branch` resolves the *latest commit* of that
branch on every package resolution. There is no review gate between an
upstream `master` push (whether by the maintainer, a co-maintainer, a
compromised token, or a malicious force-push) and a Rectangle build that
links the new code. Because Rectangle ships outside the App Store and is
*not* sandboxed (it has Accessibility access by design), a malicious
`MASShortcut` build inherits the host's full user-level permissions.

**Fix applied.** Pin to the current `master` HEAD by revision SHA:

```
requirement = {
    kind     = revision;
    revision = 2f9fbb3f959b7a683c6faaf9638d22afad37a235;
};
```

(SHA was resolved via `gh api repos/rxhanson/MASShortcut/commits/master`
at audit time: 2025-09-28 "Fixes sizing of the button cell that shifted
in macOS 26".)

**Follow-up recommendation for upstream maintainer:** tag MASShortcut
releases (e.g. `2.4.1`) and switch Rectangle to `upToNextMinorVersion`
or `upToNextMajorVersion`, which is the same threat model as Sparkle.

---

### 2. [Medium] `rectangle://execute-task` mutates state silently from any URL source

**Location:** `Rectangle/AppDelegate.swift`, `application(_:open:)`.

**Risk.** Rectangle registers the `rectangle://` URL scheme. Any web
page can navigate to `rectangle://execute-task?name=ignore-app&app-bundle-id=com.apple.Safari`
and macOS will hand the URL straight to Rectangle, which (in the
original code) called `applicationToggle.disableApp(...)` with no user
prompt. Outcomes:

- A site can silently *disable* Rectangle shortcuts for a chosen app
  (e.g. the browser) — a primitive useful as one link in a multi-step
  social-engineering or accessibility-prompt-fatigue attack.
- A site can *enable* Rectangle shortcuts for an app the user
  deliberately ignored (e.g. re-enabling shortcuts that conflict with a
  game / IDE while the user is focused there).

Note: the unrelated `execute-action` host is intentionally unchanged.
Those actions are reversible window-movement operations and the
documented use case (Stream Deck, Shortcuts.app, automation) requires
them to be silent.

**Fix applied.** Require an `NSAlert` confirmation before `execute-task`
mutates state, unless Rectangle itself is the frontmost app (in which
case the request almost certainly came from Rectangle's own UI / a user
shortcut). Bundle-id is surfaced in the alert so the user can see what
they're approving.

```swift
func confirmExecuteTask(action: String, bundleId: String) -> Bool {
    if NSWorkspace.shared.frontmostApplication == NSRunningApplication.current {
        return true
    }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Allow Rectangle URL action?".localized
    alert.informativeText = String(format: "An external source asked Rectangle to perform \"%@\" on app bundle id \"%@\". Allow?".localized, action, bundleId)
    alert.addButton(withTitle: "Allow".localized)
    alert.addButton(withTitle: "Cancel".localized)
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn
}
```

---

### 3. [Medium] `Config.loadFromSupportDir()` silently auto-loads any JSON dropped in Application Support

**Location:** `Rectangle/PrefsWindow/Config.swift`.

**Risk.** On every launch Rectangle looks for
`~/Library/Application Support/Rectangle/RectangleConfig.json` and, if
present, *silently* applies it (overwriting shortcuts and the entire
`Defaults` set), then moves the file aside. Any process running as the
user can drop a file at that path — a downloaded ZIP, an installer, a
"helper" script, a pre-existing malicious LaunchAgent — and have its
contents persisted into Rectangle on next launch with no user
indication.

Combined with finding #2 this is a way to redefine the user's window
shortcuts to point at unexpected actions without ever surfacing UI.

The original code also did `String(contentsOf:)` with no size limit
(Finding #4) and followed symlinks transparently.

**Fix applied.** Three changes in this branch:

1. **Confirmation prompt.** Show an `AlertUtil.twoButtonAlert` listing
   the file path and asking the user to "Apply" or "Discard". On
   discard, the file is removed (consistent with the prior post-load
   behavior).
2. **Reject symlinks and world-writable files.** Both indicate
   tampering. The file is removed and a warning alert is shown.
3. **1 MiB size cap in `load(fileUrl:)`.** Real exported configs are
   tens of KB; anything materially larger is refused without reading
   it into memory (folds in Finding #4).

The legitimate "drop a config and have it imported" workflow still
works — it just requires one click of confirmation.

---

### 4. [Low] `String(contentsOf:)` in `Config.load` has no size limit

Folded into Finding #3's fix: the size check guards `load(fileUrl:)`
itself, so the protection applies to both the auto-load path and the
explicit `importConfig` button.

---

### 5. [Low] URL handler does not validate scheme or `app-bundle-id` shape

**Location:** `Rectangle/AppDelegate.swift`, `application(_:open:)`.

The handler does not verify `components.scheme == "rectangle"`. In
practice macOS only dispatches the registered scheme to this method, so
this is defense-in-depth, not a live bug. Similarly, `app-bundle-id` is
passed straight into `UserDefaults` ops without a reverse-DNS shape
check, so a malicious URL can pollute the `disabledApps` set with
non-bundle-id strings (these are inert — they never match a real
frontmost app — but they sit in the user's defaults).

**Suggested patch (not committed — low impact, separate change):**

```swift
guard url.scheme?.lowercased() == "rectangle" else { continue }

// inside isValidParameter:
let bundleIdPattern = #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#
let isValid = bundleId.map { $0.range(of: bundleIdPattern, options: .regularExpression) != nil } ?? false
```

---

### 6. [Low] `.github/workflows/build.yml` uses `codesign --force --deep`

**Location:** `.github/workflows/build.yml`, the "Resign App" step.

Apple has deprecated `--deep`. It walks every nested bundle and
re-signs them with the same identity, which can mask signing errors and
hide unexpected nested binaries. Since `xcodebuild -exportArchive`
already signs the outer bundle correctly, the explicit re-sign step is
both unnecessary and lossy.

**Suggested patch (not committed — CI/build concern, not a runtime
vulnerability):** delete the "Resign App" step entirely. If a re-sign
truly is needed for the ad-hoc workflow, sign only the outer bundle
without `--deep`:

```yaml
- name: Resign App
  run: codesign --force -s "$CODE_SIGN_IDENTITY" "$BUILD_DIR/$APP_NAME"
```

(Tangential: `runs-on: macos-26` is not a current GitHub-hosted runner
label and will cause the workflow to fail to schedule. Unrelated to
security but worth fixing.)

---

### 7. [Info] Sparkle version constraint

`upToNextMajorVersion(2.0.0)` means every Rectangle build picks up the
latest 2.x release of Sparkle. Because Sparkle's appcast itself is
EdDSA-signed (`SUPublicEDKey` in `Info.plist`) and updates are
verified before install, this is the standard configuration. No change
recommended.

---

### 8. [Info] Telemetry / outbound data

Confirmed absent. See the TL;DR table at the top.

---

### 9. [Info] `Logger` echoes untrusted strings into an `NSTextView`

`Logger.log` is called with attacker-controllable strings (e.g. the
bundle-id from a `rectangle://` URL). The log window's `NSTextView` has
`isEditable=false` and renders plain text (`NSAttributedString` with
only a monospaced font attribute), so there is no script-injection
surface. The log buffer is in-memory only and is cleared when the
window closes.

No change recommended.

---

## Verification performed

- `plutil -lint Rectangle.xcodeproj/project.pbxproj` → `OK` after the
  pbxproj edit.
- Project brace count is balanced (450/450) post-edit.
- No `xcodebuild` archive build was attempted: this audit ran on a
  machine without Xcode command-line developer tools selected and
  without a Rectangle signing identity. Maintainer CI will run the
  full archive build on PR.

## Files changed in this PR

- `Rectangle.xcodeproj/project.pbxproj` — pin MASShortcut to revision.
- `Rectangle/AppDelegate.swift` — confirm prompt for `execute-task` URL
  actions.
- `Rectangle/PrefsWindow/Config.swift` — size cap, symlink/world-write
  rejection, and confirm prompt for `loadFromSupportDir`.
- `SECURITY_AUDIT.md` — this document.

## Not addressed in this PR (recommended follow-ups)

- Findings #5 and #6 (low severity).
- Tagging MASShortcut releases upstream and switching Rectangle to
  semantic version range pinning (mirrors how Sparkle is set up).
- A dedicated `SECURITY.md` with a reporting address (currently the
  README has no security disclosure channel).
