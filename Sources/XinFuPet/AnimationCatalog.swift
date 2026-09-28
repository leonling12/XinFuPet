import AppKit
import Foundation

final class AnimationCatalog {
    static let shared = AnimationCatalog()
    private(set) var plans: [String: ActionPlan] = [:]

    private init() { build() }
    func plan(_ id: String) -> ActionPlan? { plans[id] }
    func ids(prefix: String) -> [String] { plans.keys.filter { $0.hasPrefix(prefix) }.sorted() }

    private func f(_ t: Double, _ p: String, dx: CGFloat = 0, dy: CGFloat = 0,
                   s: CGFloat = 1, r: CGFloat = 0) -> PoseKeyframe {
        .init(t, p, dx: dx, dy: dy, scale: s, rotation: r)
    }
    private func t(_ actor: ActorID, _ frames: [PoseKeyframe], delay: Double = 0) -> ActorTrack {
        .init(actor: actor, startDelay: delay, frames: frames)
    }
    private func add(_ id: String, _ name: String, _ duration: Double, _ trigger: String,
                     _ category: String, _ tracks: [ActorTrack], cooldown: Double = 25) {
        plans[id] = .init(id: id, nameZH: name, duration: duration, trigger: trigger,
                          cooldown: cooldown, tracks: tracks, category: category)
    }

    private func build() {
        // Frieren: 12 distinct action poses, each transitions in and returns to idle.
        add("F01", "翻阅魔法书", 6.0, "自主 / 单击", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.055, "bookajar"), f(0.12, "bookhalf"),
            f(0.21, "read"), f(0.72, "read", dx: 3),
            f(0.82, "bookhalf"), f(0.90, "bookajar"), f(1, "neutral")
        ])], cooldown: 35)
        add("F02", "查看地图", 5.5, "自主", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.18, "map", dy: -3), f(0.72, "map", dx: -3, dy: -5), f(1, "neutral")
        ])], cooldown: 55)
        add("F03", "举杖施法", 5.0, "单击 / 双人互动", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.12, "staffraise", dx: 2), f(0.26, "staff", dx: 3),
            f(0.42, "cast", dx: 7), f(0.68, "cast", dx: 4),
            f(0.84, "staffraise", dx: 2), f(1, "neutral")
        ])], cooldown: 55)
        add("F04", "研究路边小物", 5.0, "自主", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.20, "inspect", dy: -6), f(0.76, "inspect", dx: 3, dy: -4), f(1, "neutral")
        ])], cooldown: 40)
        add("F05", "整理头发和衣领", 4.6, "自主 / 悬停", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.20, "adjust", dx: 2), f(0.72, "adjust", dx: -2, r: -0.008), f(1, "neutral")
        ])], cooldown: 36)
        add("F06", "整理行囊", 5.5, "自主", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.20, "pack", dx: -3), f(0.74, "pack", dx: 3, dy: -3), f(1, "neutral")
        ])], cooldown: 50)
        add("F07", "扶杖观察", 4.8, "自主低频", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.12, "staffraise"), f(0.22, "staff", dx: 2),
            f(0.68, "staff", dx: -2), f(0.84, "staffraise"), f(1, "neutral")
        ])], cooldown: 55)
        add("F08", "坐下读书", 8.5, "自主 / 菜单", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.10, "sitstart", dy: -2), f(0.24, "sitread", dy: -3),
            f(0.76, "sitread"), f(0.88, "sitstart", dy: -2), f(1, "neutral")
        ])], cooldown: 70)
        add("F09", "看书时打盹", 9.0, "自主低频", "Frieren", [t(.frieren, [
            f(0, "sitread"), f(0.24, "sitread", dy: -2), f(0.48, "doze", dy: 3),
            f(0.82, "doze", r: -0.01), f(1, "sitread")
        ])], cooldown: 100)
        add("F10", "打盹后醒来", 5.0, "自主低频", "Frieren", [t(.frieren, [
            f(0, "doze"), f(0.26, "wake", dy: 1), f(0.68, "wake", dx: 2), f(0.88, "neutral", dy: -1), f(1, "neutral")
        ])], cooldown: 60)
        add("F11", "听见动静回望", 4.5, "悬停 / 点击", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.20, "notice", dx: 3), f(0.72, "notice", dx: 5, r: -0.008), f(1, "neutral")
        ])], cooldown: 30)
        add("F12", "缓步向前", 6.2, "自主走动", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.13, "walk", dx: 3), f(0.48, "walk", dx: 8, dy: -2),
            f(0.76, "walk", dx: 12), f(1, "neutral", dx: 14)
        ])], cooldown: 50)
        add("F13", "伸展肩背", 4.8, "自主", "Frieren", [t(.frieren, [
            f(0, "neutral"), f(0.20, "stretch", dy: 2), f(0.72, "stretch", r: 0.008), f(1, "neutral")
        ])], cooldown: 65)

        // Himmel: 13 distinct action poses, including both phases of a sword practice.
        add("H01", "向你招呼", 4.0, "单击 / 悬停", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.075, "greetquarter"), f(0.16, "greetstart"),
            f(0.27, "greet"), f(0.65, "greet", dx: 3),
            f(0.77, "greetstart"), f(0.87, "greetquarter"), f(1, "neutral")
        ])], cooldown: 30)
        add("H02", "坐下休息", 8.0, "自主 / 菜单", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.12, "sitstart", dy: -2), f(0.28, "sit", dy: -3),
            f(0.75, "sit"), f(0.88, "sitstart", dy: -2), f(1, "neutral")
        ])], cooldown: 75)
        add("H03", "递上一朵花", 6.5, "双人互动", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.20, "flower", dx: -4), f(0.76, "flower", dx: -7), f(1, "neutral")
        ])], cooldown: 120)
        add("H04", "整理披风", 4.8, "自主", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.20, "cape", dx: 2), f(0.70, "cape", dx: -2), f(1, "neutral")
        ])], cooldown: 38)
        add("H05", "练习剑术", 5.7, "自主低频 / 菜单", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.16, "swordcheck"), f(0.37, "swordpractice", dx: 5, r: 0.012),
            f(0.72, "swordpractice", dx: 2), f(1, "neutral")
        ])], cooldown: 90)
        add("H06", "确认佩剑", 4.4, "自主", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.18, "swordcheck", dy: -2), f(0.70, "swordcheck"), f(1, "neutral")
        ])], cooldown: 55)
        add("H07", "摆出勇者姿势", 4.4, "自主 / 单击", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.20, "hero", dy: -2), f(0.72, "hero", dx: 3), f(1, "neutral")
        ])], cooldown: 50)
        add("H08", "回头等同伴", 4.8, "自主", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.20, "look", dx: -3), f(0.72, "look", dx: -5), f(1, "neutral")
        ])], cooldown: 45)
        add("H09", "指向远处风景", 4.8, "双人互动", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.20, "point", dx: 3), f(0.72, "point", dx: 5), f(1, "neutral")
        ])], cooldown: 55)
        add("H10", "弯腰拾起物件", 5.0, "自主", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.22, "kneel", dy: -4), f(0.74, "kneel", dx: -2), f(1, "neutral")
        ])], cooldown: 60)
        add("H11", "安静等候", 4.5, "自主低频", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.22, "rest"), f(0.74, "rest", dx: 2), f(1, "neutral")
        ])], cooldown: 55)
        add("H12", "缓步巡看", 6.0, "自主走动", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.14, "walk", dx: -3), f(0.50, "walk", dx: -8, dy: -2),
            f(0.78, "walk", dx: -12), f(1, "neutral", dx: -14)
        ])], cooldown: 55)
        add("H13", "翻看旅途笔记", 5.8, "自主", "Himmel", [t(.himmel, [
            f(0, "neutral"), f(0.20, "read", dy: -2), f(0.76, "read"), f(1, "neutral")
        ])], cooldown: 70)

        // Duo events use separate character tracks and stagger their responses.
        add("D01", "错拍对视", 5.2, "自主 / 双击", "Duo", [
            t(.himmel, [f(0, "neutral"), f(0.20, "look", dx: -4), f(0.76, "look"), f(1, "neutral")]),
            t(.frieren, [f(0, "neutral"), f(0.38, "notice", dx: 4), f(0.78, "notice"), f(1, "neutral")], delay: 0.30)
        ], cooldown: 90)
        add("D02", "互相问候", 5.0, "双击 / 点击菜单", "Duo", [
            t(.himmel, [f(0, "neutral"), f(0.06, "greetquarter", dx: -1),
                f(0.13, "greetstart", dx: -2), f(0.24, "greet", dx: -3),
                f(0.68, "greet"), f(0.82, "greetstart"), f(0.90, "greetquarter"), f(1, "neutral")]),
            t(.frieren, [f(0, "neutral"), f(0.36, "notice", dx: 4), f(0.76, "neutral")], delay: 0.28)
        ], cooldown: 70)
        add("D03", "并肩看书", 8.0, "自主 / 菜单", "Duo", [
            t(.frieren, [f(0, "neutral"), f(0.05, "bookajar", dx: 1),
                f(0.12, "bookhalf", dx: 2), f(0.21, "read", dx: 4),
                f(0.76, "read"), f(0.84, "bookhalf"), f(0.91, "bookajar"), f(1, "neutral")]),
            t(.himmel, [f(0, "neutral"), f(0.32, "read", dx: -4), f(0.82, "read"), f(1, "neutral")], delay: 0.30)
        ], cooldown: 125)
        add("D04", "一起散步", 7.0, "自主 / 菜单", "Duo", [
            t(.frieren, [f(0, "neutral"), f(0.15, "walk", dx: 4), f(0.78, "walk", dx: 10), f(1, "neutral", dx: 12)]),
            t(.himmel, [f(0, "neutral"), f(0.24, "walk", dx: -4), f(0.80, "walk", dx: -10), f(1, "neutral", dx: -12)], delay: 0.16)
        ], cooldown: 140)
        add("D05", "看地图认路", 6.5, "自主低频", "Duo", [
            t(.frieren, [f(0, "neutral"), f(0.18, "map", dx: 3), f(0.80, "map"), f(1, "neutral")]),
            t(.himmel, [f(0, "neutral"), f(0.30, "point", dx: -4), f(0.78, "point"), f(1, "neutral")], delay: 0.25)
        ], cooldown: 130)
        add("D06", "递花并接过", 7.0, "自主 / 菜单", "Duo", [
            t(.himmel, [f(0, "neutral"), f(0.18, "flower", dx: -5), f(0.78, "flower", dx: -5), f(1, "neutral")]),
            t(.frieren, [f(0, "neutral"), f(0.42, "inspect", dx: 5), f(0.80, "inspect"), f(1, "neutral")], delay: 0.35)
        ], cooldown: 160)
        add("D07", "展示小魔法", 6.4, "双击 / 菜单", "Duo", [
            t(.frieren, [f(0, "neutral"), f(0.10, "staffraise", dx: 2), f(0.24, "staff", dx: 3),
                f(0.38, "cast", dx: 6), f(0.70, "cast"), f(0.86, "staffraise"), f(1, "neutral")]),
            t(.himmel, [f(0, "neutral"), f(0.42, "rest", dx: -4), f(0.80, "rest"), f(1, "neutral")], delay: 0.22)
        ], cooldown: 145)
        add("D08", "一起坐下休息", 9.0, "自主低频", "Duo", [
            t(.frieren, [f(0, "neutral"), f(0.12, "sitstart", dx: 2), f(0.28, "sitread", dx: 3),
                f(0.75, "sitread"), f(0.88, "sitstart"), f(1, "neutral")]),
            t(.himmel, [f(0, "neutral"), f(0.14, "sitstart", dx: -2), f(0.32, "sit", dx: -3),
                f(0.75, "sit"), f(0.88, "sitstart"), f(1, "neutral")], delay: 0.34)
        ], cooldown: 170)
    }
}
