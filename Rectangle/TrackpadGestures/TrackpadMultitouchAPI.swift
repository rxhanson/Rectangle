import CoreFoundation
import Foundation
import IOKit

// Load only when enabled: unavailable private APIs must not prevent Rectangle launching.
final class TrackpadMultitouchAPI {
    typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    typealias Register = @convention(c) (MTDeviceRef?, MTContactCallbackFunction?) -> Void
    typealias Start = @convention(c) (MTDeviceRef?, Int32) -> Void
    typealias Stop = @convention(c) (MTDeviceRef?) -> Void
    static let shared = TrackpadMultitouchAPI()
    private let handle: UnsafeMutableRawPointer
    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let create = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.createList = unsafeBitCast(create, to: CreateList.self)
        self.register = unsafeBitCast(register, to: Register.self)
        self.unregister = unsafeBitCast(unregister, to: Register.self)
        self.start = unsafeBitCast(start, to: Start.self)
        self.stop = unsafeBitCast(stop, to: Stop.self)
    }
}
