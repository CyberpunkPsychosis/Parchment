import SwiftUI

enum FlowTab: String, CaseIterable {
    case chats, companions, groups, discover, settings
    var icon: String {
        switch self {
        case .chats:      return "bubble.left.fill"
        case .companions: return "sparkles"
        case .groups:     return "person.2.fill"
        case .discover:   return "safari.fill"
        case .settings:   return "gearshape.fill"
        }
    }
    var key: String { "nav.\(rawValue)" }
}

struct RootView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var ui: UIState
    @State private var tab: FlowTab = .chats

    var body: some View {
        // 所有页签常驻内存，用透明度切换，避免切走再回来时 @State(会话/输入)被销毁
        ZStack {
            tabContent(.chats) { ChatListView() }
            tabContent(.companions) { CompanionsView() }
            tabContent(.groups) { GroupsView() }
            tabContent(.discover) { DiscoverView() }
            tabContent(.settings) { SettingsView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 菜单作为底部安全区 inset：收起时内容区（含聊天输入栏）跟着平滑下移，联动一致
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !ui.hideTabBar {
                VStack(spacing: 0) {
                    FlowTabBar(tab: $tab)
                    StatusFooter()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(PaperBackground())
        .animation(.easeInOut(duration: 0.28), value: ui.hideTabBar)
    }

    /// 常驻渲染每个页签，仅用透明度/命中测试切换可见性（保活 @State）。
    @ViewBuilder
    private func tabContent<V: View>(_ t: FlowTab, @ViewBuilder _ view: () -> V) -> some View {
        view()
            .opacity(tab == t ? 1 : 0)
            .allowsHitTesting(tab == t)
            .zIndex(tab == t ? 1 : 0)
    }
}

struct FlowTabBar: View {
    @EnvironmentObject var loc: Localization
    @Binding var tab: FlowTab

    var body: some View {
        HStack {
            ForEach(FlowTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(loc.t(t.key))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == t ? FlowTheme.teal : FlowTheme.gray)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            FlowTheme.card
                .overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top)
        )
    }
}

/// 底部装饰状态条（设计稿原样：已连接 • 100% • 快捷访问）。
struct StatusFooter: View {
    @EnvironmentObject var loc: Localization
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi").font(.system(size: 11))
            Text(loc.t("footer.connectivity")).font(FlowTheme.caption(11))
            Spacer()
            Text("100%").font(FlowTheme.caption(11))
            Image(systemName: "battery.100").font(.system(size: 11))
        }
        .foregroundStyle(FlowTheme.gray)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(FlowTheme.parchment)
    }
}
