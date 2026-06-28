import SwiftUI

/// 跨视图的 UI 状态。进入聊天详情时隐藏底部 Tab 栏。
final class UIState: ObservableObject {
    @Published var hideTabBar = false
    @Published var unreadTotal = 0   // 聊天 Tab 未读红点
    // 群组 / 发现 Tab 当前子页签（长按 Tab 可设默认，存 UserDefaults）
    @Published var groupsSection: Int
    @Published var discoverSection: Int

    init() {
        groupsSection = UserDefaults.standard.integer(forKey: FlowTab.groups.defaultSubKey)
        discoverSection = UserDefaults.standard.integer(forKey: FlowTab.discover.defaultSubKey)
    }
}
