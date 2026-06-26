import SwiftUI

enum Lang: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    var label: String { self == .zh ? "中文" : "English" }
}

/// Lightweight in-app localization so the language can be toggled live
/// (mock UI – avoids bundle/.strings reload friction). Covers chrome only;
/// sample chat content stays as-is per the design.
final class Localization: ObservableObject {
    @AppStorage("flow.lang") private var stored: String = "zh"
    @Published var lang: Lang = .zh

    init() { lang = Lang(rawValue: stored) ?? .zh }

    func set(_ l: Lang) { lang = l; stored = l.rawValue }

    func t(_ key: String) -> String { Self.table[key]?[lang] ?? key }

    private static let table: [String: [Lang: String]] = [
        // App / nav
        "app.name":        [.zh: "流动", .en: "FLOW"],
        "nav.chats":       [.zh: "聊天", .en: "Chats"],
        "nav.groups":      [.zh: "群组", .en: "Groups"],
        "nav.discover":    [.zh: "发现", .en: "Discover"],
        "nav.profile":     [.zh: "我",   .en: "Profile"],
        "nav.settings":    [.zh: "设置", .en: "Settings"],
        // Chats
        "chats.title":     [.zh: "我的聊天", .en: "My Chats"],
        "chats.preview":   [.zh: "最近一条消息预览…", .en: "Last message preview."],
        "status.online":   [.zh: "在线", .en: "Online"],
        "status.offline":  [.zh: "离线", .en: "Offline"],
        "chat.today":      [.zh: "今天", .en: "Today"],
        "chat.placeholder":[.zh: "输入消息…", .en: "Type a message…"],
        "chat.send":       [.zh: "发送", .en: "SEND"],
        "chat.voice":      [.zh: "语音", .en: "Text"],
        // Groups
        "groups.title":    [.zh: "群组", .en: "Groups"],
        "groups.create":   [.zh: "创建新群组", .en: "Create Group"],
        "groups.name":     [.zh: "群组名称", .en: "Group name"],
        "groups.members":  [.zh: "选择成员", .en: "Select members"],
        "groups.confirm":  [.zh: "创建", .en: "Create"],
        // Discover
        "discover.title":  [.zh: "发现", .en: "Discover"],
        "discover.elite":  [.zh: "精英服务", .en: "Elite Services"],
        "discover.join":   [.zh: "加入", .en: "JOIN"],
        // Settings
        "settings.title":     [.zh: "设置", .en: "Settings"],
        "settings.switched":  [.zh: "流动模式", .en: "Switched mode"],
        "settings.clash":     [.zh: "冲突模式", .en: "Clash Mode"],
        "settings.sliders":   [.zh: "滑块", .en: "Sliders"],
        "settings.scheme":    [.zh: "滑块配色", .en: "Sliders scheme"],
        "settings.selected":  [.zh: "选择配色", .en: "Selected scheme"],
        "settings.language":  [.zh: "语言", .en: "Language"],
        // Profile / contact
        "profile.title":   [.zh: "个人资料", .en: "Profile"],
        "profile.company": [.zh: "团队公司", .en: "Company of Teams"],
        "profile.edit":    [.zh: "编辑", .en: "Edit"],
        // Footer
        "footer.connectivity": [.zh: "已连接", .en: "Connectivity"],
        "footer.quick":        [.zh: "快捷访问", .en: "Quick access"],
        "search.placeholder":  [.zh: "搜索", .en: "Search"],
    ]
}
