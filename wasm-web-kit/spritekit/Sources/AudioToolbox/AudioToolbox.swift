// AudioToolbox shim — FidgetX uses AudioServicesPlayAlertSound for haptic
// feedback (vibration on iPhone). Browsers have no equivalent on desktop, and
// on mobile the Vibration API requires a user gesture, so this is a no-op.
// Games keep calling sites intact.

public typealias SystemSoundID = UInt32

public let kSystemSoundID_Vibrate: SystemSoundID = 0x00000FFF

public func AudioServicesPlayAlertSound(_ id: SystemSoundID) {}
public func AudioServicesPlaySystemSound(_ id: SystemSoundID) {}
public func AudioServicesPlaySystemSoundWithCompletion(_ id: SystemSoundID, _ block: @escaping () -> Void) { block() }
public func AudioServicesDisposeSystemSoundID(_ id: SystemSoundID) {}
public func AudioServicesCreateSystemSoundID(_ url: AnyObject, _ outID: UnsafeMutablePointer<SystemSoundID>) -> Int32 {
    outID.pointee = 0
    return 0
}
