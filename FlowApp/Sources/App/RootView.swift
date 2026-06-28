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

    /// 该 Tab 的子页签（用于长按设默认）。无子页签返回 []。
    var subTabs: [(id: Int, key: String)] {
        switch self {
        case .groups:   return [(0, "groups.seg.groups"), (1, "groups.seg.communities")]
        case .discover: return [(0, "disc.market"), (1, "disc.groups"), (2, "disc.moments")]
        default:        return []
        }
    }

    /// 存"默认子页签"的 UserDefaults key。
    var defaultSubKey: String { "flow.defaultSub.\(rawValue)" }
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
    @EnvironmentObject var ui: UIState
    @Binding var tab: FlowTab

    var body: some View {
        HStack {
            ForEach(FlowTab.allCases, id: \.self) { t in
                Button { selectTab(t) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon)
                            .font(.system(size: 18, weight: .medium))
                            .overlay(alignment: .topTrailing) {
                                if t == .chats && ui.unreadTotal > 0 {
                                    Text(ui.unreadTotal > 99 ? "99+" : "\(ui.unreadTotal)")
                                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(.red)).offset(x: 12, y: -6)
                                }
                            }
                        Text(loc.t(t.key))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == t ? FlowTheme.teal : FlowTheme.gray)
                    .frame(maxWidth: .infinity)
                }
                .contextMenu {
                    if !t.subTabs.isEmpty {
                        Section(loc.t("tab.setDefault")) {
                            ForEach(t.subTabs, id: \.id) { sub in
                                Button { setDefaultSub(t, sub.id) } label: {
                                    Label(loc.t(sub.key),
                                          systemImage: UserDefaults.standard.integer(forKey: t.defaultSubKey) == sub.id ? "checkmark" : "circle")
                                }
                            }
                        }
                    }
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

    /// 切到某 Tab：若有子页签，落到用户设定的默认子页签。
    private func selectTab(_ t: FlowTab) {
        tab = t
        applyDefaultSub(t)
    }

    private func applyDefaultSub(_ t: FlowTab) {
        let d = UserDefaults.standard.integer(forKey: t.defaultSubKey)
        switch t {
        case .groups:   ui.groupsSection = d
        case .discover: ui.discoverSection = d
        default: break
        }
    }

    /// 长按选定：记住为默认子页签，并立即跳过去。
    private func setDefaultSub(_ t: FlowTab, _ id: Int) {
        UserDefaults.standard.set(id, forKey: t.defaultSubKey)
        tab = t
        switch t {
        case .groups:   ui.groupsSection = id
        case .discover: ui.discoverSection = id
        default: break
        }
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
