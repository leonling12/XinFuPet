import AppKit

/// Live, continuous controls. Values are persisted by PetSettings.
final class SettingsPanel: NSObject {
    private weak var coordinator: AppCoordinator?
    private let window: NSWindow
    private let size = NSSlider(frame: .zero)
    private let gap = NSSlider(frame: .zero)
    private let speed = NSSlider(frame: .zero)
    private let frequency = NSSlider(frame: .zero)
    private var values: [NSTextField] = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "辛芙设置"
        window.isReleasedWhenClosed = false
        window.center()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
        window.contentView = content
        let rows: [(String, NSSlider, Double, Double, Selector)] = [
            ("双人大小", size, 0.55, 2, #selector(sizeChanged(_:))),
            ("人物间距", gap, 0, 140, #selector(gapChanged(_:))),
            ("动作速度", speed, 0.5, 2, #selector(speedChanged(_:))),
            ("活动频率", frequency, 0.35, 2, #selector(frequencyChanged(_:)))
        ]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(223 - index * 54)
            let label = NSTextField(labelWithString: row.0)
            label.frame = NSRect(x: 20, y: y + 3, width: 105, height: 23)
            content.addSubview(label)
            row.1.frame = NSRect(x: 128, y: y, width: 195, height: 28)
            row.1.minValue = row.2
            row.1.maxValue = row.3
            row.1.isContinuous = true
            row.1.target = self
            row.1.action = row.4
            content.addSubview(row.1)
            let value = NSTextField(labelWithString: "")
            value.alignment = .right
            value.frame = NSRect(x: 328, y: y + 3, width: 72, height: 23)
            content.addSubview(value)
            values.append(value)
        }
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults))
        reset.frame = NSRect(x: 300, y: 12, width: 102, height: 30)
        content.addSubview(reset)
        refresh()
    }

    func show() {
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        size.doubleValue = Double(PetSettings.shared.sizeScale)
        gap.doubleValue = Double(PetSettings.shared.pairSpacing)
        speed.doubleValue = PetSettings.shared.motionSpeed
        frequency.doubleValue = PetSettings.shared.activityFrequency
        values[0].stringValue = String(format: "%.0f%%", size.doubleValue * 100)
        values[1].stringValue = String(format: "%.0f pt", gap.doubleValue)
        values[2].stringValue = String(format: "%.2f×", speed.doubleValue)
        values[3].stringValue = String(format: "%.2f×", frequency.doubleValue)
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        coordinator?.resize(scale: CGFloat(sender.doubleValue))
        refresh()
    }
    @objc private func gapChanged(_ sender: NSSlider) {
        coordinator?.updateSpacing(CGFloat(sender.doubleValue))
        refresh()
    }
    @objc private func speedChanged(_ sender: NSSlider) {
        PetSettings.shared.motionSpeed = sender.doubleValue
        refresh()
    }
    @objc private func frequencyChanged(_ sender: NSSlider) {
        PetSettings.shared.activityFrequency = sender.doubleValue
        refresh()
    }
    @objc private func resetDefaults() {
        coordinator?.restoreDefaults()
        refresh()
    }
}
