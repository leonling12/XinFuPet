import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SceneWindow {
    static func needsVisibilityChange(isVisible: Bool, targetVisible: Bool) -> Bool {
        isVisible != targetVisible
    }

    let panel: PetPanel
    let scene: PetSceneView
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var actorMouseCaptureActive = false

    init(frame: NSRect, coordinator: AppCoordinator) {
        panel = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "芙莉莲与辛美尔"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = PetSettings.shared.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true; panel.isMovableByWindowBackground = false; panel.hidesOnDeactivate = false
        panel.minSize = PetSceneView.sceneSize(scale: 0.55, spacing: PetSettings.shared.pairSpacing)
        panel.maxSize = PetSceneView.sceneSize(scale: 2.0, spacing: PetSettings.shared.pairSpacing)
        scene = PetSceneView(frame: NSRect(origin: .zero, size: frame.size))
        scene.coordinator = coordinator
        panel.contentView = scene
        panel.orderFrontRegardless()
        installPassThrough()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func pointIsInteractive(_ screenPoint: NSPoint) -> Bool {
        guard panel.frame.contains(screenPoint) else { return false }
        let wp = panel.convertPoint(fromScreen: screenPoint)
        let vp = scene.convert(wp, from: nil)
        return scene.actor(at: vp) != nil
    }

    private func updatePassThrough(at screenPoint: NSPoint) {
        guard !actorMouseCaptureActive else {
            panel.ignoresMouseEvents = false
            return
        }
        panel.ignoresMouseEvents = !pointIsInteractive(screenPoint)
    }

    func beginActorMouseCapture() {
        actorMouseCaptureActive = true
        panel.ignoresMouseEvents = false
    }

    func showPets() {
        guard Self.needsVisibilityChange(isVisible: panel.isVisible, targetVisible: true) else { return }
        panel.orderFrontRegardless()
    }

    func hidePets() {
        guard Self.needsVisibilityChange(isVisible: panel.isVisible, targetVisible: false) else { return }
        panel.orderOut(nil)
    }

    func endActorMouseCapture() {
        actorMouseCaptureActive = false
        updatePassThrough(at: NSEvent.mouseLocation)
    }

    private func installPassThrough() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.updatePassThrough(at: NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.updatePassThrough(at: NSEvent.mouseLocation)
            return event
        }
        updatePassThrough(at: NSEvent.mouseLocation)
    }
}
