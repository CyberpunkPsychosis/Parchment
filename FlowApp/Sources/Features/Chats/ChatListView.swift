import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var ui: UIState
    @State private var showProfile = false
    @State private var showFriends = false
    @State private var showCreateGroup = false
    @State private var showAddFriend = false
    @State private var showSearch = false
    @State private var conversations: [ConversationDTO] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if loaded && conversations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(conversations.enumerated()), id: \.element.id) { idx, conv in
                                NavigationLink(value: conv) {
                                    ChatRowView(chat: conv.asSummary, seed: UInt64(idx + 1),
                                                pinned: conv.pinned ?? false, muted: conv.muted ?? false)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { act { try await APIClient.shared.togglePin(conversationId: conv.id) } } label: {
                                        Label(loc.t((conv.pinned ?? false) ? "conv.unpin" : "conv.pin"), systemImage: "pin")
                                    }
                                    Button { act { try await APIClient.shared.toggleMute(conversationId: conv.id) } } label: {
                                        Label(loc.t((conv.muted ?? false) ? "conv.unmute" : "conv.mute"), systemImage: "bell.slash")
                                    }
                                    Button(role: .destructive) { act { try await APIClient.shared.leaveConversation(conv.id) } } label: {
                                        Label(loc.t("conv.delete"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .background(PaperBackground())
            .navigationDestination(for: ConversationDTO.self) { conv in
                ConversationView(conversation: conv)
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .flowMessage)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView().environmentObject(loc).environmentObject(auth)
        }
        .sheet(isPresented: $showFriends) { ContactsView() }
        .sheet(isPresented: $showCreateGroup) { CreateGroupView { _ in Task { await reload() } } }
        .sheet(isPresented: $showAddFriend) { AddFriendView() }
        .sheet(isPresented: $showSearch) { SearchView() }
    }

    private func reload() async {
        if let cs = try? await APIClient.shared.listConversations() {
            await MainActor.run {
                conversations = cs; loaded = true
                ui.unreadTotal = cs.reduce(0) { $0 + $1.unread }
            }
        } else {
            await MainActor.run { loaded = true }
        }
    }

    /// 执行一个会话操作后刷新列表。
    private func act(_ op: @escaping () async throws -> Void) {
        Task { try? await op(); await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            Text(loc.t("chats.empty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profileInitials: String {
        let name = auth.user?.nickname ?? "U"
        return String(name.prefix(name.first.map { $0.isASCII ? 2 : 1 } ?? 1)).uppercased()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { showProfile = true } label: {
                Avatar(initials: profileInitials, tint: FlowTheme.teal, size: 38, seed: 7, imageURL: auth.user?.avatar_url)
            }
            Text(loc.t("chats.title"))
                .font(FlowTheme.title(30))
                .foregroundStyle(FlowTheme.ink)
            Spacer()
            Menu {
                Button { showFriends = true } label: { Label(loc.t("new.chat"), systemImage: "bubble.left") }
                Button { showCreateGroup = true } label: { Label(loc.t("new.group"), systemImage: "person.3") }
                Button { showAddFriend = true } label: { Label(loc.t("friends.add"), systemImage: "person.badge.plus") }
                Button { showSearch = true } label: { Label(loc.t("new.search"), systemImage: "magnifyingglass") }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(FlowTheme.ink)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

struct ChatRowView: View {
    let chat: ChatSummary
    var seed: UInt64 = 1
    var pinned: Bool = false
    var muted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(initials: chat.initials, tint: chat.tint, size: 46, imageURL: chat.imageURL)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(chat.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FlowTheme.ink)
                        .lineLimit(1)
                    if muted { Image(systemName: "bell.slash.fill").font(.system(size: 10)).foregroundStyle(FlowTheme.gray) }
                    if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(FlowTheme.teal) }
                }
                Text(chat.preview)
                    .font(FlowTheme.caption(13))
                    .foregroundStyle(FlowTheme.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(chat.time)
                    .font(FlowTheme.caption(11))
                    .foregroundStyle(FlowTheme.gray)
                if chat.unread > 0 {
                    Text("\(chat.unread)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(FlowTheme.teal))
                } else {
                    HStack(spacing: 2) {
                        Circle().fill(FlowTheme.gray.opacity(0.5)).frame(width: 5, height: 5)
                        Circle().fill(FlowTheme.gray.opacity(0.5)).frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .sketchCard(18, fill: FlowTheme.card, seed: seed)
    }
}
