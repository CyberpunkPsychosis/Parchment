import SwiftUI

/// 他人主页：资料 + 加好友 / 私聊 + 其公开的 AI 搭子。
struct UserProfileView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    let userId: Int
    @State private var user: FriendUser?
    @State private var route: ConversationDTO?
    @State private var requested = false
    @State private var showReport = false
    @State private var reportReason = ""
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let u = user {
                        Avatar(initials: u.initials, tint: u.tintColor, size: 84, seed: 7, imageURL: u.avatar_url).padding(.top, 24)
                        if let bio = u.bio, !bio.isEmpty {
                            Text(bio).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray).multilineTextAlignment(.center).padding(.horizontal, 30)
                        }
                        Text(u.nickname).font(FlowTheme.heading(22)).foregroundStyle(FlowTheme.ink)

                        if !u.is_me {
                            HStack(spacing: 12) {
                                Button { dm(u) } label: { PillButton(title: loc.t("profile.message"), radius: 18, seed: 1) }
                                if u.is_friend {
                                    Text(loc.t("friend.isFriend")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                } else if u.outgoing_pending || requested {
                                    Text(loc.t("friend.pending")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                } else {
                                    Button { addFriend(u) } label: {
                                        Text(loc.t("friend.add")).font(.system(size: 13, weight: .semibold)).foregroundStyle(FlowTheme.teal)
                                            .padding(.horizontal, 16).padding(.vertical, 9)
                                            .background(Capsule().fill(FlowTheme.teal.opacity(0.12)))
                                    }
                                }
                            }
                        }

                        if let comps = u.companions, !comps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(loc.t("profile.companions")).font(FlowTheme.heading(16)).foregroundStyle(FlowTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ForEach(Array(comps.enumerated()), id: \.element.id) { idx, c in
                                    HStack(spacing: 11) {
                                        Avatar(initials: c.avatar, tint: c.tintColor, size: 38, seed: UInt64(idx + 170))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                            Text(c.persona).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .sketchCard(16, fill: FlowTheme.card, seed: UInt64(idx + 180))
                                }
                            }
                            .padding(.horizontal, 16).padding(.top, 8)
                        }
                        Spacer(minLength: 24)
                    } else {
                        ProgressView().tint(FlowTheme.teal).padding(.top, 60)
                    }
                }
            }
            .background(PaperBackground())
            .navigationDestination(item: $route) { conv in ConversationView(conversation: conv) }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }.padding(16)
            }
            .overlay(alignment: .topLeading) {
                if let u = user, !u.is_me {
                    Menu {
                        Button(role: .destructive) { block(u) } label: { Label(loc.t("safety.block"), systemImage: "hand.raised") }
                        Button { showReport = true } label: { Label(loc.t("safety.report"), systemImage: "exclamationmark.bubble") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(FlowTheme.gray)
                    }.padding(16)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(FlowTheme.ink.opacity(0.85))).padding(.bottom, 30)
                }
            }
            .alert(loc.t("safety.report"), isPresented: $showReport) {
                TextField(loc.t("safety.reportReason"), text: $reportReason)
                Button(loc.t("safety.submit")) { submitReport() }
                Button(loc.t("common.cancel"), role: .cancel) { reportReason = "" }
            }
        }
        .task { user = try? await APIClient.shared.userProfile(userId) }
    }

    private func block(_ u: FriendUser) {
        Task {
            try? await APIClient.shared.blockUser(u.id)
            await MainActor.run { toast = loc.t("safety.blocked") }
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { dismiss() }
        }
    }

    private func submitReport() {
        let reason = reportReason; reportReason = ""
        Task {
            try? await APIClient.shared.report(targetType: "user", targetId: userId, reason: reason)
            await MainActor.run { toast = loc.t("safety.reported") }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { if toast == loc.t("safety.reported") { toast = nil } }
        }
    }

    private func dm(_ u: FriendUser) {
        Task { if let c = try? await APIClient.shared.openDirect(peerUserId: u.id) { await MainActor.run { route = c } } }
    }
    private func addFriend(_ u: FriendUser) {
        requested = true
        Task { try? await APIClient.shared.sendFriendRequest(toUserId: u.id) }
    }
}
