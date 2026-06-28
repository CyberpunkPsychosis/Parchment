import SwiftUI
import PhotosUI
import UIKit

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
    @State private var showAddAI = false
    @State private var showShareCompanion = false
    @State private var showMembers = false
    @State private var photoItem: PhotosPickerItem?
    @State private var profileRef: UserRef?
    @State private var typingName: String?
    @State private var mentionQuery: String?
    @State private var levelUpToast: String?
    @State private var headerGrowth: CompanionGrowth?
    @State private var replyingTo: MessageDTO?
    @State private var forwardingMsg: MessageDTO?
    @StateObject private var recorder = AudioRecorder()
    @State private var showBgPicker = false

    private var myId: Int? { auth.user?.id }
    private var aiMembers: [ConvMemberDTO] { members.filter { $0.is_ai } }

    /// 输入 @ 后的候选成员（含搭子），按当前查询前缀过滤。
    private var mentionCandidates: [ConvMemberDTO] {
        guard let q = mentionQuery else { return [] }
        let pool = members.filter { $0.user_id != myId }   // 排除自己，包含 AI 搭子
        guard !q.isEmpty else { return pool }
        let lq = q.lowercased()
        return pool.filter { $0.name.lowercased().contains(lq) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { idx, m in
                            if idx == 0 || messages[idx - 1].day != m.day {
                                Text(m.day).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.ink.opacity(0.45))
                                    .padding(.vertical, 4)
                            }
                            ConvBubble(msg: m, myId: myId, isGroup: conversation.is_group,
                                       onAvatarTap: { uid in profileRef = UserRef(id: uid) },
                                       onRecall: { recall(m) },
                                       onReact: { e in react(m, e) },
                                       onReply: { replyingTo = m },
                                       onForward: { forwardingMsg = m }).id(m.id)
                        }
                        if let typingName { Text("\(typingName) \(loc.t("chat.typing"))").font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray).frame(maxWidth: .infinity, alignment: .leading) }
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
            if mentionQuery != nil && !mentionCandidates.isEmpty { mentionBar }
            inputBar
        }
        .background(PaperBackground())
        .overlay(alignment: .top) {
            if let levelUpToast {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13))
                    Text(levelUpToast).font(FlowTheme.caption(13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(FlowTheme.teal))
                .padding(.top, 70)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: levelUpToast)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .flowMessage)) { note in
            guard let m = note.object as? MessageDTO, m.conversation_id == conversation.id else { return }
            appendUnique(m); typingName = nil
            Task { try? await APIClient.shared.markConversationRead(conversationId: conversation.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowRecall)) { note in
            guard let e = note.object as? SocketEnvelope, e.conversation_id == conversation.id, let mid = e.message_id else { return }
            messages.removeAll { $0.id == mid }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowReaction)) { note in
            guard let e = note.object as? SocketEnvelope, e.conversation_id == conversation.id, let mid = e.message_id,
                  let i = messages.firstIndex(where: { $0.id == mid }) else { return }
            messages[i].reactions = e.reactions
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowTyping)) { note in
            guard let e = note.object as? SocketEnvelope, e.conversation_id == conversation.id else { return }
            typingName = e.name
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); await MainActor.run { if typingName == e.name { typingName = nil } } }
        }
        .onChange(of: draft) { _, v in
            if !v.isEmpty { ChatSocket.shared.sendTyping(conversationId: conversation.id) }
            updateMention(v)
        }
        .onAppear { ui.hideTabBar = true }
        .onDisappear { ui.hideTabBar = false }
        .sheet(isPresented: $showAddAI) { CompanionPickerView { id in addCompanion(id) } }
        .sheet(isPresented: $showShareCompanion) { CompanionPickerView { id in shareCompanion(id) } }
        .sheet(isPresented: $showMembers) {
            GroupMembersView(conversation: conversation, myId: myId, onLeave: { dismiss() })
        }
        .sheet(item: $profileRef) { ref in UserProfileView(userId: ref.id) }
        .sheet(item: $forwardingMsg) { m in
            ForwardPickerView(excludeId: conversation.id) { convId in forward(m, to: convId) }
                .environmentObject(loc)
        }
        .sheet(isPresented: $showBgPicker) { ChatBackgroundPicker().environmentObject(loc) }
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
    }

    // MARK: 数据

    private func load() async {
        if let ms = try? await APIClient.shared.listMessages(conversationId: conversation.id) {
            await MainActor.run { messages = ms }
        }
        if let mem = try? await APIClient.shared.conversationMembers(conversation.id) {
            await MainActor.run { members = mem }
        }
        // 单搭子会话：拉取其当前等级用于头部展示
        if let cid = aiMembers.count == 1 ? aiMembers.first?.companion_id : nil,
           let comps = try? await APIClient.shared.listCompanions(),
           let c = comps.first(where: { $0.id == cid }) {
            await MainActor.run {
                headerGrowth = CompanionGrowth(exp: c.exp, level: c.level, stage: c.stage,
                                               level_min_exp: c.level_min_exp, level_max_exp: c.level_max_exp)
            }
        }
        try? await APIClient.shared.markConversationRead(conversationId: conversation.id)
    }

    private func appendUnique(_ m: MessageDTO) {
        if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        let replyId = replyingTo?.id
        draft = ""; sending = true; suggestions = []; mentionQuery = nil; replyingTo = nil
        Task {
            let m = try? await APIClient.shared.sendMessage(conversationId: conversation.id, content: text, replyToId: replyId)
            await MainActor.run { if let m { appendUnique(m) }; sending = false }
            // 私聊里如果有 AI 搭子，自动让它接话
            if conversation.type == "companion" || (!conversation.is_group && aiMembers.count == 1),
               let only = aiMembers.first?.companion_id {
                await summon(only)
            } else if conversation.is_group {
                // 群里 @ 了某个搭子 → 让它接话（可同时 @ 多个）
                for ai in aiMembers where text.contains("@\(ai.name)") {
                    if let cid = ai.companion_id { await summon(cid) }
                }
            }
        }
    }

    /// 解析草稿末尾的 @token：最后一个 @ 之后若无空格则进入提示模式。
    private func updateMention(_ text: String) {
        guard conversation.is_group, let at = text.lastIndex(of: "@") else { mentionQuery = nil; return }
        let after = text[text.index(after: at)...]
        if after.contains(where: { $0 == " " || $0 == "\n" }) { mentionQuery = nil; return }
        mentionQuery = String(after)
    }

    /// 选中候选 → 用 @名称 替换草稿末尾的 @token。
    private func insertMention(_ name: String) {
        if let at = draft.lastIndex(of: "@") {
            draft = String(draft[..<at]) + "@\(name) "
        } else {
            draft += "@\(name) "
        }
        mentionQuery = nil
    }

    /// 松开麦克风：停止录音→上传→发送语音消息。
    private func finishRecording() {
        guard let (url, secs) = recorder.stop() else { return }
        Task {
            guard let data = try? Data(contentsOf: url) else { return }
            if let remote = try? await APIClient.shared.uploadAudio(data),
               let m = try? await APIClient.shared.sendMessage(
                    conversationId: conversation.id, kind: "voice", content: "\(remote)|\(secs)") {
                await MainActor.run { appendUnique(m) }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 转发：把原消息内容发到所选会话。
    private func forward(_ m: MessageDTO, to convId: Int) {
        Task {
            _ = try? await APIClient.shared.sendMessage(conversationId: convId, kind: m.kind, content: m.content)
            await MainActor.run { forwardingMsg = nil }
        }
    }

    private func summon(_ companionId: Int) async {
        await MainActor.run { aiBusy = true }
        let m = try? await APIClient.shared.aiReply(conversationId: conversation.id, companionId: companionId)
        await MainActor.run {
            if let m {
                appendUnique(m)
                if let g = m.companion_growth { headerGrowth = g }
                if m.leveled_up == true, let g = m.companion_growth {
                    showLevelUp("\(m.sender_name) \(loc.t("growth.levelUp")) Lv.\(g.level) · \(g.stage)")
                }
            }
            aiBusy = false
        }
    }

    private func showLevelUp(_ text: String) {
        levelUpToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            await MainActor.run { if levelUpToast == text { levelUpToast = nil } }
        }
    }

    private func recall(_ m: MessageDTO) {
        Task {
            try? await APIClient.shared.recallMessage(m.id)
            await MainActor.run { messages.removeAll { $0.id == m.id } }
        }
    }

    private func react(_ m: MessageDTO, _ emoji: String) {
        Task { try? await APIClient.shared.reactMessage(m.id, emoji: emoji) }
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
            Avatar(initials: conversation.avatar, tint: conversation.tintColor, size: 38, imageURL: conversation.avatar_url)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(conversation.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                    if let g = headerGrowth {
                        LevelBadge(level: g.level, stage: g.stage, tint: conversation.tintColor)
                    }
                }
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
                Button { showBgPicker = true } label: { Label(loc.t("bg.title"), systemImage: "photo.on.rectangle") }
                Button { runSuggest() } label: { Label(loc.t("conv.smartReply"), systemImage: "wand.and.stars") }
                if conversation.is_group {
                    Button { showMembers = true } label: { Label(loc.t("conv.members.manage"), systemImage: "person.2") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(FlowTheme.ink)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .bottom))
    }

    /// @ 自动提示面板：输入 @ 后实时显示候选成员/搭子，点选补全。
    private var mentionBar: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(mentionCandidates) { m in
                    Button { insertMention(m.name) } label: {
                        HStack(spacing: 10) {
                            Avatar(initials: m.initials, tint: m.tintColor, size: 28)
                            Text(m.name).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                            if m.is_ai {
                                Text(loc.t("conv.aiTag")).font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(FlowTheme.teal))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 180)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
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
        VStack(spacing: 0) {
            if let r = replyingTo { replyingBanner(r) }
            if recorder.isRecording { recordingBanner }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(FlowTheme.gray)
                }
                // 长按麦克风录音，松手发送
                Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20)).foregroundStyle(recorder.isRecording ? FlowTheme.teal : FlowTheme.gray)
                    .scaleEffect(recorder.isRecording ? 1.2 : 1)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !recorder.isRecording { recorder.start() } }
                            .onEnded { _ in finishRecording() }
                    )
                HStack {
                    TextField(loc.t("chat.placeholder"), text: $draft).font(FlowTheme.body(15)).onSubmit { send() }
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.9)))
                .sketchBorder(22, width: 1.4, seed: 42)

                Button { send() } label: { PillButton(title: loc.t("chat.send"), radius: 22, seed: 41) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
    }

    private func replyingBanner(_ r: MessageDTO) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(FlowTheme.teal).frame(width: 2.5, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(loc.t("chat.replyingTo"))\(r.sender_name)").font(.system(size: 11, weight: .semibold)).foregroundStyle(FlowTheme.teal)
                Text(r.kind == "text" ? r.content : (r.kind == "voice" ? "[语音]" : "[图片]"))
                    .font(.system(size: 11)).foregroundStyle(FlowTheme.gray).lineLimit(1)
            }
            Spacer()
            Button { replyingTo = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(FlowTheme.parchment)
    }

    private var recordingBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("\(loc.t("chat.recording")) \(Int(recorder.elapsed))s").font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.ink)
            Spacer()
            Text(loc.t("chat.releaseToSend")).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(FlowTheme.parchment)
    }
}

/// 转发目标选择器：选一个会话把消息转过去。
struct ForwardPickerView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let excludeId: Int
    var onPick: (Int) -> Void
    @State private var conversations: [ConversationDTO] = []

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                Text(loc.t("chat.forwardTo")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink).padding(.vertical, 16)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(conversations.filter { $0.id != excludeId }) { c in
                            Button { onPick(c.id); dismiss() } label: {
                                HStack(spacing: 12) {
                                    Avatar(initials: c.avatar, tint: c.tintColor, size: 40, imageURL: c.avatar_url)
                                    Text(c.title).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .sketchCard(14, fill: FlowTheme.card, seed: UInt64(c.id + 20))
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }.padding(16)
        }
        .task { conversations = (try? await APIClient.shared.listConversations()) ?? [] }
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
    var onRecall: () -> Void = {}
    var onReact: (String) -> Void = {}
    var onReply: () -> Void = {}
    var onForward: () -> Void = {}

    private let quickEmojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    private var mine: Bool { msg.sender_user_id != nil && msg.sender_user_id == myId }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if mine { Spacer(minLength: 48) }
            if !mine {
                let av = Avatar(initials: msg.sender_avatar, tint: msg.senderColor, size: 34, imageURL: msg.sender_avatar_url)
                if let uid = msg.sender_user_id, !msg.is_ai {
                    Button { onAvatarTap?(uid) } label: { av }.buttonStyle(.plain)
                } else { av }
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if (isGroup || msg.is_ai) && !mine {
                    Text(msg.sender_name).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if let rs = msg.reply_to { replyQuote(rs) }
                    bubble
                }
                .contextMenu {
                    if msg.kind == "text" { Button { UIPasteboard.general.string = msg.content } label: { Label("复制 Copy", systemImage: "doc.on.doc") } }
                    Button { onReply() } label: { Label("引用 Reply", systemImage: "arrowshape.turn.up.left") }
                    if msg.kind == "text" || msg.kind == "image" { Button { onForward() } label: { Label("转发 Forward", systemImage: "arrowshape.turn.up.right") } }
                    Menu { ForEach(quickEmojis, id: \.self) { e in Button(e) { onReact(e) } } } label: { Label("回应 React", systemImage: "face.smiling") }
                    if mine { Button(role: .destructive) { onRecall() } label: { Label("撤回 Recall", systemImage: "arrow.uturn.backward") } }
                }
                if let rs = msg.reactions, !rs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(rs, id: \.emoji) { r in
                            Text("\(r.emoji)\(r.count)").font(.system(size: 11))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(FlowTheme.beige))
                        }
                    }
                }
                Text(msg.shortTime).font(FlowTheme.caption(9)).foregroundStyle(FlowTheme.ink.opacity(0.5))
            }
            if !mine { Spacer(minLength: 48) }
        }
    }

    /// 引用的原消息摘要（气泡上方）。
    private func replyQuote(_ rs: ReplySummary) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(FlowTheme.teal.opacity(0.6)).frame(width: 2.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(rs.sender_name).font(.system(size: 10, weight: .semibold)).foregroundStyle(FlowTheme.teal)
                Text(rs.snippet).font(.system(size: 11)).foregroundStyle(FlowTheme.gray).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(FlowTheme.ink.opacity(0.05)))
        .frame(maxWidth: 220, alignment: .leading)
    }

    @ViewBuilder private var bubble: some View {
        switch msg.kind {
        case "image", "sticker":
            AsyncImage(url: URL(string: msg.content)) { img in img.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
            .frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 16)).sketchBorder(16, width: 1.4, seed: UInt64(msg.id))
        case "voice":
            VoiceMessageBubble(content: msg.content, mine: mine, seed: UInt64(msg.id))
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

/// AI 搭子名片消息卡片（kind=companion）。已发布的可一键认领。
struct CompanionCard: View {
    @EnvironmentObject var loc: Localization
    let json: String
    @State private var adopted = false

    private var o: [String: Any] {
        (json.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    }
    var body: some View {
        let name = o["name"] as? String ?? "搭子"
        let avatar = o["avatar"] as? String ?? "AI"
        let tint = o["tint"] as? String ?? "teal"
        let persona = o["persona"] as? String ?? ""
        let snapshot = o["snapshot_id"] as? Int
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(initials: avatar, tint: FlowTheme.tint(tint), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                    Text("🤖 AI 搭子名片").font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                }
            }
            if !persona.isEmpty {
                Text(persona).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray).lineLimit(3)
            }
            if let sid = snapshot {
                Button {
                    adopted = true
                    Task { _ = try? await APIClient.shared.adopt(snapshotId: sid) }
                } label: {
                    Text(loc.t(adopted ? "market.adopted" : "market.adopt"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.teal))
                }
                .disabled(adopted)
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
    @State private var showEdit = false
    @State private var showInvite = false
    @State private var announcement = ""
    @State private var profileRef: UserRef?

    private var amOwner: Bool { members.first { $0.user_id == myId }?.role == "owner" }
    private var countSuffix: String {
        let humans = members.filter { !$0.is_ai }.count
        if let cap = conversation.member_cap { return " \(humans)/\(cap)" }
        return " \(humans)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("conv.members.manage") + countSuffix).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }.padding(20)

            if !announcement.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "megaphone").foregroundStyle(FlowTheme.teal).font(.system(size: 13))
                    Text(announcement).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .sketchCard(14, fill: FlowTheme.teal.opacity(0.08), seed: 77)
                .padding(.horizontal, 20).padding(.bottom, 10)
            }

            if amOwner {
                HStack(spacing: 10) {
                    Button { showEdit = true } label: {
                        Label(loc.t("group.edit"), systemImage: "square.and.pencil").font(FlowTheme.caption(13))
                    }
                    Button { showInvite = true } label: {
                        Label(loc.t("group.invite"), systemImage: "person.badge.plus").font(FlowTheme.caption(13))
                    }
                    Spacer()
                }
                .foregroundStyle(FlowTheme.teal)
                .padding(.horizontal, 20).padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 11) {
                            Avatar(initials: m.initials, tint: m.tintColor, size: 38, seed: UInt64(idx + 210), imageURL: m.avatar_url)
                            if let uid = m.user_id, !m.is_ai, uid != myId {
                                Button { profileRef = UserRef(id: uid) } label: {
                                    Text(m.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                }.buttonStyle(.plain)
                            } else {
                                Text(m.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                            }
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
        .task { announcement = conversation.announcement ?? ""; await reload() }
        .sheet(isPresented: $showEdit) { GroupEditView(conversation: conversation) { c in announcement = c.announcement ?? "" } }
        .sheet(isPresented: $showInvite) { InviteFriendsView(conversation: conversation, existing: Set(members.compactMap { $0.user_id })) { Task { await reload() } } }
        .sheet(item: $profileRef) { ref in UserProfileView(userId: ref.id) }
    }

    private func reload() async {
        members = (try? await APIClient.shared.conversationMembers(conversation.id)) ?? []
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

/// 群主编辑群信息：群名 / 头像 / 公告。
struct GroupEditView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationDTO
    var onSaved: (ConversationDTO) -> Void = { _ in }

    @State private var title = ""
    @State private var announcement = ""
    @State private var avatarURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Text(loc.t("common.cancel")).foregroundStyle(FlowTheme.gray) }
                Spacer()
                Text(loc.t("group.edit")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { save() } label: { Text(loc.t("profile.save")).fontWeight(.semibold).foregroundStyle(FlowTheme.teal) }
            }.padding(20)

            ScrollView {
                VStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Avatar(initials: title.isEmpty ? "群" : String(title.prefix(1)), tint: FlowTheme.teal, size: 84, seed: 7, imageURL: avatarURL)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: uploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                                    .font(.system(size: 12)).foregroundStyle(.white).padding(6).background(Circle().fill(FlowTheme.teal))
                            }
                    }.padding(.top, 8)
                    field(loc.t("groups.name"), text: $title, seed: 33)
                    field(loc.t("group.announcement"), text: $announcement, seed: 34)
                }.padding(.horizontal, 20)
            }
        }
        .background(PaperBackground())
        .onAppear { title = conversation.title; announcement = conversation.announcement ?? ""; avatarURL = conversation.avatar_url }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            uploading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let url = try? await APIClient.shared.uploadImage(data) { await MainActor.run { avatarURL = url } }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
    }

    private func field(_ t: String, text: Binding<String>, seed: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            TextField(t, text: text).font(FlowTheme.body(16))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field)).sketchBorder(14, width: 1.3, seed: seed)
        }
    }

    private func save() {
        Task {
            if let c = try? await APIClient.shared.updateConversation(conversation.id, title: title,
                                                                      avatar: avatarURL ?? "", announcement: announcement) {
                await MainActor.run { onSaved(c); dismiss() }
            }
        }
    }
}

/// 邀请好友进群（排除已在群里的）。
struct InviteFriendsView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationDTO
    let existing: Set<Int>
    var onInvited: () -> Void = {}

    @State private var friends: [FriendUser] = []
    @State private var selected: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("group.invite")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }.padding(20)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { idx, f in
                        Button {
                            if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                        } label: {
                            HStack(spacing: 11) {
                                Avatar(initials: f.initials, tint: f.tintColor, size: 38, seed: UInt64(idx + 230), imageURL: f.avatar_url)
                                Text(f.nickname).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                Spacer()
                                CheckBox(checked: selected.contains(f.id))
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }
            Button { invite() } label: { PrimaryButton(title: loc.t("groups.confirm")) }
                .disabled(selected.isEmpty).opacity(selected.isEmpty ? 0.6 : 1).padding(20)
        }
        .background(PaperBackground())
        .task { friends = ((try? await APIClient.shared.listFriends()) ?? []).filter { !existing.contains($0.id) } }
    }

    private func invite() {
        Task {
            for id in selected { try? await APIClient.shared.addUserToConversation(conversation.id, userId: id) }
            await MainActor.run { onInvited(); dismiss() }
        }
    }
}
