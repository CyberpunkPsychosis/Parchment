import SwiftUI

/// 全局搜索：好友 / 群组社群 / 可认领搭子。
struct SearchView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss

    @State private var q = ""
    @State private var results = SearchResults()
    @State private var profileRef: UserRef?
    @State private var convRoute: ConversationDTO?
    @State private var groupRoute: PlazaGroup?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(FlowTheme.gray)
                    TextField(loc.t("search.hint"), text: $q).font(FlowTheme.body(15)).onSubmit { run() }
                    Button { dismiss() } label: { Text(loc.t("common.cancel")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field)).sketchBorder(14, width: 1.3, seed: 70)
                .padding(.horizontal, 16).padding(.top, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !results.users.isEmpty { section(loc.t("search.friends")) {
                            ForEach(results.users) { u in
                                row(initials: u.initials, tint: u.tintColor, url: u.avatar_url, title: u.nickname, sub: nil) {
                                    profileRef = UserRef(id: u.id)
                                }
                            }
                        }}
                        if !results.groups.isEmpty { section(loc.t("search.groups")) {
                            ForEach(results.groups) { g in
                                row(initials: g.avatar, tint: g.tintColor, url: nil, title: g.name,
                                    sub: "\(g.member_count)\(loc.t("conv.members"))") { openGroup(g) }
                            }
                        }}
                        if !results.companions.isEmpty { section(loc.t("search.companions")) {
                            ForEach(results.companions) { c in
                                HStack(spacing: 11) {
                                    Avatar(initials: c.avatar, tint: c.tintColor, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                        Text(c.persona).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray).lineLimit(1)
                                    }
                                    Spacer()
                                    Button { adopt(c) } label: { PillButton(title: loc.t("market.adopt"), radius: 14, seed: UInt64(c.id)) }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .sketchCard(16, fill: FlowTheme.card, seed: UInt64(c.id + 300))
                            }
                        }}
                    }
                    .padding(16)
                }
            }
            .background(PaperBackground())
            .navigationDestination(item: $convRoute) { c in ConversationView(conversation: c) }
            .navigationDestination(item: $groupRoute) { g in CommunityDetailView(group: g) }
            .sheet(item: $profileRef) { ref in UserProfileView(userId: ref.id) }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(FlowTheme.ink.opacity(0.85))).padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            content()
        }
    }

    private func row(initials: String, tint: Color, url: String?, title: String, sub: String?, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 11) {
                Avatar(initials: initials, tint: tint, size: 40, imageURL: url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                    if let sub { Text(sub).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(FlowTheme.gray)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .sketchCard(16, fill: FlowTheme.card, seed: UInt64(abs(title.hashValue % 900) + 1))
        }
        .buttonStyle(.plain)
    }

    private func run() {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { results = SearchResults(); return }
        Task { let r = try? await APIClient.shared.search(query); await MainActor.run { results = r ?? SearchResults() } }
    }

    private func openGroup(_ g: SearchGroup) {
        Task {
            if g.is_member, let conv = try? await APIClient.shared.openGroupConversation(groupId: g.id) {
                await MainActor.run { convRoute = conv }
            } else if let detail = try? await APIClient.shared.groupDetail(id: g.id) {
                await MainActor.run { groupRoute = detail }
            }
        }
    }

    private func adopt(_ c: SearchCompanion) {
        Task {
            _ = try? await APIClient.shared.adopt(snapshotId: c.snapshot_id)
            await MainActor.run { showToast(loc.t("market.adopted")) }
            NotificationCenter.default.post(name: .flowCompanionsChanged, object: nil)
        }
    }

    private func showToast(_ t: String) {
        withAnimation { toast = t }
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); await MainActor.run { withAnimation { toast = nil } } }
    }
}
