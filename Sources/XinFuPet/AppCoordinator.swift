import AppKit
import Foundation

final class AppCoordinator: NSObject {
    private(set) var sceneWindow: SceneWindow!
    private var frierenTimer: DispatchSourceTimer?
    private var himmelTimer: DispatchSourceTimer?
    private var duoTimer: DispatchSourceTimer?
    private var recentF: [String] = [], recentH: [String] = [], recentD: [String] = []
    private var busy = false
    private var displayObservers: [NSObjectProtocol] = []

    deinit { displayObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    private let autonomousF = (1...13).map { String(format: "F%02d", $0) }
    private let autonomousH = (1...13).map { String(format: "H%02d", $0) }
    private let autonomousD = (1...8).map { String(format: "D%02d", $0) }

    func start() {
        let scale = PetSettings.shared.sizeScale
        let size = PetSceneView.sceneSize(scale: scale, spacing: PetSettings.shared.pairSpacing)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = PetSettings.shared.sceneOrigin ?? NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        sceneWindow = SceneWindow(frame: NSRect(origin: origin, size: size), coordinator: self)
        constrainScene()
        let center = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification,
                     NSWindow.didChangeScreenNotification,
                     NSWindow.didChangeBackingPropertiesNotification] {
            displayObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.constrainScene()
                self?.sceneWindow?.scene.needsLayout = true
                self?.logRetina()
            })
        }
        updateWindowLevel(); scheduleAll(); logRetina()
    }

    func play(_ id: String, userInitiated: Bool = false) {
        guard !PetSettings.shared.paused, let p = AnimationCatalog.shared.plan(id) else { return }
        busy = true
        sceneWindow.scene.engine.play(p, userInitiated: userInitiated) { [weak self] in self?.busy = false }
    }

    func playRandomClick(for actor: ActorID) {
        let ids = actor == .frieren ? ["F01", "F03", "F05", "F11"] : ["H01", "H03", "H07"]
        if let id = ids.randomElement() { play(id, userInitiated: true) }
    }

    func playDuoUserEvent() {
        if let id = autonomousD.randomElement() { play(id, userInitiated: true) }
    }

    private func scheduleAll() { scheduleSolo(.frieren); scheduleSolo(.himmel); scheduleDuo() }

    private func scheduleSolo(_ actor: ActorID) {
        let freq = max(0.35, PetSettings.shared.activityFrequency)
        let delay = Double.random(in: 25...60) / freq
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + delay)
        t.setEventHandler { [weak self] in
            self?.runSolo(actor)
            self?.scheduleSolo(actor)
        }
        t.resume()
        if actor == .frieren { frierenTimer?.cancel(); frierenTimer = t }
        else { himmelTimer?.cancel(); himmelTimer = t }
    }

    private func runSolo(_ actor: ActorID) {
        guard !PetSettings.shared.paused, !busy else { return }
        let all = actor == .frieren ? autonomousF : autonomousH
        var recent = actor == .frieren ? recentF : recentH
        let candidates = all.filter { !recent.contains($0) }
        guard let id = (candidates.isEmpty ? all : candidates).randomElement() else { return }
        recent.append(id); if recent.count > 3 { recent.removeFirst() }
        if actor == .frieren { recentF = recent } else { recentH = recent }
        play(id)
        if PetSettings.shared.autonomousWalking && (id == "F12" || id == "H12") { nudgeScene() }
    }

    private func scheduleDuo() {
        let freq = max(0.35, PetSettings.shared.activityFrequency)
        let delay = Double.random(in: 120...240) / freq
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + delay)
        t.setEventHandler { [weak self] in
            self?.runDuo()
            self?.scheduleDuo()
        }
        t.resume()
        duoTimer?.cancel(); duoTimer = t
    }

    private func runDuo() {
        guard !PetSettings.shared.paused, !busy else { return }
        let c = autonomousD.filter { !recentD.contains($0) }
        if let id = (c.isEmpty ? autonomousD : c).randomElement() {
            recentD.append(id); if recentD.count > 4 { recentD.removeFirst() }
            play(id)
        }
    }

    func setPaused(_ v: Bool) {
        PetSettings.shared.paused = v
        if v {
            frierenTimer?.cancel(); himmelTimer?.cancel(); duoTimer?.cancel()
            if !sceneWindow.scene.engine.isActionClockActive
                && !sceneWindow.scene.isDraggingWalkActive { busy = false }
        } else {
            sceneWindow.scene.settlePausedDragAfterResume()
            if !sceneWindow.scene.engine.isActionClockActive && !sceneWindow.scene.isDraggingWalkActive {
                busy = false
            }
            scheduleAll()
        }
    }

    func beginManualWalkDrag() {
        sceneWindow?.scene.engine.cancelPlaybackPreservingPoses()
        sceneWindow?.scene.setFlowerHidden(true)
        busy = true
    }

    func beginActorMouseCapture() { sceneWindow?.beginActorMouseCapture() }

    func endActorMouseCapture() { sceneWindow?.endActorMouseCapture() }

    func settleManualWalkDrag(direction: String, phase: Double) {
        sceneWindow?.scene.engine.settleManualWalkDrag(direction: direction, phase: phase)
    }

    func endManualWalkDrag() { busy = false }

    func updateWindowLevel() {
        sceneWindow?.panel.level = PetSettings.shared.alwaysOnTop ? .floating : .normal
    }

    func showPets() {
        sceneWindow?.showPets()
    }

    func hidePets() {
        sceneWindow?.hidePets()
    }

    func terminateApplication() { NSApp.terminate(nil) }

    func resize(scale: CGFloat) {
        guard let panel = sceneWindow?.panel, let screen = targetScreen(for: panel.frame) else { return }
        let maximum = maximumScale(on: screen)
        let bounded = min(max(scale, min(0.55, maximum)), maximum)
        PetSettings.shared.sizeScale = bounded
        applySize(PetSettings.shared.sizeScale)
    }

    func resizeContinuously(by delta: CGFloat) {
        resize(scale: PetSettings.shared.sizeScale * (1 + delta))
    }

    func updateSpacing(_ points: CGFloat) {
        PetSettings.shared.pairSpacing = points
        applySize(PetSettings.shared.sizeScale)
    }

    func restoreDefaults() {
        PetSettings.shared.restoreDefaults()
        resize(scale: PetSettings.shared.sizeScale)
        updateSpacing(PetSettings.shared.pairSpacing)
    }

    private func applySize(_ scale: CGFloat) {
        guard let p = sceneWindow?.panel else { return }
        if let screen = targetScreen(for: p.frame) { updateWindowSizeLimits(on: screen) }
        let center = NSPoint(x: p.frame.midX, y: p.frame.midY)
        let size = PetSceneView.sceneSize(scale: scale, spacing: PetSettings.shared.pairSpacing)
        let frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        p.setFrame(frame, display: true, animate: !PetSettings.shared.lowMotion)
        constrainScene(); logRetina()
    }

    var maximumSizeScale: CGFloat {
        guard let frame = sceneWindow?.panel.frame, let screen = targetScreen(for: frame) else { return 2 }
        return maximumScale(on: screen)
    }

    var sizeScaleInputBounds: ClosedRange<CGFloat> {
        let maximum = min(2.0, maximumSizeScale)
        return min(0.55, maximum)...maximum
    }

    private func maximumScale(on screen: NSScreen) -> CGFloat {
        let visible = screen.visibleFrame
        let gap = PetSettings.shared.pairSpacing
        return max(0.1, min((visible.width * 0.94 - gap) / PetSceneView.baseContentWidth,
                            visible.height * 0.94 / PetSceneView.baseSceneHeight))
    }

    private func updateWindowSizeLimits(on screen: NSScreen) {
        guard let panel = sceneWindow?.panel else { return }
        let maximum = maximumScale(on: screen)
        let gap = PetSettings.shared.pairSpacing
        panel.minSize = PetSceneView.sceneSize(scale: min(0.55, maximum), spacing: gap)
        panel.maxSize = PetSceneView.sceneSize(scale: maximum, spacing: gap)
    }

    private func targetScreen(for frame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let intersections = screens.map { screen -> (NSScreen, CGFloat) in
            let rect = screen.frame.intersection(frame)
            return (screen, rect.isNull ? 0 : max(0, rect.width) * max(0, rect.height))
        }
        if let largest = intersections.max(by: { lhs, rhs in
            if abs(lhs.1 - rhs.1) < 0.5 {
                return !lhs.0.frame.contains(center) && rhs.0.frame.contains(center)
            }
            return lhs.1 < rhs.1
        }), largest.1 > 0 { return largest.0 }
        return screens.min { lhs, rhs in
            func distance(_ screen: NSScreen) -> CGFloat {
                let nearestX = min(max(center.x, screen.frame.minX), screen.frame.maxX)
                let nearestY = min(max(center.y, screen.frame.minY), screen.frame.maxY)
                let dx = center.x - nearestX, dy = center.y - nearestY
                return dx * dx + dy * dy
            }
            return distance(lhs) < distance(rhs)
        } ?? NSScreen.main
    }

    func constrainScene() {
        guard let p = sceneWindow?.panel, let screen = targetScreen(for: p.frame) else { return }
        updateWindowSizeLimits(on: screen)
        var frame = p.frame
        let fittedScale = min(PetSettings.shared.sizeScale, maximumScale(on: screen))
        let center = NSPoint(x: frame.midX, y: frame.midY)
        PetSettings.shared.sizeScale = fittedScale
        frame.size = PetSceneView.sceneSize(scale: fittedScale, spacing: PetSettings.shared.pairSpacing)
        frame.origin = NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        frame.origin.x = min(max(screen.visibleFrame.minX, frame.origin.x), max(screen.visibleFrame.minX, screen.visibleFrame.maxX - frame.width))
        frame.origin.y = min(max(screen.visibleFrame.minY, frame.origin.y), max(screen.visibleFrame.minY, screen.visibleFrame.maxY - frame.height))
        p.setFrame(frame, display: true)
        sceneWindow.scene.needsLayout = true
        PetSettings.shared.sceneOrigin = frame.origin
    }

    private func nudgeScene() {
        guard let p = sceneWindow?.panel, let s = p.screen ?? NSScreen.main else { return }
        var f = p.frame
        f.origin.x += CGFloat.random(in: -80...80)
        f.origin.x = min(max(s.visibleFrame.minX, f.origin.x), max(s.visibleFrame.minX, s.visibleFrame.maxX - f.width))
        PetSettings.shared.sceneOrigin = f.origin
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = PetSettings.shared.lowMotion ? 0.05 : 1.1 / PetSettings.shared.motionSpeed
            p.animator().setFrameOrigin(f.origin)
        }
    }

    func showContextMenu(event: NSEvent, in view: NSView) {
        let point = view.convert(event.locationInWindow, from: nil)
        _ = showContextMenu(at: point, in: view)
    }

    @discardableResult
    func showContextMenu(at point: NSPoint, in view: NSView) -> Bool {
        let m = NSMenu()
        for (title, id) in [("打招呼","D02"),("共同看书","D03"),("递一朵花","D06"),("小魔法","D07"),("坐下休息","D08")] {
            let i = NSMenuItem(title: title, action: #selector(contextAction(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = id; m.addItem(i)
        }
        m.addItem(.separator())
        let sizeItem = NSMenuItem(title: "设置大小…", action: #selector(contextSize(_:)), keyEquivalent: "")
        sizeItem.target = self; m.addItem(sizeItem)
        let p = NSMenuItem(title: PetSettings.shared.paused ? "恢复自主动作" : "暂停自主动作", action: #selector(contextPause(_:)), keyEquivalent: "")
        p.target = self; m.addItem(p)
        m.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏桌宠", action: #selector(contextHidePets), keyEquivalent: "")
        hide.target = self; m.addItem(hide)
        let quit = NSMenuItem(title: "退出桌宠", action: #selector(contextQuit), keyEquivalent: "")
        quit.target = self; m.addItem(quit)
        return m.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func contextAction(_ s: NSMenuItem) {
        if let id = s.representedObject as? String { play(id, userInitiated: true) }
    }
    @objc private func contextPause(_ s: NSMenuItem) { setPaused(!PetSettings.shared.paused) }
    @objc private func contextSize(_ s: NSMenuItem) { promptForSizePercent() }
    @objc private func contextHidePets() { hidePets() }
    @objc private func contextQuit() { terminateApplication() }

    private func promptForSizePercent() {
        let bounds = sizeScaleInputBounds
        let minimumPercent = Double(bounds.lowerBound * 100)
        let maximumPercent = Double(bounds.upperBound * 100)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        input.stringValue = String(format: "%.1f", Double(PetSettings.shared.sizeScale * 100))
        input.placeholderString = "100"
        input.setAccessibilityLabel("桌宠大小百分比")

        let alert = NSAlert()
        alert.messageText = "设置桌宠大小"
        alert.informativeText = String(format: "输入百分比，例如 80、100 或 120。当前可用范围：%.1f%%–%.1f%%；超出范围会限制在此范围内。", minimumPercent, maximumPercent)
        alert.accessoryView = input
        alert.addButton(withTitle: "应用")
        alert.addButton(withTitle: "取消")
        alert.window.title = "设置桌宠大小"
        alert.window.initialFirstResponder = input
        input.selectText(nil)
        // The app is an accessory with a nonactivating pet panel. Activate it
        // before presenting the standard modal alert so the dialog is visible
        // and its percentage field can receive keyboard input and AX focus.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let rawValue = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(rawValue), percent.isFinite else {
            let invalid = NSAlert()
            invalid.alertStyle = .warning
            invalid.messageText = "没有更改大小"
            invalid.informativeText = String(format: "请输入有限的数字。当前可用范围：%.1f%%–%.1f%%。", minimumPercent, maximumPercent)
            invalid.addButton(withTitle: "好")
            invalid.runModal()
            return
        }

        let requested = CGFloat(percent / 100)
        guard requested.isFinite else { return }
        let applied = min(max(requested, bounds.lowerBound), bounds.upperBound)
        resize(scale: applied)
        if applied != requested {
            let clamped = NSAlert()
            clamped.messageText = "大小已限制在可用范围内"
            clamped.informativeText = String(format: "当前可用范围：%.1f%%–%.1f%%。已应用 %.1f%%。", minimumPercent, maximumPercent, Double(applied * 100))
            clamped.addButton(withTitle: "好")
            clamped.runModal()
        }
    }

    func logRetina() {
        if let p = sceneWindow?.panel {
            let sc = p.backingScaleFactor
            NSLog("XinFuPet development scene %0.0fx%0.0f pt @ %0.2fx -> %0.0fx%0.0f backing px; source details remain limited by each production PNG", p.frame.width, p.frame.height, sc, p.frame.width * sc, p.frame.height * sc)
        }
    }
}
