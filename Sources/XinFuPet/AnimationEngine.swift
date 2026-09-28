import AppKit
import Foundation

final class AnimationEngine {
    weak var scene: PetSceneView?
    private var generation = UUID()
    private(set) var activeID: String?
    private var completion: (() -> Void)?
    private var activePlan: ActionPlan?
    private var clock: DispatchSourceTimer?
    private var elapsed: Double = 0
    private var lastTick: TimeInterval = 0
    private var activeActors: Set<ActorID> = []
    private var startingPoses: [ActorID: String] = [:]
    private var pairWalkDirection = "left"
    private var manualDragSettleRemaining: Double?

    var isActionClockActive: Bool { activePlan != nil || manualDragSettleRemaining != nil }

    init(scene: PetSceneView) { self.scene = scene }

    func cancelPlaybackPreservingPoses() {
        generation = UUID()
        clock?.cancel(); clock = nil
        activePlan = nil
        manualDragSettleRemaining = nil
        activeActors.removeAll()
        activeID = nil
        completion = nil
        scene?.setWalkDepth(direction: nil)
    }

    func cancelAndReturn() {
        cancelPlaybackPreservingPoses()
        scene?.setFlowerHidden(true)
        scene?.frieren.reset(duration: 0)
        scene?.himmel.reset(duration: 0)
    }

    func play(_ plan: ActionPlan, userInitiated: Bool = false, completion: (() -> Void)? = nil) {
        guard let scene else { return }
        cancelPlaybackPreservingPoses()
        generation = UUID(); let g = generation
        activeID = plan.id
        activePlan = plan
        activeActors = Set(plan.tracks.map(\.actor))
        startingPoses = Dictionary(uniqueKeysWithValues: plan.tracks.map {
            ($0.actor, actorView($0.actor, in: scene).currentPose)
        })
        self.completion = completion
        elapsed = 0
        lastTick = ProcessInfo.processInfo.systemUptime
        if plan.id != "H03" && plan.id != "D06" { scene.setFlowerHidden(true) }
        if plan.id == "H03" || plan.id == "D06" { scene.setFlowerHidden(true) }
        if plan.id == "D04" {
            pairWalkDirection = scene.lastHorizontalWalkDirection
            scene.setWalkDepth(direction: pairWalkDirection)
        } else if plan.id == "F12" {
            scene.setWalkDepth(direction: "right")
        } else if plan.id == "H12" {
            scene.setWalkDepth(direction: "left")
        }
        startClock(scene: scene, generation: g)
    }

    private func startClock(scene: PetSceneView, generation g: UUID) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self, weak scene] in
            guard let self, let scene, self.generation == g else { return }
            self.tick(scene: scene, generation: g)
        }
        clock = timer
        timer.resume()
    }

    private func tick(scene: PetSceneView, generation g: UUID) {
        guard generation == g else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0, min(0.1, now - lastTick))
        lastTick = now
        let speed = max(0.5, PetSettings.shared.motionSpeed)

        if var remaining = manualDragSettleRemaining {
            if !PetSettings.shared.paused { remaining -= delta * speed }
            manualDragSettleRemaining = remaining
            guard remaining <= 0 else { return }
            clock?.cancel(); clock = nil
            manualDragSettleRemaining = nil
            for actor in activeActors {
                let view = actorView(actor, in: scene)
                view.setPose("neutral", transition: 0)
                view.setWalkTransform(dx: 0, dy: 0)
            }
            activeActors.removeAll()
            activeID = nil
            scene.setWalkDepth(direction: nil)
            scene.coordinator?.endManualWalkDrag()
            return
        }

        guard let plan = activePlan else { return }
        if !PetSettings.shared.paused { elapsed += delta * speed }
        let sharedD06Progress = min(1, max(0, elapsed / max(0.001, plan.duration)))
        for track in plan.tracks {
            let localSeconds = elapsed - track.startDelay
            guard localSeconds >= 0 else { continue }
            let normalized = plan.id == "D06" ? sharedD06Progress
                : min(1, max(0, localSeconds / max(0.001, plan.duration)))
            updateTrack(track, plan: plan, normalized: normalized, scene: scene)
        }
        if plan.id == "D06" { updateD06Flower(sharedD06Progress, scene: scene) }

        let finishAt = plan.tracks.map { $0.startDelay + plan.duration }.max() ?? plan.duration
        guard elapsed >= finishAt else { return }
        finish(plan, scene: scene)
    }

    private func updateTrack(_ track: ActorTrack, plan: ActionPlan, normalized: Double,
                            scene: PetSceneView) {
        let view = actorView(track.actor, in: scene)
        if updateCanonicalAction(track.actor, plan: plan, normalized: normalized, view: view, scene: scene) {
            return
        }

        // D03 is a shared reading pose: Frieren holds the one book and
        // Himmel uses the authored down-left look (frame 3), never his notes.
        if plan.id == "D03" && track.actor == .himmel {
            if AssetStore.shared.canonicalActionAnchor(actor: .himmel, action: "look") != nil,
               normalized >= 0.30, normalized < 0.90 {
                view.setCanonicalAction("look", frame: 3)
            } else {
                view.setPose("neutral", transition: 0)
            }
            view.setWalkTransform(dx: 0, dy: 0)
            return
        }

        let currentIndex = track.frames.lastIndex(where: { $0.t <= normalized }) ?? 0
        let current = track.frames[currentIndex]
        let next = currentIndex + 1 < track.frames.count ? track.frames[currentIndex + 1] : nil
        let span = max(0.0001, (next?.t ?? current.t) - current.t)
        let mix = min(1, max(0, (normalized - current.t) / span))
        func blend(_ from: CGFloat, _ to: CGFloat?) -> CGFloat { from + ((to ?? from) - from) * mix }

        if plan.id == "F12" || plan.id == "H12" || plan.id == "D04" {
            guard current.pose == "walk" else {
                view.setPose(current.pose, transition: 0)
                let dx = plan.id == "D04" ? 0 : blend(current.dx, next?.dx)
                let dy = plan.id == "D04" ? 0 : blend(current.dy, next?.dy)
                let scale = plan.id == "D04" ? 1 : blend(current.scale, next?.scale)
                let rotation = plan.id == "D04" ? 0 : blend(current.rotation, next?.rotation)
                view.setWalkTransform(dx: dx, dy: dy, scale: scale, rotation: rotation)
                return
            }
            let direction = plan.id == "D04" ? pairWalkDirection : (track.actor == .frieren ? "right" : "left")
            let phase = elapsed / 0.9
            view.setCanonicalWalk(direction: direction, phase: phase,
                                  phaseOffset: plan.id == "D04" && track.actor == .himmel ? 0.25 : 0)
            let dx = plan.id == "D04" ? 0 : blend(current.dx, next?.dx)
            let dy = plan.id == "D04" ? 0 : blend(current.dy, next?.dy)
            let scale = plan.id == "D04" ? 1 : blend(current.scale, next?.scale)
            let rotation = plan.id == "D04" ? 0 : blend(current.rotation, next?.rotation)
            view.setWalkTransform(dx: dx, dy: dy, scale: scale, rotation: rotation)
            return
        }

        view.setPose(current.pose, transition: 0)
        view.setWalkTransform(dx: blend(current.dx, next?.dx), dy: blend(current.dy, next?.dy),
                              scale: blend(current.scale, next?.scale),
                              rotation: blend(current.rotation, next?.rotation))
    }

    @discardableResult
    private func updateCanonicalAction(_ actor: ActorID, plan: ActionPlan, normalized t: Double,
                                       view: ActorView, scene: PetSceneView) -> Bool {
        if let family = familyAction(actor: actor, planID: plan.id),
           AssetStore.shared.canonicalActionAnchor(actor: actor, action: family) != nil {
            if let frame = familyFrame(family, actor: actor, progress: t) {
                view.setCanonicalAction(family, frame: frame)
            } else {
                view.setPose("neutral", transition: 0)
            }
            view.setWalkTransform(dx: 0, dy: 0)
            return true
        }
        switch plan.id {
        case "H03":
            guard actor == .himmel else { return true }
            if t < 0.81 {
                let sample = offerSample(t)
                view.setCanonicalAction("offer", frame: sample)
                view.setWalkTransform(dx: -7 * smoothstep(min(1, t / 0.18)), dy: 0)
                if sample == 3 || sample == 4,
                   let pinch = AssetStore.shared.gesturePinchAnchor(actor: .himmel, action: "offer", frame: sample) {
                    _ = scene.setFlowerAtGestureHand(actor: .himmel, action: "offer", frame: sample, anchor: pinch)
                } else {
                    scene.setFlowerHidden(true)
                }
            } else {
                view.setPose("neutral", transition: 0)
                let returnShift = 1 - smoothstep(min(1, (t - 0.81) / 0.19))
                view.setWalkTransform(dx: -7 * returnShift, dy: 0)
                scene.setFlowerHidden(true)
            }
            return true

        case "D06":
            if actor == .himmel {
                if t < 0.82 {
                    let sample = duoOfferSample(t)
                    view.setCanonicalAction("offer", frame: sample)
                    let retreat = smoothstep(min(1, max(0, (t - 0.76) / 0.16)))
                    view.setWalkTransform(dx: -7 * smoothstep(min(1, t / 0.18)) * (1 - retreat), dy: 0)
                } else {
                    view.setPose("neutral", transition: 0)
                    view.setWalkTransform(dx: 0, dy: 0)
                }
            } else {
                let sample = duoReceiveSample(t)
                view.setCanonicalAction("receive", frame: sample)
            }
            return true

        case "F08", "H02", "D08":
            let (idx, neutralAtEnd) = seatedSequence(actor: actor, progress: t)
            if neutralAtEnd { view.setPose("neutral", transition: 0) }
            else { view.setCanonicalAction("sit", frame: idx) }
            view.setWalkTransform(dx: 0, dy: 0)
            return true

        case "F09":
            if startingPoses[.frieren] == "canonical-sit" {
                if t < 0.26 { view.setCanonicalAction("sit", frame: 2) }
                else if t < 0.37 { view.setCanonicalAction("doze", frame: 0) }
                else if t < 0.49 { view.setCanonicalAction("doze", frame: 1) }
                else if t < 0.68 { view.setCanonicalAction("doze", frame: 2) }
                else if t < 0.82 { view.setCanonicalAction("doze", frame: 3) }
                else { view.setCanonicalAction("sit", frame: 2) }
            } else {
                if t < 0.12 { view.setCanonicalAction("sit", frame: 0) }
                else if t < 0.22 { view.setCanonicalAction("sit", frame: 1) }
                else if t < 0.32 { view.setCanonicalAction("sit", frame: 2) }
                else if t < 0.43 { view.setCanonicalAction("doze", frame: 0) }
                else if t < 0.54 { view.setCanonicalAction("doze", frame: 1) }
                else if t < 0.72 { view.setCanonicalAction("doze", frame: 2) }
                else if t < 0.86 { view.setCanonicalAction("doze", frame: 3) }
                else { view.setCanonicalAction("sit", frame: 2) }
            }
            view.setWalkTransform(dx: 0, dy: 0)
            return true

        case "F10":
            if startingPoses[.frieren] == "neutral" {
                if t < 0.10 { view.setCanonicalAction("sit", frame: 0) }
                else if t < 0.18 { view.setCanonicalAction("sit", frame: 1) }
                else if t < 0.26 { view.setCanonicalAction("sit", frame: 2) }
                else if t < 0.36 { view.setCanonicalAction("doze", frame: 0) }
                else if t < 0.46 { view.setCanonicalAction("doze", frame: 1) }
                else if t < 0.56 { view.setCanonicalAction("doze", frame: 2) }
                else if t < 0.66 { view.setCanonicalAction("doze", frame: 3) }
                else if t < 0.76 { view.setCanonicalAction("sit", frame: 2) }
                else if t < 0.84 { view.setCanonicalAction("sit", frame: 1) }
                else if t < 0.93 { view.setCanonicalAction("sit", frame: 0) }
                else { view.setPose("neutral", transition: 0) }
            } else {
                if t < 0.18 { view.setCanonicalAction("doze", frame: 0) }
                else if t < 0.36 { view.setCanonicalAction("doze", frame: 1) }
                else if t < 0.56 { view.setCanonicalAction("doze", frame: 2) }
                else if t < 0.68 { view.setCanonicalAction("doze", frame: 3) }
                else if t < 0.78 { view.setCanonicalAction("sit", frame: 2) }
                else if t < 0.86 { view.setCanonicalAction("sit", frame: 1) }
                else if t < 0.95 { view.setCanonicalAction("sit", frame: 0) }
                else { view.setPose("neutral", transition: 0) }
            }
            view.setWalkTransform(dx: 0, dy: 0)
            return true

        case "F13":
            let (idx, neutralAtEnd) = transitionSequence(t, action: "stretch")
            if neutralAtEnd { view.setPose("neutral", transition: 0) }
            else { view.setCanonicalAction("stretch", frame: idx) }
            view.setWalkTransform(dx: 0, dy: 0)
            return true

        case "H10":
            let (idx, neutralAtEnd) = transitionSequence(t, action: "kneel")
            if neutralAtEnd { view.setPose("neutral", transition: 0) }
            else { view.setCanonicalAction("kneel", frame: idx) }
            view.setWalkTransform(dx: 0, dy: 0)
            return true

        case "H05":
            if t < 0.18 { view.setCanonicalAction("swordcheck", frame: 0) }
            else if t < 0.28 { view.setCanonicalAction("swordcheck", frame: 1) }
            else if t < 0.38 { view.setCanonicalAction("practice", frame: 0) }
            else if t < 0.48 { view.setCanonicalAction("practice", frame: 1) }
            else if t < 0.60 { view.setCanonicalAction("practice", frame: 2) }
            else if t < 0.74 { view.setCanonicalAction("practice", frame: 3) }
            else if t < 0.90 { view.setCanonicalAction("practice", frame: 0) }
            else { view.setPose("neutral", transition: 0) }
            view.setWalkTransform(dx: 0, dy: 0)
            return true

        default:
            return false
        }
    }

    private func updateD06Flower(_ t: Double, scene: PetSceneView) {
        if t >= 0.30 && t < 0.43 {
            let frame = t < 0.40 ? 3 : 4
            guard let point = gestureContact(.himmel, action: "offer", renderedFrame: frame,
                                             anchorFrame: frame, scene: scene) else { return }
            scene.setFlowerAtContact(point)
            return
        }
        if t >= 0.43 && t < 0.60 {
            guard let from = gestureContact(.himmel, action: "offer", renderedFrame: 4,
                                            anchorFrame: 4, scene: scene),
                  let to = gestureContact(.frieren, action: "receive", renderedFrame: 4,
                                          anchorFrame: 4, scene: scene) else { return }
            scene.setFlowerAtContact(NSPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2))
            return
        }
        if t >= 0.60 {
            let frame = duoReceiveSample(t)
            guard let point = gestureContact(.frieren, action: "receive", renderedFrame: frame,
                                             anchorFrame: 5, scene: scene) else { return }
            scene.setFlowerAtContact(point)
            return
        }
        scene.setFlowerHidden(true)
    }

    private func gestureContact(_ actor: ActorID, action: String, renderedFrame: Int, anchorFrame: Int,
                                scene: PetSceneView) -> NSPoint? {
        guard let anchor = AssetStore.shared.gesturePinchAnchor(actor: actor, action: action, frame: anchorFrame) else { return nil }
        return scene.gestureHandPoint(actor: actor, action: action, frame: renderedFrame, anchor: anchor)
    }

    private func offerSample(_ t: Double) -> Int {
        let p = min(1, max(0, t / 0.81))
        if p < 0.12 { return 0 }
        if p < 0.24 { return 1 }
        if p < 0.36 { return 2 }
        if p < 0.48 { return 3 }
        if p < 0.74 { return 4 }
        if p < 0.82 { return 5 }
        if p < 0.91 { return 6 }
        return 7
    }

    private func duoOfferSample(_ t: Double) -> Int {
        if t < 0.10 { return 0 }
        if t < 0.20 { return 1 }
        if t < 0.30 { return 2 }
        if t < 0.40 { return 3 }
        if t < 0.60 { return 4 }
        if t < 0.68 { return 5 }
        if t < 0.75 { return 6 }
        return 7
    }

    private func duoReceiveSample(_ t: Double) -> Int {
        if t < 0.10 { return 0 }
        if t < 0.20 { return 1 }
        if t < 0.30 { return 2 }
        if t < 0.43 { return 3 }
        if t < 0.60 { return 4 }
        if t < 0.72 { return 5 }
        if t < 0.82 { return 6 }
        return 7
    }

    private func seatedSequence(actor: ActorID, progress t: Double) -> (Int, Bool) {
        if actor == .frieren {
            if t < 0.12 { return (0, false) }
            if t < 0.28 { return (1, false) }
            if t < 0.76 { return (2, false) }
            if t < 0.88 { return (1, false) }
            if t < 0.96 { return (0, false) }
            if t < 1 { return (0, false) }
            return (0, true)
        }
        if t < 0.12 { return (0, false) }
        if t < 0.28 { return (1, false) }
        if t < 0.43 { return (2, false) }
        if t < 0.76 { return (3, false) }
        if t < 0.88 { return (2, false) }
        if t < 0.96 { return (1, false) }
        if t < 1 { return (0, false) }
        return (0, true)
    }

    private func transitionSequence(_ t: Double, action: String) -> (Int, Bool) {
        let index: Int
        if t < 0.20 { index = 0 }
        else if t < 0.42 { index = 1 }
        else if t < 0.68 { index = 2 }
        else if t < 0.80 { index = 3 }
        else if t < 0.88 { index = 2 }
        else if t < 0.95 { index = 1 }
        else if t < 1 { index = 0 }
        else { return (0, true) }
        return (index, false)
    }

    private func smoothstep(_ t: Double) -> CGFloat {
        let x = min(1, max(0, t))
        return CGFloat(x * x * (3 - 2 * x))
    }

    private func actorView(_ actor: ActorID, in scene: PetSceneView) -> ActorView {
        actor == .frieren ? scene.frieren : scene.himmel
    }

    private func familyAction(actor: ActorID, planID: String) -> String? {
        if actor == .frieren {
            switch planID {
            case "F02", "D05": return "map"
            case "F04": return "inspect"
            case "F05": return "adjust"
            case "F06": return "pack"
            case "F11", "D01", "D02": return "notice"
            default: return nil
            }
        }
        if actor == .himmel {
            switch planID {
            case "H04": return "cape"
            case "H06": return "swordcheck"
            case "H07": return "hero"
            case "H08", "D01": return "look"
            case "H09", "D05": return "point"
            case "H11", "D07": return "rest"
            case "H13": return "read"
            default: return nil
            }
        }
        return nil
    }

    private func familyFrame(_ action: String, actor: ActorID, progress t: Double) -> Int? {
        let count = AssetStore.shared.canonicalActionAnchor(actor: actor, action: action)?.frameCount ?? 0
        guard count > 0, t >= 0.18, t < 0.95 else { return nil }
        // The pointing strip already authors its return in frame 3; play it
        // once in source order instead of reversing the gesture back outward.
        if action == "point" {
            if t < 0.25 { return 0 }
            if t < 0.34 { return min(1, count - 1) }
            if t < 0.72 { return min(2, count - 1) }
            return count - 1
        }
        // Play all authored entry poses, hold the final pose, then return
        // through the same source frames before restoring legacy neutral.
        if t < 0.25 { return 0 }
        if t < 0.32 { return min(1, count - 1) }
        if t < 0.40 { return min(2, count - 1) }
        if t < 0.72 { return count - 1 }
        if t < 0.80 { return max(0, count - 2) }
        if t < 0.87 { return min(1, count - 1) }
        return 0
    }

    private func finish(_ plan: ActionPlan, scene: PetSceneView) {
        clock?.cancel(); clock = nil
        activePlan = nil
        if plan.id == "D06" {
            scene.himmel.setPose("neutral", transition: 0)
            scene.himmel.setWalkTransform(dx: 0, dy: 0)
            scene.frieren.setCanonicalAction("receive", frame: 7)
            if let anchor = AssetStore.shared.gesturePinchAnchor(actor: .frieren, action: "receive", frame: 5) {
                _ = scene.setFlowerAtGestureHand(actor: .frieren, action: "receive", frame: 7, anchor: anchor)
            }
        } else if plan.id == "H03" {
            scene.himmel.setPose("neutral", transition: 0)
            scene.himmel.setWalkTransform(dx: 0, dy: 0)
            scene.setFlowerHidden(true)
        } else if ["F12", "H12", "D04"].contains(plan.id) {
            for actor in activeActors {
                let view = actorView(actor, in: scene)
                view.setPose("neutral", transition: 0)
                view.setWalkTransform(dx: 0, dy: 0)
            }
        }
        activeActors.removeAll()
        activeID = nil
        scene.setWalkDepth(direction: nil)
        startingPoses.removeAll()
        let done = completion
        completion = nil
        done?()
    }

    func settleManualWalkDrag(direction: String, phase: Double) {
        guard let scene else { return }
        cancelPlaybackPreservingPoses()
        generation = UUID()
        let g = generation
        activeID = "manualDragSettle"
        activeActors = [.frieren, .himmel]
        let wrapped = phase.truncatingRemainder(dividingBy: 1)
        let sample = (Int(floor(wrapped * 4)) % 4 + 4) % 4
        let closeSample = sample % 2 == 1 ? sample : (sample + 1) % 4
        let closePhase = Double(closeSample) / 4
        scene.frieren.setCanonicalWalk(direction: direction, phase: closePhase)
        scene.himmel.setCanonicalWalk(direction: direction, phase: closePhase, phaseOffset: 0.25)
        scene.frieren.setWalkTransform(dx: 0, dy: 0)
        scene.himmel.setWalkTransform(dx: 0, dy: 0)
        scene.setWalkDepth(direction: direction)
        manualDragSettleRemaining = 0.20
        lastTick = ProcessInfo.processInfo.systemUptime
        startClock(scene: scene, generation: g)
    }
}
