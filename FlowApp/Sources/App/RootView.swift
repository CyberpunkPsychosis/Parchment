import SwiftUI

enum FlowTab: String, CaseIterable {
    case chats, groups, discover, profile, settings
    var icon: String {
        switch self {
        case .chats:    return "bubble.left.fill"
        case .groups:   return "person.2.fill"
        case .discover: return "safari.fill"
        case .profile:  return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }
    var key: String { "nav.\(rawValue)" }
}

struct RootView: View {
    @EnvironmentObject var loc: Localization
    @State private var tab: FlowTab = .chats

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tab {
                case .chats:    ChatListView()
                case .groups:   GroupsView()
                case .discover: DiscoverView()
                case .profile:  ProfileView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FlowTabBar(tab: $tab)
            StatusFooter()
        }
        .background(PaperBackground())
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

/// Decorative status strip from the design board (Connectivity • 100% • Quick access).
struct StatusFooter: View {
    @EnvironmentObject var loc: Localization
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi").font(.system(size: 11))
            Text(loc.t("footer.connectivity")).font(FlowTheme.caption(11))
            Spacer()
            Text("100%").font(FlowTheme.caption(11))
            Image(systemName: "battery.100").font(.system(size: 11))
            Spacer()
            HStack(spacing: 4) {
                Avatar(initials: "AC", tint: FlowTheme.teal, size: 16)
                Text(loc.t("footer.quick")).font(FlowTheme.caption(11))
                Image(systemName: "chevron.up").font(.system(size: 8))
            }
        }
        .foregroundStyle(FlowTheme.gray)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(FlowTheme.parchment)
    }
}
