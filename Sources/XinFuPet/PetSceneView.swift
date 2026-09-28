import AppKit
import QuartzCore

private final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PetSceneView: NSView {
    // Geometry is measured on the original neutral full-body PNGs. The images
    // remain whole; only their view frames are scaled and placed here.
    static var baseSceneHeight: CGFloat {
        180 / (characterHeightFraction * himmelNeutralFootprint.height)
    }
    static let characterHeightFraction: CGFloat = 0.94
    static let characterAspect: CGFloat = 2.0 / 3.0
    static let horizontalPadding: CGFloat = 20
    static let frierenVisibleHeightRatio: CGFloat = 0.88
    static let frierenNeutralFootprint = NSRect(x: 280.0 / 1024, y: 42.0 / 1536,
                                               width: 496.0 / 1024, height: 1445.0 / 1536)
    static let himmelNeutralFootprint = NSRect(x: 137.0 / 1024, y: 24.0 / 1536,
                                              width: 749.0 / 1024, height: 1504.0 / 1536)
    static var frierenCanvasHeightRatio: CGFloat {
        frierenVisibleHeightRatio * himmelNeutralFootprint.height / frierenNeutralFootprint.height
    }

    static var baseContentWidth: CGFloat {
        let hWidth = baseSceneHeight * characterHeightFraction * characterAspect
        let fWidth = hWidth * frierenCanvasHeightRatio
        return frierenNeutralFootprint.maxX * fWidth + (1 - himmelNeutralFootprint.minX) * hWidth + 2 * horizontalPadding
    }

    static func sceneSize(scale: CGFloat, spacing: CGFloat) -> NSSize {
        NSSize(width: baseContentWidth * scale + spacing, height: baseSceneHeight * scale)
    }
    let frieren = ActorView(actor: .frieren)
    let himmel = ActorView(actor: .himmel)
    private let flowerView = PassThroughImageView(frame: .zero)
    lazy var engine = AnimationEngine(scene: self)
    weak var coordinator: AppCoordinator?
    private var hoverWork: DispatchWorkItem?
    private var dragOrigin: NSPoint = .zero
    private var windowOrigin: NSPoint = .zero
    private var lastWalkMouseLocation: NSPoint = .zero
    private var dragWalkDistanceInCycles: Double = 0
    private var lastWalkInputUptime: TimeInterval = 0
    private var dragWalkActive = false
    private var pendingDragWalkSettle = false
    private(set) var lastHorizontalWalkDirection = "left"
    private var walkFrontActor: ActorID = .himmel
    var isDraggingWalkActive: Bool { dragWalkActive }
    var hasPendingWalkDragSettle: Bool { pendingDragWalkSettle }
    var manualDragWalkPhase: Double { dragWalkDistanceInCycles }
    private var dragged = false
    private var pressedActor: ActorID?
    private var actorPointerCaptured = false
    private var consumedDoubleClick = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(frieren); addSubview(himmel)
        flowerView.imageScaling = .scaleProportionallyUpOrDown
        flowerView.isHidden = true
        addSubview(flowerView, positioned: .above, relativeTo: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? { "芙莉莲与辛美尔场景" }

    override func accessibilityChildren() -> [Any]? {
        walkFrontActor == .frieren ? [frieren, himmel] : [himmel, frieren]
    }

    override func accessibilityHitTest(_ screenPoint: NSPoint) -> Any? {
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let scenePoint = convert(windowPoint, from: nil)
        guard let actor = actor(at: scenePoint) else { return nil }
        return actor == .frieren ? frieren : himmel
    }

    func accessibilityPress(_ actor: ActorID) -> Bool {
        guard coordinator != nil else { return false }
        activateActor(actor)
        return true
    }

    func accessibilityShowMenu(for actor: ActorID) -> Bool {
        guard coordinator != nil, let window else { return false }
        let actorView = actor == .frieren ? frieren : himmel
        let screenFrame = actorView.accessibilityFrame()
        guard !screenFrame.isEmpty else { return false }
        let screenCenter = NSPoint(x: screenFrame.midX, y: screenFrame.midY)
        let windowPoint = window.convertPoint(fromScreen: screenCenter)
        let scenePoint = convert(windowPoint, from: nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, let coordinator = self.coordinator else { return }
            _ = coordinator.showContextMenu(at: scenePoint, in: self)
        }
        return true
    }

    private func activateActor(_ actor: ActorID) {
        coordinator?.playRandomClick(for: actor)
    }

    override func layout() {
        super.layout()
        let h = bounds.height * Self.characterHeightFraction
        let hWidth = h * Self.characterAspect
        let fHeight = h * Self.frierenCanvasHeightRatio
        let fWidth = fHeight * Self.characterAspect
        let gap = PetSettings.shared.pairSpacing
        let hLeft = Self.frierenNeutralFootprint.maxX * fWidth + gap - Self.himmelNeutralFootprint.minX * hWidth
        let total = hLeft + hWidth
        let x0 = (bounds.width - total) / 2
        let ground = bounds.height * 0.035
        frieren.frame = NSRect(x: x0, y: ground - Self.frierenNeutralFootprint.minY * fHeight, width: fWidth, height: fHeight)
        himmel.frame = NSRect(x: x0 + hLeft, y: ground - Self.himmelNeutralFootprint.minY * h, width: hWidth, height: h)
    }

    func actor(at p: NSPoint) -> ActorID? {
        // Use the rendered layer position so hit testing follows whole-body motion.
        let sceneLayer = layer?.presentation() ?? layer
        let frierenLayer = frieren.layer?.presentation() ?? frieren.layer
        let himmelLayer = himmel.layer?.presentation() ?? himmel.layer
        let fp = frierenLayer?.convert(p, from: sceneLayer) ?? frieren.convert(p, from: self)
        let hp = himmelLayer?.convert(p, from: sceneLayer) ?? himmel.convert(p, from: self)
        if walkFrontActor == .frieren {
            if frieren.alphaHit(fp) { return .frieren }
            if himmel.alphaHit(hp) { return .himmel }
        } else {
            if himmel.alphaHit(hp) { return .himmel }
            if frieren.alphaHit(fp) { return .frieren }
        }
        return nil
    }

    func setWalkDepth(direction: String?) {
        let nextFrontActor: ActorID = direction == "right" ? .frieren : .himmel
        guard nextFrontActor != walkFrontActor else { return }
        walkFrontActor = nextFrontActor
        if walkFrontActor == .frieren {
            addSubview(frieren, positioned: .above, relativeTo: himmel)
        } else {
            addSubview(himmel, positioned: .above, relativeTo: frieren)
        }
        addSubview(flowerView, positioned: .above, relativeTo: nil)
    }

    func setFlowerHidden(_ hidden: Bool) {
        flowerView.isHidden = hidden
    }

    func setFlowerAtGestureHand(actor: ActorID, action: String, frame: Int,
                                anchor: AssetStore.PixelAnchor) -> NSPoint? {
        guard let contact = gestureHandPoint(actor: actor, action: action, frame: frame, anchor: anchor) else { return nil }
        setFlowerAtContact(contact)
        return contact
    }

    func gestureHandPoint(actor: ActorID, action: String, frame: Int,
                          anchor: AssetStore.PixelAnchor) -> NSPoint? {
        let view = actor == .frieren ? frieren : himmel
        guard let local = view.canonicalActionPoint(action, frame: frame, x: anchor.x, y: anchor.y) else { return nil }
        return view.convert(local, to: self)
    }

    func setFlowerAtContact(_ contact: NSPoint) {
        guard let image = AssetStore.shared.flowerImage() else { return }
        flowerView.image = image
        let scale = bounds.height / Self.baseSceneHeight
        let height = 26 * scale
        let width = height * image.size.width / max(1, image.size.height)
        let flowerPinchX = width * (157.0 / 255.0)
        let flowerPinchY = height * (1 - 220.0 / 425.0)
        flowerView.frame = NSRect(x: contact.x - flowerPinchX, y: contact.y - flowerPinchY,
                                  width: width, height: height)
        if let propLayer = flowerView.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            propLayer.anchorPoint = CGPoint(x: 157.0 / 255.0, y: 1 - 220.0 / 425.0)
            propLayer.position = contact
            propLayer.setAffineTransform(CGAffineTransform(rotationAngle: -0.24))
            CATransaction.commit()
        }
        flowerView.isHidden = false
    }

    func setFlowerBetween(_ from: NSPoint, _ to: NSPoint, progress: CGFloat) {
        guard let image = AssetStore.shared.flowerImage() else { return }
        flowerView.image = image
        let scale = bounds.height / Self.baseSceneHeight
        let height = 26 * scale
        let width = height * image.size.width / max(1, image.size.height)
        let p = min(1, max(0, progress))
        let contact = NSPoint(x: from.x + (to.x - from.x) * p,
                             y: from.y + (to.y - from.y) * p)
        let flowerPinchX = width * (157.0 / 255.0)
        let flowerPinchY = height * (1 - 220.0 / 425.0)
        flowerView.frame = NSRect(x: contact.x - flowerPinchX, y: contact.y - flowerPinchY,
                                  width: width, height: height)
        if let propLayer = flowerView.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            propLayer.anchorPoint = CGPoint(x: 157.0 / 255.0, y: 1 - 220.0 / 425.0)
            propLayer.position = contact
            propLayer.setAffineTransform(CGAffineTransform(rotationAngle: -0.24))
            CATransaction.commit()
        }
        flowerView.isHidden = false
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard !PetSettings.shared.paused, pressedActor == nil, !dragWalkActive else {
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        hoverWork?.cancel()
        let p = convert(event.locationInWindow, from: nil)
        guard let a = actor(at: p) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.performHoverActionIfEligible {
                self.coordinator?.play(a == .frieren ? "F11" : "H01", userInitiated: true)
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (a == .frieren ? 0.55 : 0.25), execute: work)
    }
    override func mouseExited(with event: NSEvent) {
        hoverWork?.cancel()
        hoverWork = nil
    }

    @discardableResult
    func performHoverActionIfEligible(_ action: () -> Void) -> Bool {
        guard !PetSettings.shared.paused, pressedActor == nil, !dragWalkActive else { return false }
        action()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        hoverWork?.cancel()
        hoverWork = nil
        let p = convert(event.locationInWindow, from: nil)
        guard let hitActor = actor(at: p) else {
            pressedActor = nil
            actorPointerCaptured = false
            consumedDoubleClick = false
            dragged = false
            return
        }
        pressedActor = hitActor
        actorPointerCaptured = true
        coordinator?.beginActorMouseCapture()
        dragOrigin = NSEvent.mouseLocation
        lastWalkMouseLocation = dragOrigin
        beginWalkDragInput(timestamp: event.timestamp)
        windowOrigin = window.frame.origin
        dragged = false
        consumedDoubleClick = event.clickCount >= 2
        if consumedDoubleClick {
            coordinator?.playDuoUserEvent()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard actorPointerCaptured, pressedActor != nil, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragOrigin.x, dy = now.y - dragOrigin.y
        if sqrt(dx * dx + dy * dy) > 3 { dragged = true }
        if dragged {
            let deltaX = now.x - lastWalkMouseLocation.x
            let deltaY = now.y - lastWalkMouseLocation.y
            lastWalkMouseLocation = now
            applyWalkDragInput(horizontalDelta: deltaX, verticalDelta: deltaY, timestamp: event.timestamp)
        }
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.constrainScene()
        if dragged { finishWalkDragInput() }
        defer {
            if actorPointerCaptured { coordinator?.endActorMouseCapture() }
            actorPointerCaptured = false
            pressedActor = nil
            consumedDoubleClick = false
        }
        guard !consumedDoubleClick, !dragged, let a = pressedActor else { return }
        activateActor(a)
    }

    func beginWalkDragInput(timestamp: TimeInterval? = nil) {
        dragWalkDistanceInCycles = 0
        lastWalkInputUptime = timestamp ?? ProcessInfo.processInfo.systemUptime
        dragWalkActive = false
        pendingDragWalkSettle = false
    }

    func applyWalkDragInput(horizontalDelta: CGFloat, verticalDelta: CGFloat,
                            timestamp: TimeInterval? = nil) {
        let inputUptime = timestamp ?? ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, inputUptime - lastWalkInputUptime)
        lastWalkInputUptime = max(lastWalkInputUptime, inputUptime)
        guard !PetSettings.shared.paused else { return }
        if horizontalDelta > 0.001 { lastHorizontalWalkDirection = "right" }
        if horizontalDelta < -0.001 { lastHorizontalWalkDirection = "left" }
        let distance = hypot(horizontalDelta, verticalDelta)
        guard distance > 0.001 else { return }

        // The four authored samples contain two repeated poses. A quarter-cycle
        // is one visible leg switch, so cap that cadence at two switches/second.
        // Keep a small minimum while genuine movement continues, but never catch
        // up after a stalled event: excess distance phase is discarded.
        let effectiveDeltaTime = min(elapsed, 0.10)
        guard effectiveDeltaTime > 0 else { return }
        let distancePhase = Double(distance / max(1, 132 * PetSettings.shared.sizeScale))
        let phaseDelta = min(max(distancePhase, 0.22 * effectiveDeltaTime),
                             0.50 * effectiveDeltaTime)
        dragWalkDistanceInCycles += phaseDelta
        let phase = dragWalkDistanceInCycles.truncatingRemainder(dividingBy: 1)
        if !dragWalkActive {
            if let coordinator { coordinator.beginManualWalkDrag() }
            else { engine.cancelPlaybackPreservingPoses() }
        }
        frieren.setCanonicalWalk(direction: lastHorizontalWalkDirection, phase: phase)
        himmel.setCanonicalWalk(direction: lastHorizontalWalkDirection, phase: phase, phaseOffset: 0.25)
        setWalkDepth(direction: lastHorizontalWalkDirection)
        dragWalkActive = true
        pendingDragWalkSettle = false
    }

    func finishWalkDragInput() {
        guard dragWalkActive else { return }
        if PetSettings.shared.paused {
            pendingDragWalkSettle = true
            return
        }
        if let coordinator {
            coordinator.settleManualWalkDrag(direction: lastHorizontalWalkDirection,
                                             phase: dragWalkDistanceInCycles)
        } else {
            engine.settleManualWalkDrag(direction: lastHorizontalWalkDirection,
                                        phase: dragWalkDistanceInCycles)
        }
        dragWalkActive = false
        pendingDragWalkSettle = false
    }

    func settlePausedDragAfterResume() {
        guard pendingDragWalkSettle else { return }
        finishWalkDragInput()
    }

    override func rightMouseDown(with event: NSEvent) { coordinator?.showContextMenu(event: event, in: self) }

    override func magnify(with event: NSEvent) {
        coordinator?.resizeContinuously(by: event.magnification)
    }
}
