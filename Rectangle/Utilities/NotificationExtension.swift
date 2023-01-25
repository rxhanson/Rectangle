//
//  NotificationExtension.swift
//  Rectangle
//
//  Created by Ryan Hanson on 12/23/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Cocoa

extension Notification.Name {
  
    static let configImported = Notification.Name("configImported")
    static let windowSnapping = Notification.Name("windowSnapping")
    static let frontAppChanged = Notification.Name("frontAppChanged")
    static let allowAnyShortcut = Notification.Name("allowAnyShortcutToggle")
    static let changeDefaults = Notification.Name("changeDefaults")
    static let todoMenuToggled = Notification.Name("todoMenuToggled")
    static let appWillBecomeActive = Notification.Name("appWillBecomeActive")
    static let missionControlDragging = Notification.Name("missionControlDragging")
    static let menuBarIconHidden = Notification.Name("menuBarIconHidden")

    func post(
        center: NotificationCenter = NotificationCenter.default,
        object: Any? = nil,
        userInfo: [AnyHashable : Any]? = nil) {
        
        center.post(name: self, object: object, userInfo: userInfo)
    }
    
    @discardableResult
    func onPost(
        center: NotificationCenter = NotificationCenter.default,
        object: Any? = nil,
        queue: OperationQueue? = nil,
        using: @escaping (Notification) -> Void)
    -> NSObjectProtocol {
        
        return center.addObserver(
            forName: self,
            object: object,
            queue: queue,
            using: using)
    }

}

