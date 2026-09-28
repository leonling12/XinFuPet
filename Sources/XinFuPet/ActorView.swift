import AppKit
import QuartzCore

/// A complete transparent character image is displayed for every supported pose.
/// Walk frames are complete source illustrations on a fixed, shared canvas; no
/// limbs, masks, or frame-by-frame bounds fitting are used.
final class ActorView: NSView {
    let actor: ActorID
    private let fullBody = CALayer()
    private(set) var currentPose = "neutral"
    private var currentMask: NSBitmapImageRep?
    private var canonicalWalkDirection: String?
    private var canonicalWalkSample: Int?
    private var canonicalAction: String?
    private var canonicalActionSample: Int?
    private var canonicalActionRootOffsetX: CGFloat = 0
    private var customWholeBodyFrame = false
    var currentWalkDirection: String? { canonicalWalkDirection }
    var currentWalkSample: Int? { canonicalWalkSample }
    var currentCanonicalActionFrame: Int? { canonicalActionSample }

    init(actor: ActorID) {
        self.actor = actor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        fullBody.contentsGravity = .resizeAspect
        fullBody.magnificationFilter = .linear
        fullBody.minificationFilter = .trilinear
        let image = AssetStore.shared.productionImage(actor: actor, pose: "neutral")
        fullBody.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let data = image?.tiffRepresentation {
            currentMask = NSBitmapImageRep(data: data)
        }
        layer?.addSublayer(fullBody)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        actor == .frieren ? "芙莉莲" : "辛美尔"
    }

    override func accessibilityHelp() -> String? {
        "单击或按下触发动作；双击触发双人互动；拖动移动桌宠；显示菜单可选择动作、调整大小或暂停自主动作。"
    }

    /// Accessibility frames are screen coordinates. Convert the currently
    /// presented whole-body layer rectangle so authored poses and movement
    /// keep the VoiceOver target aligned with the visible character.
    override func accessibilityFrame() -> NSRect {
        guard let window, let scene = superview as? PetSceneView,
              let actorLayer = layer?.presentation() ?? layer,
              let sceneLayer = scene.layer?.presentation() ?? scene.layer else { return .zero }
        let bodyLayer = fullBody.presentation() ?? fullBody
        let sceneRect = actorLayer.convert(bodyLayer.frame, to: sceneLayer)
        let sceneFrame = NSRect(x: sceneRect.origin.x, y: sceneRect.origin.y,
                                width: sceneRect.width, height: sceneRect.height)
        let windowRect = scene.convert(sceneFrame, to: nil)
        return window.convertToScreen(windowRect)
    }

    override func accessibilityPerformPress() -> Bool {
        (superview as? PetSceneView)?.accessibilityPress(actor) ?? false
    }

    override func accessibilityPerformShowMenu() -> Bool {
        (superview as? PetSceneView)?.accessibilityShowMenu(for: actor) ?? false
    }

    override func layout() {
        super.layout()
        fullBody.contentsScale = window?.backingScaleFactor ?? 2
        if let direction = canonicalWalkDirection {
            installCanonicalWalkGeometry(direction: direction)
        } else if let action = canonicalAction {
            installCanonicalActionGeometry(action: action)
        } else if !customWholeBodyFrame {
            fullBody.frame = bounds
        }
    }

    /// Shows one complete image inside an explicitly anchored local rectangle.
    /// This also provides the common whole-image path for authored gesture strips.
    func showWholeBodyFrame(_ image: NSImage, pose: String, localFrame: NSRect,
                            transition: Double = 0) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        canonicalWalkDirection = nil
        canonicalWalkSample = nil
        canonicalAction = nil
        canonicalActionSample = nil
        canonicalActionRootOffsetX = 0
        customWholeBodyFrame = localFrame != bounds
        currentPose = pose
        if let data = image.tiffRepresentation { currentMask = NSBitmapImageRep(data: data) }
        // Whole-body drawings are authored poses. Swap the single image
        // immediately so older callers cannot introduce a cross-fade ghost.
        fullBody.removeAnimation(forKey: "pose")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fullBody.frame = localFrame
        fullBody.contents = cgImage
        CATransaction.commit()
    }

    func setPose(_ pose: String, transition: Double = 0) {
        guard currentPose != pose,
              let image = AssetStore.shared.productionImage(actor: actor, pose: pose) else { return }
        showWholeBodyFrame(image, pose: pose, localFrame: bounds, transition: 0)
    }

    /// Displays a canonical full-body walk frame at the shared stride phase.
    /// The same uniform scale is used for both directions and all four samples;
    /// the measured direction root and foot anchor are the only placement inputs.
    func setCanonicalWalk(direction: String, phase: Double, phaseOffset: Double = 0) {
        let wrapped = (phase + phaseOffset).truncatingRemainder(dividingBy: 1)
        let sample = (Int(floor(wrapped * 4)) % 4 + 4) % 4
        if currentPose == "walk", canonicalWalkDirection == direction, canonicalWalkSample == sample { return }
        guard let image = AssetStore.shared.canonicalWalkImage(actor: actor,
                                                               direction: direction,
                                                               frame: sample),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              AssetStore.shared.canonicalWalkAnchor(actor: actor, direction: direction) != nil else { return }
        canonicalWalkDirection = direction
        canonicalWalkSample = sample
        canonicalAction = nil
        canonicalActionSample = nil
        customWholeBodyFrame = true
        currentPose = "walk"
        if let data = image.tiffRepresentation { currentMask = NSBitmapImageRep(data: data) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fullBody.removeAnimation(forKey: "pose")
        fullBody.frame = canonicalWalkFrame(direction: direction)
        fullBody.contents = cgImage
        CATransaction.commit()
    }

    /// Shows one authored whole-body action drawing. Position uses a fixed
    /// action-wide torso root and foot anchor; frame bounds never drive scale.
    func setCanonicalAction(_ action: String, frame: Int, rootOffsetX: CGFloat = 0) {
        if currentPose == "canonical-\(action)", canonicalAction == action,
           canonicalActionSample == frame, canonicalActionRootOffsetX == rootOffsetX { return }
        guard let image = AssetStore.shared.canonicalActionImage(actor: actor, action: action, frame: frame),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              AssetStore.shared.canonicalActionAnchor(actor: actor, action: action) != nil else { return }
        canonicalWalkDirection = nil
        canonicalWalkSample = nil
        canonicalAction = action
        canonicalActionSample = frame
        canonicalActionRootOffsetX = rootOffsetX
        customWholeBodyFrame = true
        currentPose = "canonical-\(action)"
        if let data = image.tiffRepresentation { currentMask = NSBitmapImageRep(data: data) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fullBody.removeAnimation(forKey: "pose")
        fullBody.frame = canonicalActionFrame(action: action)
        fullBody.contents = cgImage
        CATransaction.commit()
    }

    func canonicalActionPoint(_ action: String, frame: Int, x: CGFloat, y: CGFloat) -> NSPoint? {
        guard canonicalAction == action, canonicalActionSample == frame,
              let anchor = AssetStore.shared.canonicalActionAnchor(actor: actor, action: action),
              fullBody.frame.width > 0, fullBody.frame.height > 0 else { return nil }
        return NSPoint(x: fullBody.frame.minX + x / anchor.canvasWidth * fullBody.frame.width,
                       y: fullBody.frame.minY + (1 - y / anchor.canvasHeight) * fullBody.frame.height)
    }

    func setWalkTransform(dx: CGFloat, dy: CGFloat, scale: CGFloat = 1, rotation: CGFloat = 0) {
        guard let actorLayer = layer else { return }
        let transform = CGAffineTransform(translationX: dx, y: dy)
            .scaledBy(x: scale, y: scale).rotated(by: rotation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        actorLayer.removeAnimation(forKey: "poseTransform")
        actorLayer.setAffineTransform(transform)
        CATransaction.commit()
    }

    private func installCanonicalWalkGeometry(direction: String) {
        fullBody.frame = canonicalWalkFrame(direction: direction)
    }

    private func installCanonicalActionGeometry(action: String) {
        fullBody.frame = canonicalActionFrame(action: action)
    }

    private func canonicalActionFrame(action: String) -> NSRect {
        guard let anchor = AssetStore.shared.canonicalActionAnchor(actor: actor, action: action) else { return bounds }
        let neutralFigureFraction: CGFloat = actor == .himmel ? 1504.0 / 1536.0 : 1445.0 / 1536.0
        let scale = bounds.height * neutralFigureFraction / anchor.nativeCanonicalBodyHeight
        let neutralFootY = bounds.height * (actor == .himmel ? 24.0 / 1536.0 : 42.0 / 1536.0)
        let x = bounds.midX + canonicalActionRootOffsetX - anchor.torsoRootX * scale
        let y = neutralFootY - (anchor.canvasHeight - anchor.footAnchorY) * scale
        return NSRect(x: x, y: y, width: anchor.canvasWidth * scale, height: anchor.canvasHeight * scale)
    }

    private func canonicalWalkFrame(direction: String) -> NSRect {
        guard let anchor = AssetStore.shared.canonicalWalkAnchor(actor: actor, direction: direction),
              let left = AssetStore.shared.canonicalWalkAnchor(actor: actor, direction: "left"),
              let right = AssetStore.shared.canonicalWalkAnchor(actor: actor, direction: "right") else { return bounds }
        let neutralFigureFraction: CGFloat = actor == .himmel ? 1504.0 / 1536.0 : 1445.0 / 1536.0
        let sharedNativeHeight = (left.nativeCanonicalBodyHeight + right.nativeCanonicalBodyHeight) / 2
        let scale = bounds.height * neutralFigureFraction / sharedNativeHeight
        let neutralFootY = bounds.height * (actor == .himmel ? 24.0 / 1536.0 : 42.0 / 1536.0)
        let x = bounds.midX - anchor.torsoRootX * scale
        let y = neutralFootY - (anchor.canvasHeight - anchor.footAnchorY) * scale
        return NSRect(x: x, y: y, width: anchor.canvasWidth * scale, height: anchor.canvasHeight * scale)
    }

    func reset(duration: Double = 0.25) {
        setPose("neutral", transition: 0)
        setWalkTransform(dx: 0, dy: 0)
    }

    func alphaHit(_ point: NSPoint) -> Bool {
        guard let rep = currentMask else { return false }
        let drawn: NSRect
        if canonicalWalkDirection != nil || canonicalAction != nil || currentPose.hasPrefix("canonical-") {
            drawn = fullBody.frame
        } else if customWholeBodyFrame {
            drawn = fullBody.frame
        } else {
            // Preserve the original resizeAspect hit area for all legacy poses.
            let imageWidth = CGFloat(rep.pixelsWide)
            let imageHeight = CGFloat(rep.pixelsHigh)
            let imageScale = min(bounds.width / imageWidth, bounds.height / imageHeight)
            let drawnWidth = imageWidth * imageScale
            let drawnHeight = imageHeight * imageScale
            drawn = NSRect(x: (bounds.width - drawnWidth) / 2,
                           y: (bounds.height - drawnHeight) / 2,
                           width: drawnWidth, height: drawnHeight)
        }
        guard drawn.width > 0, drawn.height > 0, drawn.contains(point) else { return false }
        let x = Int((point.x - drawn.minX) / drawn.width * CGFloat(rep.pixelsWide))
        // NSView coordinates grow upward; NSBitmapImageRep rows grow downward.
        let y = Int((1 - (point.y - drawn.minY) / drawn.height) * CGFloat(rep.pixelsHigh))
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return false }
        return (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08
    }
}
