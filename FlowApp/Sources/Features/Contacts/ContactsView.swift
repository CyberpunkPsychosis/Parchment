import SwiftUI

/// Sketch-bordered checkbox used in member selection.
struct CheckBox: View {
    let checked: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(checked ? FlowTheme.teal : FlowTheme.field)
            .frame(width: 23, height: 23)
            .overlay {
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
            }
            .sketchBorder(6, width: 1.2, seed: checked ? 60 : 61)
    }
}

/// 好友列表：真实数据。点好友进私聊；可加好友、处理好友申请。
struct ContactsView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    @State private var friends: [FriendUser] = []
    @State private var requests: [IncomingRequest] = []
    @State private var route: ConversationDTO?
    @State private var showAdd = false
    @State private var showRequests = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(loc.t("friends.title")).font(FlowTheme.heading(22)).foregroundStyle(FlowTheme.ink)
                    Spacer()
                    Button { showAdd = true } label: {
                        Image(systemName: "person.badge.plus").font(.system(size: 18)).foregroundStyle(FlowTheme.teal)
                    }
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
                }
                .padding(20)

                if !requests.isEmpty {
                    Button { showRequests = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(FlowTheme.teal)
                            Text(loc.t("friends.requests")).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                            Spacer()
                            Text("\(requests.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).background(Circle().fill(FlowTheme.teal))
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(FlowTheme.gray)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .sketchCard(16, fill: FlowTheme.card, seed: 75)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 8)
                }

                if loaded && friends.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "person.2").font(.system(size: 30)).foregroundStyle(FlowTheme.gray.opacity(0.6))
                        Text(loc.t("friends.empty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                        Spacer()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(friends.enumerated()), id: \.element.id) { idx, f in
                                Button { openDM(f) } label: {
                                    HStack(spacing: 11) {
                                        Avatar(initials: f.initials, tint: f.tintColor, size: 40, seed: UInt64(idx + 80), imageURL: f.avatar_url)
                                        Text(f.nickname).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                        Spacer()
                                        Image(systemName: "bubble.left").font(.system(size: 14)).foregroundStyle(FlowTheme.gray)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .sketchCard(16, fill: FlowTheme.card, seed: UInt64(idx + 90))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 6)
                    }
                }
            }
            .background(PaperBackground())
            .navigationDestination(item: $route) { conv in ConversationView(conversation: conv) }
        }
        .task { await reload() }
        .sheet(isPresented: $showAdd) { AddFriendView { Task { await reload() } } }
        .sheet(isPresented: $showRequests) { FriendRequestsView { Task { await reload() } } }
    }

    private func reload() async {
        let f = (try? await APIClient.shared.listFriends()) ?? []
        let r = (try? await APIClient.shared.listFriendRequests()) ?? []
        await MainActor.run { friends = f; requests = r; loaded = true }
    }

    private func openDM(_ f: FriendUser) {
        Task {
            if let conv = try? await APIClient.shared.openDirect(peerUserId: f.id) {
                await MainActor.run { route = conv }
            }
        }
    }
}

/// 搜索用户并发好友申请。
struct AddFriendView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    var onChanged: () -> Void = {}

    @State private var q = ""
    @State private var results: [FriendUser] = []
    @State private var sent: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("friends.add")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }
            .padding(20)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(FlowTheme.gray)
                TextField(loc.t("friends.searchHint"), text: $q)
                    .font(FlowTheme.body(15)).onSubmit { search() }
                if !q.isEmpty { Button { q = ""; results = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(FlowTheme.gray) } }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
            .sketchBorder(14, width: 1.4, seed: 70)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { idx, u in
                        HStack(spacing: 11) {
                            Avatar(initials: u.initials, tint: u.tintColor, size: 40, seed: UInt64(idx + 110), imageURL: u.avatar_url)
                            Text(u.nickname).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                            Spacer()
                            actionButton(u)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .sketchCard(16, fill: FlowTheme.card, seed: UInt64(idx + 120))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            Spacer(minLength: 8)
        }
        .background(PaperBackground())
    }

    @ViewBuilder private func actionButton(_ u: FriendUser) -> some View {
        if u.is_friend {
            Text(loc.t("friend.isFriend")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
        } else if u.outgoing_pending || sent.contains(u.id) {
            Text(loc.t("friend.pending")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
        } else {
            Button {
                sent.insert(u.id)
                Task { try? await APIClient.shared.sendFriendRequest(toUserId: u.id); onChanged() }
            } label: { PillButton(title: loc.t("friend.add"), radius: 14, seed: UInt64(u.id)) }
        }
    }

    private func search() {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { results = []; return }
        Task {
            let r = try? await APIClient.shared.searchUsers(query)
            await MainActor.run { results = r ?? [] }
        }
    }
}

/// 收到的好友申请。
struct FriendRequestsView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    var onChanged: () -> Void = {}

    @State private var requests: [IncomingRequest] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("friends.requests")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }
            .padding(20)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(requests.enumerated()), id: \.element.id) { idx, r in
                        HStack(spacing: 11) {
                            Avatar(initials: r.initials, tint: r.tintColor, size: 40, seed: UInt64(idx + 130))
                            Text(r.nickname).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                            Spacer()
                            Button {
                                Task { try? await APIClient.shared.acceptFriendRequest(id: r.id); reloadAfter(r.id) }
                            } label: { PillButton(title: loc.t("friend.accept"), radius: 14, seed: UInt64(r.id)) }
                            Button {
                                Task { try? await APIClient.shared.rejectFriendRequest(id: r.id); reloadAfter(r.id) }
                            } label: { Image(systemName: "xmark.circle").foregroundStyle(FlowTheme.gray) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .sketchCard(16, fill: FlowTheme.card, seed: UInt64(idx + 140))
                    }
                }
                .padding(20)
            }
            Spacer(minLength: 8)
        }
        .background(PaperBackground())
        .task { requests = (try? await APIClient.shared.listFriendRequests()) ?? [] }
    }

    private func reloadAfter(_ id: Int) {
        requests.removeAll { $0.id == id }
        onChanged()
    }
}
