import SwiftUI

/// 真实会话聊天页（私聊 / 群聊）。REST 拉历史 + 发送，WebSocket 实时收。
/// 群聊渲染发送者头像与名字。AI 搭子进群在阶段 4 接入。
struct ConversationView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    let conversation: ConversationDTO
    @State private var messages: [MessageDTO] = []
    @State private var draft = ""
    @State private var sending = false

    private var myId: Int? { auth.user?.id }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { m in
                            ConvBubble(msg: m, myId: myId, isGroup: conversation.is_group).id(m.id)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .background(ChatBackground())
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
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
    }

    private func load() async {
        if let ms = try? await APIClient.shared.listMessages(conversationId: conversation.id) {
            await MainActor.run { messages = ms }
        }
        try? await APIClient.shared.markConversationRead(conversationId: conversation.id)
    }

    private func appendUnique(_ m: MessageDTO) {
        if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        draft = ""; sending = true
        Task {
            let m = try? await APIClient.shared.sendMessage(conversationId: conversation.id, content: text)
            await MainActor.run {
                if let m { appendUnique(m) }
                sending = false
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(FlowTheme.ink)
            }
            Avatar(initials: conversation.avatar, tint: conversation.tintColor, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                if conversation.is_group {
                    Text("\(conversation.member_count) \(loc.t("conv.members"))")
                        .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                } else {
                    HStack(spacing: 5) { OnlineDot(); Text(loc.t("status.online")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .bottom))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack {
                TextField(loc.t("chat.placeholder"), text: $draft)
                    .font(FlowTheme.body(15))
                    .onSubmit { send() }
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
                if isGroup && !mine {
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
            AsyncImage(url: URL(string: msg.content)) { img in
                img.resizable().scaledToFill()
            } placeholder: { FlowTheme.beige }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .sketchBorder(16, width: 1.4, seed: UInt64(msg.id))
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
