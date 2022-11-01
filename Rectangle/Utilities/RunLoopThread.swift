//
//  RunLoopThread.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class RunLoopThread: Thread {
    private let startSemaphore = DispatchSemaphore(value: 0)
    private let mode: RunLoop.Mode
    private(set) var runLoop: RunLoop?
    
    init(mode: RunLoop.Mode, qualityOfService: QualityOfService? = nil, start: Bool = false) {
        self.mode = mode
        super.init()
        if let qualityOfService = qualityOfService { self.qualityOfService = qualityOfService }
        if start { self.start() }
    }
    
    override func start() {
        super.start()
        startSemaphore.wait()
    }
    
    override func main() {
        runLoop = RunLoop.current
        startSemaphore.signal()
        while !isCancelled {
            if !runLoop!.run(mode: mode, before: .distantFuture) {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
}
