/// UnregisterLogin.swift
///
/// CLI path for `--unregister-login`: clear SMAppService + legacy login item, then exit.
/// Invoked during cutover under the transitional old bundle identity.

import Foundation
import ServiceManagement
import os.log

enum UnregisterLogin {

    static func runAndExit() -> Never {
        var ok = true

        if #available(macOS 13, *) {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                let ns = error as NSError
                // Already absent / not registered — treat as success.
                if ns.domain == "SMAppServiceErrorDomain", ns.code == 1 {
                    // SMErrorDomain kSMErrorJobNotFound variants vary; also accept enabled!=true.
                } else if SMAppService.mainApp.status != .enabled {
                    // Not enabled → already clear enough.
                } else {
                    os_log("unregister-login: SMAppService.unregister failed: %{public}@", error.localizedDescription)
                    ok = false
                }
            }
        }

        let legacyCleared = SMLoginItemSetEnabled(AppDelegate.legacyLauncherAppId as CFString, false)
        if !legacyCleared {
            // May already be disabled; try reading is not available — log and continue only if SMAppService path succeeded.
            os_log("unregister-login: SMLoginItemSetEnabled(legacy) returned false")
            // Not fatal on macOS 13+ where legacy path is unused; fatal on older OSes.
            if #available(macOS 13, *) {
                // keep ok as-is
            } else {
                ok = false
            }
        }

        exit(ok ? 0 : 1)
    }
}
