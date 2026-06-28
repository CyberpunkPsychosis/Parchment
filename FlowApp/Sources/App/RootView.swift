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
    @State private var showAssistant = false

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
                    StatusFooter(onTap: { showAssistant = true })
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(PaperBackground())
        .animation(.easeInOut(duration: 0.28), value: ui.hideTabBar)
        .sheet(isPresented: $showAssistant) { AssistantView().environmentObject(loc) }
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

/// 底部「羊皮纸助手」入口条：点开能用自然语言在站内办事。
struct StatusFooter: View {
    @EnvironmentObject var loc: Localization
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(FlowTheme.teal)
                Text(loc.t("assistant.entry")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                Spacer()
                Image(systemName: "chevron.up").font(.system(size: 10)).foregroundStyle(FlowTheme.gray.opacity(0.7))
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(FlowTheme.parchment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
