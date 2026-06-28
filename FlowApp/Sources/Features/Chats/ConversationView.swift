import SwiftUI
import PhotosUI

/// 真实会话聊天页（私聊 / 群聊）。REST 拉历史 + 发送，WebSocket 实时收。
/// 群聊渲染发送者头像与名字，支持加入 AI 搭子、@搭子回复、群聊总结、智能回复。
struct ConversationView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    let conversation: ConversationDTO
    @State private var messages: [MessageDTO] = []
    @State private var members: [ConvMemberDTO] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var aiBusy = false
    @State private var suggestions: [String] = []
    @State private var summary: String?
    @State private var showAddAI = false
    @State private var showShareCompanion = false
    @State private var showMembers = false
    @State private var photoItem: PhotosPickerItem?
    @State private var profileRef: UserRef?

    private var myId: Int? { auth.user?.id }
    private var aiMembers: [ConvMemberDTO] { members.filter { $0.is_ai } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { m in
                            ConvBubble(msg: m, myId: myId, isGroup: conversation.is_group,
                                       onAvatarTap: { uid in profileRef = UserRef(id: uid) }).id(m.id)
                        }
                        if aiBusy { HStack { ProgressView().tint(FlowTheme.teal); Spacer() }.padding(.leading, 8) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .background(ChatBackground())
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if !suggestions.isEmpty { suggestionBar }
            if !aiMembers.isEmpty { aiBar }
            inputBar
        }
        .background(PaperBackground())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .flowMessage)) { note in
            guard let m = note.object as? MessageDTO, m.conversation_id == conversation.id else { return }
            appendUnique(m)
            Task { try? await APIClient.shared.markConversationRead(conversationId: conversation.id) }
        }
        .onAppear { ui.hideTabBar = true }
        .onDisappear { ui.hideTabBar = false }
        .sheet(isPresented: $showAddAI) { CompanionPickerView { id in addCompanion(id) } }
        .sheet(isPresented: $showShareCompanion) { CompanionPickerView { id in shareCompanion(id) } }
        .sheet(isPresented: $showMembers) {
            GroupMembersView(conversation: conversation, myId: myId, onLeave: { dismiss() })
        }
        .sheet(item: $profileRef) { ref in UserProfileView(userId: ref.id) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let url = try? await APIClient.shared.uploadImage(data),
                   let m = try? await APIClient.shared.sendMessage(conversationId: conversation.id, kind: "image", content: url) {
                    await MainActor.run { appendUnique(m) }
                }
                await MainActor.run { photoItem = nil }
            }
        }
        .sheet(item: Binding(get: { summary.map { SummaryBox(text: $0) } }, set: { if $0 == nil { summary = nil } })) { box in
            SummarySheet(text: box.text)
        }
    }

    // MARK: 数据

    private func load() async {
        if let ms = try? await APIClient.shared.listMessages(conversationId: conversation.id) {
            await MainActor.run { messages = ms }
        }
        if let mem = try? await APIClient.shared.conversationMembers(conversation.id) {
            await MainActor.run { members = mem }
        }
        try? await APIClient.shared.markConversationRead(conversationId: conversation.id)
    }

    private func appendUnique(_ m: MessageDTO) {
        if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        draft = ""; sending = true; suggestions = []
        Task {
            let m = try? await APIClient.shared.sendMessage(conversationId: conversation.id, content: text)
            await MainActor.run { if let m { appendUnique(m) }; sending = false }
            // 私聊里如果有 AI 搭子，自动让它接话
            if conversation.type == "companion" || (!conversation.is_group && aiMembers.count == 1),
               let only = aiMembers.first?.companion_id {
                await summon(only)
            }
        }
    }

    private func summon(_ companionId: Int) async {
        await MainActor.run { aiBusy = true }
        let m = try? await APIClient.shared.aiReply(conversationId: conversation.id, companionId: companionId)
        await MainActor.run { if let m { appendUnique(m) }; aiBusy = false }
    }

    private func shareCompanion(_ id: Int) {
        Task {
            if let m = try? await APIClient.shared.shareCompanion(conversationId: conversation.id, companionId: id) {
                await MainActor.run { appendUnique(m) }
            }
        }
    }

    private func addCompanion(_ id: Int) {
        Task {
            try? await APIClient.shared.addCompanionToConversation(conversation.id, companionId: id)
            if let mem = try? await APIClient.shared.conversationMembers(conversation.id) {
                await MainActor.run { members = mem }
            }
            await summon(id)  // 加完让它先打个招呼
        }
    }

    private func recentDTOs() -> [ChatMessageDTO] {
        messages.suffix(20).compactMap { m in
            guard m.kind == "text" else { return nil }
            return ChatMessageDTO(role: m.sender_user_id == myId ? "user" : "assistant", content: m.content)
        }
    }

    private func runSummarize() {
        Task {
            if let s = try? await APIClient.shared.summarize(messages: recentDTOs()) {
                await MainActor.run { summary = s }
            }
        }
    }

    private func runSuggest() {
        Task {
            if let s = try? await APIClient.shared.replySuggest(messages: recentDTOs()) {
                await MainActor.run { suggestions = s }
            }
        }
    }

    // MARK: 子视图

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(FlowTheme.ink)
            }
            Avatar(initials: conversation.avatar, tint: conversation.tintColor, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                if conversation.is_group {
                    Text("\(members.count) \(loc.t("conv.members"))").font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                } else {
                    HStack(spacing: 5) { OnlineDot(); Text(loc.t("status.online")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray) }
                }
            }
            Spacer()
            Menu {
                Button { showAddAI = true } label: { Label(loc.t("conv.addAI"), systemImage: "sparkles") }
                Button { showShareCompanion = true } label: { Label(loc.t("conv.shareCompanion"), systemImage: "person.crop.rectangle") }
                Button { runSuggest() } label: { Label(loc.t("conv.smartReply"), systemImage: "wand.and.stars") }
                if conversation.is_group {
                    Button { runSummarize() } label: { Label(loc.t("conv.summarize"), systemImage: "list.bullet.rectangle") }
                    Button { showMembers = true } label: { Label(loc.t("conv.members.manage"), systemImage: "person.2") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(FlowTheme.ink)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .bottom))
    }

    private var aiBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(aiMembers) { m in
                    Button { if let cid = m.companion_id { Task { await summon(cid) } } } label: {
                        HStack(spacing: 6) {
                            Avatar(initials: m.initials, tint: m.tintColor, size: 22)
                            Text("\(loc.t("conv.summon"))\(m.name)").font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.teal)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(FlowTheme.teal.opacity(0.1)))
                    }
                    .disabled(aiBusy)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .background(FlowTheme.parchment)
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { draft = s; suggestions = [] } label: {
                        Text(s).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(FlowTheme.card)).sketchBorder(20, width: 1, seed: 88)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .background(FlowTheme.parchment)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(FlowTheme.gray)
            }
            HStack {
                TextField(loc.t("chat.placeholder"), text: $draft).font(FlowTheme.body(15)).onSubmit { send() }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.9)))
            .sketchBorder(22, width: 1.4, seed: 42)

            Button { send() } label: { PillButton(title: loc.t("chat.send"), radius: 22, seed: 41) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
    }
}

private struct SummaryBox: Identifiable { let id = UUID(); let text: String }

private struct SummarySheet: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(loc.t("conv.summary")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }
            ScrollView { Text(text).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(20).background(PaperBackground())
    }
}

/// 选一个自己的搭子加入会话。
struct CompanionPickerView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    var onPick: (Int) -> Void

    @State private var companions: [Companion] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("conv.addAI")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }.padding(20)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(companions.enumerated()), id: \.element.id) { idx, c in
                        Button { onPick(c.id); dismiss() } label: {
                            HStack(spacing: 11) {
                                Avatar(initials: c.avatar, tint: c.tintColor, size: 40, seed: UInt64(idx + 150))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                    Text(c.persona).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(FlowTheme.teal)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .sketchCard(16, fill: FlowTheme.card, seed: UInt64(idx + 160))
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(20)
            }
        }
        .background(PaperBackground())
        .task { companions = (try? await APIClient.shared.listCompanions()) ?? [] }
    }
}

/// 会话气泡：群聊时为他人显示头像 + 名字。
struct UserRef: Identifiable { let id: Int }

struct ConvBubble: View {
    let msg: MessageDTO
    let myId: Int?
    let isGroup: Bool
    var onAvatarTap: ((Int) -> Void)? = nil

    private var mine: Bool { msg.sender_user_id != nil && msg.sender_user_id == myId }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if mine { Spacer(minLength: 48) }
            if !mine {
                let av = Avatar(initials: msg.sender_avatar, tint: msg.senderColor, size: 34)
                if let uid = msg.sender_user_id, !msg.is_ai {
                    Button { onAvatarTap?(uid) } label: { av }.buttonStyle(.plain)
                } else { av }
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if (isGroup || msg.is_ai) && !mine {
                    Text(msg.sender_name).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                }
                bubble
                Text(msg.shortTime).font(FlowTheme.caption(9)).foregroundStyle(FlowTheme.ink.opacity(0.5))
            }
            if !mine { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder private var bubble: some View {
        switch msg.kind {
        case "image", "sticker":
            AsyncImage(url: URL(string: msg.content)) { img in img.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
            .frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 16)).sketchBorder(16, width: 1.4, seed: UInt64(msg.id))
        case "companion":
            CompanionCard(json: msg.content)
        case "system":
            Text(msg.content).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
        default:
            Text(msg.content)
                .font(FlowTheme.body(15))
                .foregroundStyle(mine ? FlowTheme.sageInk : FlowTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .sketchCard(18, fill: mine ? FlowTheme.sage : Color(hex: 0xFCFAF4), seed: UInt64(msg.id))
        }
    }
}

/// AI 搭子名片消息卡片（kind=companion）。
struct CompanionCard: View {
    let json: String
    private var info: (name: String, avatar: String, tint: String, persona: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return ("搭子", "AI", "teal", "")
        }
        return (o["name"] as? String ?? "搭子", o["avatar"] as? String ?? "AI",
                o["tint"] as? String ?? "teal", o["persona"] as? String ?? "")
    }
    var body: some View {
        let i = info
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(initials: i.avatar, tint: FlowTheme.tint(i.tint), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                    Text("🤖 AI 搭子名片").font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                }
            }
            if !i.persona.isEmpty {
                Text(i.persona).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray).lineLimit(3)
            }
        }
        .padding(14).frame(width: 220, alignment: .leading)
        .sketchCard(16, fill: Color(hex: 0xFCFAF4), seed: UInt64(abs(json.hashValue % 1000)))
    }
}

/// 群成员管理：列成员，群主可移除，任何人可退群。
struct GroupMembersView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationDTO
    let myId: Int?
    var onLeave: () -> Void = {}

    @State private var members: [ConvMemberDTO] = []

    private var amOwner: Bool { members.first { $0.user_id == myId }?.role == "owner" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("conv.members.manage")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }.padding(20)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 11) {
                            Avatar(initials: m.initials, tint: m.tintColor, size: 38, seed: UInt64(idx + 210))
                            Text(m.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                            if m.role == "owner" {
                                Text(loc.t("community.owner")).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(FlowTheme.teal))
                            }
                            if m.is_ai {
                                Text("AI").font(.system(size: 10, weight: .bold)).foregroundStyle(FlowTheme.teal)
                                    .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(FlowTheme.teal.opacity(0.15)))
                            }
                            Spacer()
                            if amOwner && m.role != "owner" {
                                Button { remove(m) } label: { Image(systemName: "minus.circle").foregroundStyle(FlowTheme.gray) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .sketchCard(16, fill: FlowTheme.card, seed: UInt64(idx + 220))
                    }
                }.padding(.horizontal, 20)
            }

            Button { leave() } label: {
                Text(loc.t("conv.leave")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.4), lineWidth: 1.3))
            }.padding(20)
        }
        .background(PaperBackground())
        .task { members = (try? await APIClient.shared.conversationMembers(conversation.id)) ?? [] }
    }

    private func remove(_ m: ConvMemberDTO) {
        Task {
            try? await APIClient.shared.removeMember(conversation.id, userId: m.user_id, companionId: m.companion_id)
            members = (try? await APIClient.shared.conversationMembers(conversation.id)) ?? []
        }
    }
    private func leave() {
        Task {
            try? await APIClient.shared.leaveConversation(conversation.id)
            await MainActor.run { dismiss(); onLeave() }
        }
    }
}
