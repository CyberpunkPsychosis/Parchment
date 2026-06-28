import SwiftUI
import PhotosUI
import UIKit

/// 会话页的弹窗集合：用单个 enum 驱动一个 .sheet(item:)，避免同视图多 .sheet 互相吞掉。
private enum ConvSheet: Identifiable {
    case addAI, shareCompanion, members, bgPicker
    case profile(Int)              // 用户 id
    case forward(MessageDTO)
    case memories(Int)             // 搭子 id
    case editCompanion(Companion)

    var id: String {
        switch self {
        case .addAI: return "addAI"
        case .shareCompanion: return "shareCompanion"
        case .members: return "members"
        case .bgPicker: return "bgPicker"
        case .profile(let uid): return "profile-\(uid)"
        case .forward(let m): return "forward-\(m.id)"
        case .memories(let cid): return "memories-\(cid)"
        case .editCompanion(let c): return "edit-\(c.id)"
        }
    }
}

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
    @State private var photoItem: PhotosPickerItem?
    @State private var typingName: String?
    @State private var mentionQuery: String?
    @State private var levelUpToast: String?
    @State private var headerGrowth: CompanionGrowth?
    @State private var replyingTo: MessageDTO?
    @StateObject private var recorder = AudioRecorder()
    @State private var voiceMode = false
    // SwiftUI 同一视图挂多个 .sheet 只生效部分，靠后的会被吞；统一用一个 enum 驱动
    @State private var activeSheet: ConvSheet?

    private var myId: Int? { auth.user?.id }
    private var aiMembers: [ConvMemberDTO] { members.filter { $0.is_ai } }
    /// 搭子 1:1 会话对应的搭子 id（优先用会话自带的，避免依赖成员列表是否已加载）。
    private var companionId: Int? {
        guard conversation.type == "companion" else { return nil }
        return conversation.companion_id ?? aiMembers.first?.companion_id
    }
    /// 认领来的搭子：锁定记忆/人设（保留惊喜感）。
    private var isAdoptedCompanion: Bool {
        conversation.type == "companion" && (conversation.companion_adopted || (aiMembers.first?.adopted ?? false))
    }

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
                                       onAvatarTap: { uid in activeSheet = .profile(uid) },
                                       onRecall: { recall(m) },
                                       onReact: { e in react(m, e) },
                                       onReply: { replyingTo = m },
                                       onForward: { activeSheet = .forward(m) }).id(m.id)
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
        .overlay { VoiceRecordingHUD(recorder: recorder) }
        .animation(.easeOut(duration: 0.15), value: recorder.isRecording)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addAI:
                CompanionPickerView { id in addCompanion(id) }
            case .shareCompanion:
                CompanionPickerView { id in shareCompanion(id) }
            case .members:
                GroupMembersView(conversation: conversation, myId: myId, onLeave: { dismiss() })
            case .profile(let uid):
                UserProfileView(userId: uid)
            case .forward(let m):
                ForwardPickerView(excludeId: conversation.id) { convId in forward(m, to: convId) }
                    .environmentObject(loc)
            case .bgPicker:
                ChatBackgroundPicker().environmentObject(loc)
            case .memories(let cid):
                MemoriesView(companionId: cid, companionName: conversation.title).environmentObject(loc)
            case .editCompanion(let c):
                CreateCompanionView(editing: c) { _ in }.environmentObject(loc)
            }
        }
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
            // 搭子 1:1：自动让它接话（用会话自带的 companionId，不依赖成员列表是否已加载）
            if conversation.type == "companion", let only = companionId {
                await summon(only)
            } else if !conversation.is_group, aiMembers.count == 1, let only = aiMembers.first?.companion_id {
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

    /// 打开「编辑搭子」：按 companionId 取回完整搭子对象再进编辑页（认领的也能改）。
    private func openEditCompanion() {
        guard let cid = companionId else { return }
        Task {
            let list = (try? await APIClient.shared.listCompanions()) ?? []
            if let c = list.first(where: { $0.id == cid }) {
                await MainActor.run { activeSheet = .editCompanion(c) }
            }
        }
    }

    /// 上传并发送一条语音消息（录音已由 HoldToTalkBar 停止）。
    private func sendVoice(url: URL, secs: Int) {
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
            await MainActor.run { activeSheet = nil }
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
                    showLevelUp("\(m.sender_name) \(loc.t("growth.levelUp")) Lv.\(g.level)")
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
                        LevelBadge(level: g.level, tint: conversation.tintColor)
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
                if conversation.type == "companion" {
                    // 搭子 1:1：给搭子专属菜单。认领来的搭子锁定记忆/人设（保留惊喜感），不显示这两项
                    if !isAdoptedCompanion {
                        if let cid = companionId {
                            Button { activeSheet = .memories(cid) } label: { Label(loc.t("memories.title"), systemImage: "brain.head.profile") }
                        }
                        Button { openEditCompanion() } label: { Label(loc.t("companion.edit"), systemImage: "pencil") }
                    }
                    Button { activeSheet = .bgPicker } label: { Label(loc.t("bg.title"), systemImage: "photo.on.rectangle") }
                    Button { runSuggest() } label: { Label(loc.t("conv.smartReply"), systemImage: "wand.and.stars") }
                } else {
                    // 加搭子只在群里有意义；和真人 1:1 私聊不该把 AI 塞进去
                    if conversation.is_group {
                        Button { activeSheet = .addAI } label: { Label(loc.t("conv.addAI"), systemImage: "sparkles") }
                    }
                    Button { activeSheet = .shareCompanion } label: { Label(loc.t("conv.shareCompanion"), systemImage: "person.crop.rectangle") }
                    Button { activeSheet = .bgPicker } label: { Label(loc.t("bg.title"), systemImage: "photo.on.rectangle") }
                    Button { runSuggest() } label: { Label(loc.t("conv.smartReply"), systemImage: "wand.and.stars") }
                    if conversation.is_group {
                        Button { activeSheet = .members } label: { Label(loc.t("conv.members.manage"), systemImage: "person.2") }
                    }
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
                            Avatar(initials: m.initials, tint: m.tintColor, size: 28, imageURL: m.avatar_url)
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
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(FlowTheme.gray)
                }
                // 语音/键盘切换（微信式）
                Button { voiceMode.toggle() } label: {
                    Image(systemName: voiceMode ? "keyboard" : "waveform")
                        .font(.system(size: 20)).foregroundStyle(FlowTheme.gray)
                }
                if voiceMode {
                    HoldToTalkBar(recorder: recorder, idleLabel: loc.t("voice.hold")) { url, secs in
                        sendVoice(url: url, secs: secs)
                    }
                } else {
                    HStack {
                        TextField(loc.t("chat.placeholder"), text: $draft).font(FlowTheme.body(15)).onSubmit { send() }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.9)))
                    .sketchBorder(22, width: 1.4, seed: 42)

                    Button { send() } label: { PillButton(title: loc.t("chat.send"), radius: 22, seed: 41) }
                }
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
                                Avatar(initials: c.avatar, tint: c.tintColor, size: 40, seed: UInt64(idx + 150), imageURL: c.avatar_url)
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
    var onReact: (String) -> Void = { _ in }
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
                    Task {
                        _ = try? await APIClient.shared.adopt(snapshotId: sid)
                        NotificationCenter.default.post(name: .flowCompanionsChanged, object: nil)
                    }
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

/// 群成员管理页的弹窗集合（单 sheet 驱动）。
private enum GroupSheet: Identifiable {
    case edit, invite
    case profile(Int)
    var id: String {
        switch self {
        case .edit: return "edit"
        case .invite: return "invite"
        case .profile(let uid): return "profile-\(uid)"
        }
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
    @State private var announcement = ""
    @State private var activeSheet: GroupSheet?     // 单 sheet 驱动，避免多 .sheet 互吞

    private var amOwner: Bool { members.first { $0.user_id == myId }?.role == "owner" }
    private var countSuffix: String {
        // 显示总人数（含 AI 搭子）；cap 仅约束真人，故只在总数后附注上限
        let total = members.count
        if let cap = conversation.member_cap { return " \(total)/\(cap)" }
        return " \(total)"
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
                    Button { activeSheet = .edit } label: {
                        Label(loc.t("group.edit"), systemImage: "square.and.pencil").font(FlowTheme.caption(13))
                    }
                    Button { activeSheet = .invite } label: {
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
                                Button { activeSheet = .profile(uid) } label: {
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit:
                GroupEditView(conversation: conversation) { c in announcement = c.announcement ?? "" }
            case .invite:
                InviteFriendsView(conversation: conversation, existing: Set(members.compactMap { $0.user_id })) { Task { await reload() } }
            case .profile(let uid):
                UserProfileView(userId: uid)
            }
        }
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
