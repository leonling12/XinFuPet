import AppKit
import Foundation

enum ActorID: String, Codable, CaseIterable { case frieren = "Frieren", himmel = "Himmel" }

enum PetState: String { case idle, soloAction, duoEvent, walking, resting, userInteraction, dragging, paused }

struct PoseKeyframe: Hashable {
    let t: Double
    let pose: String
    let dx: CGFloat
    let dy: CGFloat
    let scale: CGFloat
    let rotation: CGFloat
    let effectOpacity: Float

    init(_ t: Double, _ pose: String, dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1, rotation: CGFloat = 0, effectOpacity: Float = 0) {
        self.t = t; self.pose = pose; self.dx = dx; self.dy = dy; self.scale = scale; self.rotation = rotation; self.effectOpacity = effectOpacity
    }
}

struct ActorTrack: Hashable {
    let actor: ActorID
    let startDelay: Double
    let frames: [PoseKeyframe]
}

struct ActionPlan: Hashable {
    let id: String
    let nameZH: String
    let duration: Double
    let trigger: String
    let cooldown: Double
    let tracks: [ActorTrack]
    let category: String
    var keyPoseCount: Int { tracks.map { $0.frames.count }.reduce(0,+) }
}
