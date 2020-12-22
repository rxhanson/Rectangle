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

