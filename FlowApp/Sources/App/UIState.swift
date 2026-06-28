import SwiftUI

/// 跨视图的 UI 状态。进入聊天详情时隐藏底部 Tab 栏。
final class UIState: ObservableObject {
    @Published var hideTabBar = false
    @Published var unreadTotal = 0   // 聊天 Tab 未读红点
}
