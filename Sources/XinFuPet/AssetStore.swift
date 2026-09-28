import AppKit
import Foundation

final class AssetStore {
    static let shared = AssetStore()
    private var cache: [String: NSImage] = [:]

    struct CanonicalWalkAnchor {
        let canvasWidth: CGFloat
        let canvasHeight: CGFloat
        let nativeCanonicalBodyHeight: CGFloat
        let torsoRootX: CGFloat
        let footAnchorY: CGFloat
    }

    struct CanonicalActionAnchor {
        let canvasWidth: CGFloat
        let canvasHeight: CGFloat
        let nativeCanonicalBodyHeight: CGFloat
        let torsoRootX: CGFloat
        let footAnchorY: CGFloat
        let frameCount: Int
    }

    struct PixelAnchor {
        let x: CGFloat
        let y: CGFloat
    }

    private lazy var root: URL = {
        if let env = ProcessInfo.processInfo.environment["XINFU_RESOURCES"], !env.isEmpty { return URL(fileURLWithPath: env) }
        if let r = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: r.appendingPathComponent("Characters").path) { return r }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for c in [cwd.appendingPathComponent("Resources"), cwd.appendingPathComponent("app/source/Resources"), cwd.appendingPathComponent("../Resources")] {
            if FileManager.default.fileExists(atPath: c.appendingPathComponent("Characters").path) { return c }
        }
        return cwd
    }()

    private func load(_ relativePath: String) -> NSImage? {
        if let x = cache[relativePath] { return x }
        let u = root.appendingPathComponent(relativePath)
        guard let im = NSImage(contentsOf: u) else { return nil }
        cache[relativePath] = im
        return im
    }

    private lazy var canonicalWalkAnchors: [String: [String: CanonicalWalkAnchor]] = {
        let url = root.appendingPathComponent("Motion/CanonicalKeyframesV1/walk-anchors.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let canvas = json["canvas"] as? [String: Any],
              let width = canvas["width"] as? NSNumber,
              let height = canvas["height"] as? NSNumber,
              let actors = json["actors"] as? [String: [String: [String: Any]]] else { return [:] }
        var decoded: [String: [String: CanonicalWalkAnchor]] = [:]
        for (actor, directions) in actors {
            for (direction, values) in directions {
                guard let nativeHeight = values["nativeCanonicalBodyHeight"] as? NSNumber,
                      let rootX = values["torsoRootX"] as? NSNumber,
                      let footY = values["footAnchorY"] as? NSNumber else { continue }
                decoded[actor, default: [:]][direction] = CanonicalWalkAnchor(
                    canvasWidth: CGFloat(width.doubleValue),
                    canvasHeight: CGFloat(height.doubleValue),
                    nativeCanonicalBodyHeight: CGFloat(nativeHeight.doubleValue),
                    torsoRootX: CGFloat(rootX.doubleValue),
                    footAnchorY: CGFloat(footY.doubleValue))
            }
        }
        return decoded
    }()

    func canonicalWalkAnchor(actor: ActorID, direction: String) -> CanonicalWalkAnchor? {
        canonicalWalkAnchors[actor.rawValue.lowercased()]?[direction]
    }

    func canonicalWalkImage(actor: ActorID, direction: String, frame: Int) -> NSImage? {
        guard (0..<4).contains(frame) else { return nil }
        return load("Motion/CanonicalKeyframesV1/frames/\(actor.rawValue.lowercased())/\(direction)-\(frame).png")
    }

    private lazy var canonicalActionMetadata: (anchors: [String: [String: CanonicalActionAnchor]],
                                                pinch: [String: [String: PixelAnchor]]) = {
        let url = root.appendingPathComponent("Motion/CanonicalKeyframesV1/action-anchors.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let canvas = json["canvas"] as? [String: Any],
              let width = canvas["width"] as? NSNumber,
              let height = canvas["height"] as? NSNumber,
              let actors = json["actors"] as? [String: [String: [String: Any]]] else { return ([:], [:]) }
        var anchors: [String: [String: CanonicalActionAnchor]] = [:]
        for (actor, actions) in actors {
            for (action, values) in actions {
                guard let native = values["nativeCanonicalBodyHeight"] as? NSNumber,
                      let rootX = values["torsoRootX"] as? NSNumber,
                      let footY = values["footAnchorY"] as? NSNumber,
                      let files = values["files"] as? [String] else { continue }
                let actionWidth: CGFloat
                let actionHeight: CGFloat
                if let rawCanvas = values["canvas"] {
                    guard let actionCanvas = rawCanvas as? [String: Any],
                          let actionCanvasWidth = actionCanvas["width"] as? NSNumber,
                          let actionCanvasHeight = actionCanvas["height"] as? NSNumber,
                          actionCanvasWidth.doubleValue.isFinite, actionCanvasWidth.doubleValue > 0,
                          actionCanvasHeight.doubleValue.isFinite, actionCanvasHeight.doubleValue > 0 else { continue }
                    actionWidth = CGFloat(actionCanvasWidth.doubleValue)
                    actionHeight = CGFloat(actionCanvasHeight.doubleValue)
                } else {
                    actionWidth = CGFloat(width.doubleValue)
                    actionHeight = CGFloat(height.doubleValue)
                }
                anchors[actor, default: [:]][action] = CanonicalActionAnchor(
                    canvasWidth: actionWidth, canvasHeight: actionHeight,
                    nativeCanonicalBodyHeight: CGFloat(native.doubleValue),
                    torsoRootX: CGFloat(rootX.doubleValue), footAnchorY: CGFloat(footY.doubleValue),
                    frameCount: files.count)
            }
        }
        var pinch: [String: [String: PixelAnchor]] = [:]
        if let values = json["gesturePinchAnchors"] as? [String: [String: [String: Any]]] {
            for (key, points) in values {
                for (frame, point) in points {
                    guard let x = point["x"] as? NSNumber, let y = point["y"] as? NSNumber else { continue }
                    pinch[key, default: [:]][frame] = PixelAnchor(x: CGFloat(x.doubleValue), y: CGFloat(y.doubleValue))
                }
            }
        }
        return (anchors, pinch)
    }()

    func canonicalActionAnchor(actor: ActorID, action: String) -> CanonicalActionAnchor? {
        canonicalActionMetadata.anchors[actor.rawValue.lowercased()]?[action]
    }

    func canonicalActionImage(actor: ActorID, action: String, frame: Int) -> NSImage? {
        guard let anchor = canonicalActionAnchor(actor: actor, action: action),
              (0..<anchor.frameCount).contains(frame) else { return nil }
        return load("Motion/CanonicalKeyframesV1/frames/\(actor.rawValue.lowercased())/\(action)-\(frame).png")
    }

    func gesturePinchAnchor(actor: ActorID, action: String, frame: Int) -> PixelAnchor? {
        canonicalActionMetadata.pinch["\(actor.rawValue.lowercased()).\(action)"]?["frame\(frame)"]
    }

    func flowerImage() -> NSImage? { load("Motion/Props/flower.png") }

    // Only these independently drawn poses are exposed to the player.
    func productionImage(actor: ActorID, pose: String) -> NSImage? {
        let allowed: [ActorID: Set<String>] = [
            .frieren: ["neutral", "read", "bookajar", "bookhalf", "sitread", "sitstart", "cast", "staffraise", "inspect", "adjust", "walk", "stretch", "doze", "wake", "staff", "pack", "notice", "map"],
            .himmel: ["neutral", "greet", "greetquarter", "greetstart", "sit", "sitstart", "flower", "cape", "walk", "point", "kneel", "hero", "look", "swordcheck", "rest", "swordpractice", "read"]
        ]
        guard allowed[actor]?.contains(pose) == true else { return nil }
        return load("Characters/\(actor.rawValue)/production_\(pose).png")
    }

}
