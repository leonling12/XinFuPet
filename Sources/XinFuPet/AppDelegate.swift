import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator=AppCoordinator(); private var item:NSStatusItem!
    private var settingsPanel: SettingsPanel?
    func applicationDidFinishLaunching(_ n:Notification){ NSApp.setActivationPolicy(.accessory); setupMenu(); coordinator.start() }
    private func setupMenu(){
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength); item.button?.title="桌宠"
        let m=NSMenu()
        func add(_ title:String,_ sel:Selector)->NSMenuItem{let x=NSMenuItem(title:title,action:sel,keyEquivalent:"");x.target=self;m.addItem(x);return x}
        add("暂停 / 恢复",#selector(togglePause)); add("触发双人互动",#selector(duo)); m.addItem(.separator())
        add("设置连续滑杆…",#selector(showSettings))
        add("恢复默认设置",#selector(resetDefaults))
        let actions = NSMenu(title: "动作")
        func addActionList(_ title: String, _ prefix: String, _ count: Int) {
            let submenu = NSMenu(title: title)
            for number in 1...count {
                let id = prefix + String(format: "%02d", number)
                guard let plan = AnimationCatalog.shared.plan(id) else { continue }
                let row = NSMenuItem(title: plan.nameZH, action: #selector(playAction(_:)), keyEquivalent: "")
                row.target = self; row.representedObject = id; submenu.addItem(row)
            }
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            actions.setSubmenu(submenu, for: parent); actions.addItem(parent)
        }
        addActionList("芙莉莲", "F", 13)
        addActionList("辛美尔", "H", 13)
        addActionList("双人互动", "D", 8)
        let actionItem = NSMenuItem(title: "动作", action: nil, keyEquivalent: "")
        m.setSubmenu(actions, for: actionItem); m.addItem(actionItem)
        m.addItem(.separator())
        let sm=NSMenu(title:"大小"); for (n,s) in [("小 70%",0.70),("中 100%",1.0),("大 145%",1.45),("接近屏幕上限 190%",1.90)]{let x=NSMenuItem(title:n,action:#selector(size(_:)),keyEquivalent:"");x.target=self;x.representedObject=s;sm.addItem(x)};let si=NSMenuItem(title:"大小",action:nil,keyEquivalent:"");m.setSubmenu(sm,for:si);m.addItem(si)
        let speed=NSMenu(title:"动作速度");for (n,s) in [("0.75×",0.75),("1.0×",1.0),("1.25×",1.25),("1.5×",1.5)]{let x=NSMenuItem(title:n,action:#selector(speedChange(_:)),keyEquivalent:"");x.target=self;x.representedObject=s;speed.addItem(x)};let spi=NSMenuItem(title:"动作速度",action:nil,keyEquivalent:"");m.setSubmenu(speed,for:spi);m.addItem(spi)
        let freq=NSMenu(title:"自主活动频率");for (n,s) in [("安静 0.5×",0.5),("正常 1.0×",1.0),("活跃 1.5×",1.5),("较活跃 2.0×",2.0)]{let x=NSMenuItem(title:n,action:#selector(freqChange(_:)),keyEquivalent:"");x.target=self;x.representedObject=s;freq.addItem(x)};let fi=NSMenuItem(title:"自主活动频率",action:nil,keyEquivalent:"");m.setSubmenu(freq,for:fi);m.addItem(fi)
        let walk=add("自主走动",#selector(toggleWalk(_:)));walk.state=PetSettings.shared.autonomousWalking ? .on:.off
        let top=add("始终置顶",#selector(toggleTop(_:)));top.state=PetSettings.shared.alwaysOnTop ? .on:.off
        let low=add("低动态",#selector(toggleLow(_:)));low.state=PetSettings.shared.lowMotion ? .on:.off
        m.addItem(.separator())
        add("显示桌宠",#selector(showPets))
        add("隐藏桌宠",#selector(hidePets))
        add("退出桌宠",#selector(quit)); item.menu=m
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.showPets()
        return false
    }
    @objc private func togglePause(){coordinator.setPaused(!PetSettings.shared.paused)}
    @objc private func duo(){coordinator.playDuoUserEvent()}
    @objc private func playAction(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { coordinator.play(id, userInitiated: true) }
    }
    @objc private func showSettings(){
        if settingsPanel == nil { settingsPanel = SettingsPanel(coordinator: coordinator) }
        settingsPanel?.show()
    }
    @objc private func resetDefaults(){coordinator.restoreDefaults(); settingsPanel?.refresh()}
    @objc private func showPets(){coordinator.showPets()}
    @objc private func hidePets(){coordinator.hidePets()}
    @objc private func size(_ s:NSMenuItem){if let v=s.representedObject as? Double{coordinator.resize(scale:CGFloat(v))}}
    @objc private func speedChange(_ s:NSMenuItem){if let v=s.representedObject as? Double{PetSettings.shared.motionSpeed=v}}
    @objc private func freqChange(_ s:NSMenuItem){if let v=s.representedObject as? Double{PetSettings.shared.activityFrequency=v}}
    @objc private func toggleWalk(_ s:NSMenuItem){PetSettings.shared.autonomousWalking.toggle();s.state=PetSettings.shared.autonomousWalking ? .on:.off}
    @objc private func toggleTop(_ s:NSMenuItem){PetSettings.shared.alwaysOnTop.toggle();s.state=PetSettings.shared.alwaysOnTop ? .on:.off;coordinator.updateWindowLevel()}
    @objc private func toggleLow(_ s:NSMenuItem){PetSettings.shared.lowMotion.toggle();s.state=PetSettings.shared.lowMotion ? .on:.off}
    @objc private func quit(){coordinator.terminateApplication()}
}
