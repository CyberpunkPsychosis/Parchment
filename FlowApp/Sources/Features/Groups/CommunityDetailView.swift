import SwiftUI

/// 社群详情：信息 + 成员列表 + （未加入时）加入。
struct CommunityDetailView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let group: PlazaGroup
    var onChanged: () -> Void = {}

    @State private var detail: PlazaGroup?
    @State private var joining = false
    @State private var toast: String?
    @State private var route: ConversationDTO?

    private var g: PlazaGroup { detail ?? group }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Avatar(initials: g.avatar, tint: g.tintColor, size: 84, seed: 7).padding(.top, 20)
                    VStack(spacing: 5) {
                        Text(g.name).font(FlowTheme.heading(22)).foregroundStyle(FlowTheme.ink)
                        Text("\(loc.t("market.by"))\(g.owner_name) · \(loc.t(g.modeKey))")
                            .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    }

                    if !g.description.isEmpty {
                        Card { Text(g.description).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                            .padding(.horizontal, 16)
                    }

                    // 成员
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(loc.t("community.members"))（\(g.member_count)/\(g.member_cap)）")
                                .font(FlowTheme.heading(16)).foregroundStyle(FlowTheme.ink)
                            ForEach(g.members ?? [], id: \.name) { m in
                                HStack(spacing: 10) {
                                    Avatar(initials: m.initials, tint: FlowTheme.teal, size: 34)
                                    Text(m.name).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                    if m.is_owner {
                                        Text(loc.t("community.owner")).font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Capsule().fill(FlowTheme.teal))
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)

                    // 加入
                    if !g.is_member {
                        if g.join_mode == "code" {
                            Text(loc.t("community.codeOnly")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                        } else {
                            Button(action: join) {
                                ZStack {
                                    PrimaryButton(title: loc.t(g.join_mode == "approval" ? "group.apply" : "group.join"))
                                        .opacity(joining || g.pending ? 0.6 : 1)
                                    if joining { ProgressView().tint(.white) }
                                }
                            }
                            .disabled(joining || g.pending)
                            .padding(.horizontal, 16)
                        }
                        if g.pending {
                            Text(loc.t("group.pending")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                        }
                    } else {
                        Text(loc.t("group.joined")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.teal)
                    }
                    Spacer(minLength: 24)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(FlowTheme.ink)
            }.padding(16)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(FlowTheme.ink.opacity(0.85))).padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { conv in ConversationView(conversation: conv) }
        .task { detail = try? await APIClient.shared.groupDetail(id: group.id) }
    }

    private func join() {
        joining = true
        Task {
            if let r = try? await APIClient.shared.joinGroup(id: group.id) {
                if r.pending == true {
                    await MainActor.run { toast = loc.t("group.appliedToast") }
                    detail = try? await APIClient.shared.groupDetail(id: group.id)
                    onChanged()
                } else {
                    // 加入成功 → 直接进群聊
                    onChanged()
                    if let conv = try? await APIClient.shared.openGroupConversation(groupId: group.id) {
                        await MainActor.run { route = conv }
                    }
                }
            }
            joining = false
        }
    }
}
