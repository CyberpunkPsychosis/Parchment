import SwiftUI

/// 群组 = 好友内部私群；社群 = 公开社群（发现页可加入）。两段分开。
struct GroupsView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var ui: UIState
    @State private var showCreate = false
    @State private var showContacts = false
    @State private var friendGroups: [ConversationDTO] = []
    @State private var loaded = false
    @State private var route: ConversationDTO?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text(loc.t("groups.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                    Spacer()
                    Button { showContacts = true } label: {
                        Image(systemName: "person.2").font(.system(size: 20)).foregroundStyle(FlowTheme.ink)
                    }
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(FlowTheme.teal)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

                Picker("", selection: $ui.groupsSection) {
                    Text(loc.t("groups.seg.groups")).tag(0)
                    Text(loc.t("groups.seg.communities")).tag(1)
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)

                if ui.groupsSection == 0 { friendGroupList } else { GroupPlazaView(mineOnly: true, entersChat: true) }
            }
            .background(PaperBackground())
            .navigationDestination(item: $route) { conv in ConversationView(conversation: conv) }
        }
        .task { await loadFriendGroups() }
        .onReceive(NotificationCenter.default.publisher(for: .flowMessage)) { _ in Task { await loadFriendGroups() } }
        .sheet(isPresented: $showCreate) {
            if ui.groupsSection == 0 {
                CreateGroupView { conv in route = conv; Task { await loadFriendGroups() } }
            } else {
                CreatePlazaGroupView { _ in }.environmentObject(loc)
            }
        }
        .sheet(isPresented: $showContacts) { ContactsView() }
    }

    // 好友内部群 = group 类型且未挂社群(group_id == nil)
    private var friendGroupList: some View {
        Group {
            if loaded && friendGroups.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "person.3").font(.system(size: 30)).foregroundStyle(FlowTheme.gray.opacity(0.6))
                    Text(loc.t("groups.friendEmpty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(friendGroups.enumerated()), id: \.element.id) { idx, conv in
                            Button { route = conv } label: { ChatRowView(chat: conv.asSummary, seed: UInt64(idx + 50)) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadFriendGroups() async {
        let all = (try? await APIClient.shared.listConversations()) ?? []
        await MainActor.run {
            friendGroups = all.filter { $0.type == "group" && $0.group_id == nil }
            loaded = true
        }
    }
}

/// 用好友建内部群（真实会话）。
struct CreateGroupView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    var onCreated: (ConversationDTO) -> Void = { _ in }

    @State private var name = ""
    @State private var friends: [FriendUser] = []
    @State private var selected: Set<Int> = []
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("groups.create")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(loc.t("groups.name")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    TextField(loc.t("groups.name"), text: $name)
                        .font(FlowTheme.body(16))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: FlowTheme.cornerField).fill(FlowTheme.field))
                        .sketchBorder(FlowTheme.cornerField, width: 1.4, seed: 62)

                    Text(loc.t("groups.members")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    if friends.isEmpty {
                        Text(loc.t("friends.empty")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(friends.enumerated()), id: \.element.id) { idx, f in
                            Button {
                                if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(initials: f.initials, tint: f.tintColor, size: 38, seed: UInt64(idx + 200), imageURL: f.avatar_url)
                                    Text(f.nickname).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                    Spacer()
                                    CheckBox(checked: selected.contains(f.id))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Button { create() } label: { PrimaryButton(title: loc.t("groups.confirm")) }
                .disabled(creating || selected.isEmpty)
                .opacity(selected.isEmpty ? 0.6 : 1)
                .padding(20)
        }
        .background(PaperBackground())
        .task { friends = (try? await APIClient.shared.listFriends()) ?? [] }
    }

    private func create() {
        guard !selected.isEmpty, !creating else { return }
        creating = true
        let title = name.trimmingCharacters(in: .whitespaces)
        Task {
            let conv = try? await APIClient.shared.createFriendGroup(name: title, memberIds: Array(selected))
            await MainActor.run {
                creating = false
                if let conv { onCreated(conv); dismiss() }
            }
        }
    }
}
