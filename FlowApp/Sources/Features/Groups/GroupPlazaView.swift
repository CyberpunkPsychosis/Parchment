import SwiftUI

/// 社群列表：mineOnly=false 为"社群广场(全部)"，true 为"我加入的社群"。点卡片进详情。
struct GroupPlazaView: View {
    @EnvironmentObject var loc: Localization
    var mineOnly: Bool = false

    @State private var groups: [PlazaGroup] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var showCodeAlert = false
    @State private var codeInput = ""
    @State private var toast: String?

    var body: some View {
        ScrollView {
            if !mineOnly {
                HStack(spacing: 10) {
                    actionChip(icon: "plus", title: loc.t("group.create")) { showCreate = true }
                    actionChip(icon: "number", title: loc.t("group.byCode")) { codeInput = ""; showCodeAlert = true }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
            }

            if loading {
                ProgressView().tint(FlowTheme.teal).padding(.top, 40)
            } else if groups.isEmpty {
                Text(loc.t(mineOnly ? "community.mineEmpty" : "market.empty"))
                    .font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray).padding(.top, 40)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                        NavigationLink(value: g) { groupCard(g, seed: UInt64(idx + 300)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showCreate) {
            CreatePlazaGroupView { _ in Task { await load() } }.environmentObject(loc)
        }
        .alert(loc.t("group.byCode"), isPresented: $showCodeAlert) {
            TextField(loc.t("group.codeHint"), text: $codeInput)
            Button(loc.t("group.join")) { joinByCode() }
            Button(loc.t("common.cancel"), role: .cancel) {}
        }
        .task { await load() }
    }

    private func actionChip(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: icon); Text(title).font(FlowTheme.caption(13).weight(.medium)) }
                .foregroundStyle(FlowTheme.teal)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.teal.opacity(0.1)))
                .sketchBorder(14, width: 1.2, seed: icon == "plus" ? 71 : 72)
        }
    }

    private func groupCard(_ g: PlazaGroup, seed: UInt64) -> some View {
        Card(seed: seed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Avatar(initials: g.avatar, tint: g.tintColor, size: 46, seed: seed)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(g.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                        Text("\(g.member_count)/\(g.member_cap) · \(loc.t(g.modeKey))")
                            .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                    }
                    Spacer()
                    if g.is_member { miniChip(loc.t("group.joined")) }
                    else if g.pending { miniChip(loc.t("group.pending")) }
                    else { Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray) }
                }
                if !g.description.isEmpty {
                    Text(g.description).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    private func miniChip(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(FlowTheme.gray)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(FlowTheme.beige.opacity(0.6)))
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(FlowTheme.ink.opacity(0.85)))
                    .padding(.bottom, 20).transition(.opacity)
            }
        }
    }

    private func load() async {
        loading = true
        groups = (try? await (mineOnly ? APIClient.shared.myGroups() : APIClient.shared.groupPlaza())) ?? []
        loading = false
    }

    private func joinByCode() {
        let c = codeInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !c.isEmpty else { return }
        Task {
            do {
                let g = try await APIClient.shared.joinGroupByCode(code: c)
                await MainActor.run { showToast("\(loc.t("group.joinedToast"))\(g.name)") }
                await load()
            } catch {
                await MainActor.run { showToast(loc.t("group.codeInvalid")) }
            }
        }
    }

    private func showToast(_ t: String) {
        withAnimation { toast = t }
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); await MainActor.run { withAnimation { toast = nil } } }
    }
}
