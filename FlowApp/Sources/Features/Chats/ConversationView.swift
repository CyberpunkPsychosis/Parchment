import SwiftUI

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

    private var myId: Int? { auth.user?.id }
    private var aiMembers: [ConvMemberDTO] { members.filter { $0.is_ai } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { m in
                            ConvBubble(msg: m, myId: myId, isGroup: conversation.is_group).id(m.id)
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
                Button { runSuggest() } label: { Label(loc.t("conv.smartReply"), systemImage: "wand.and.stars") }
                if conversation.is_group {
                    Button { runSummarize() } label: { Label(loc.t("conv.summarize"), systemImage: "list.bullet.rectangle") }
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
struct ConvBubble: View {
    let msg: MessageDTO
    let myId: Int?
    let isGroup: Bool

    private var mine: Bool { msg.sender_user_id != nil && msg.sender_user_id == myId }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if mine { Spacer(minLength: 48) }
            if !mine { Avatar(initials: msg.sender_avatar, tint: msg.senderColor, size: 34) }
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
