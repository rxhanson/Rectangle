//
//  LaunchOnLogin.swift
//  Rectangle
//
//  Created by Ryan Hanson on 2/20/23.
//  Copyright © 2023 Ryan Hanson. All rights reserved.
//

import Foundation
import ServiceManagement
import os.log

@available(macOS 13.0, *)
public enum LaunchOnLogin {
    public static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }
                    
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                os_log("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            }
        }
    }
}
