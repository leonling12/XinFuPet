import AppKit
import Foundation

final class PetSettings {
    static let shared = PetSettings()
    private let d: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["XINFU_PREFS_SUITE"],
           let isolated = UserDefaults(suiteName: suite) { return isolated }
        return UserDefaults.standard
    }()

    var sizeScale: CGFloat {
        get { let v = d.double(forKey: "sizeScale"); return v == 0 ? 1.0 : CGFloat(v) }
        set { d.set(Double(max(newValue, 0.1)), forKey: "sizeScale") }
    }
    var pairSpacing: CGFloat {
        get { d.object(forKey: "pairSpacing") == nil ? 12 : CGFloat(d.double(forKey: "pairSpacing")) }
        set { d.set(Double(min(max(newValue, 0), 140)), forKey: "pairSpacing") }
    }

    var sceneOrigin: NSPoint? {
        get {
            guard d.object(forKey: "sceneOriginX") != nil,
                  d.object(forKey: "sceneOriginY") != nil else { return nil }
            return NSPoint(x: d.double(forKey: "sceneOriginX"), y: d.double(forKey: "sceneOriginY"))
        }
        set {
            if let origin = newValue {
                d.set(Double(origin.x), forKey: "sceneOriginX")
                d.set(Double(origin.y), forKey: "sceneOriginY")
            } else {
                d.removeObject(forKey: "sceneOriginX")
                d.removeObject(forKey: "sceneOriginY")
            }
        }
    }

    func restoreDefaults() {
        sizeScale = 1.0
        pairSpacing = 12
        motionSpeed = 1
        activityFrequency = 1
        lowMotion = false
    }
    var motionSpeed: Double {
        get { let v = d.double(forKey: "motionSpeed"); return v == 0 ? 1.0 : v }
        set { d.set(min(max(newValue, 0.5), 2.0), forKey: "motionSpeed") }
    }
    var activityFrequency: Double {
        get { let v = d.double(forKey: "activityFrequency"); return v == 0 ? 1.0 : v }
        set { d.set(min(max(newValue, 0.35), 2.0), forKey: "activityFrequency") }
    }
    var autonomousWalking: Bool {
        get { d.object(forKey: "autonomousWalking") == nil ? true : d.bool(forKey: "autonomousWalking") }
        set { d.set(newValue, forKey: "autonomousWalking") }
    }
    var alwaysOnTop: Bool {
        get { d.object(forKey: "alwaysOnTop") == nil ? true : d.bool(forKey: "alwaysOnTop") }
        set { d.set(newValue, forKey: "alwaysOnTop") }
    }
    var lowMotion: Bool {
        get { d.bool(forKey: "lowMotion") }
        set { d.set(newValue, forKey: "lowMotion") }
    }
    var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { d.set(newValue, forKey: "paused") }
    }
}
