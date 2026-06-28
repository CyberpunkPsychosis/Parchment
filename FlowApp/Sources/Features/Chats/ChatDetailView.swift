import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ChatDetailView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss
    let chat: ChatSummary
    /// AI 角色的 system prompt（普通聊天为 nil；AI 搭子会传入人设）
    var persona: String? = nil
    /// 搭子 id：不为空则走"带记忆"的搭子对话（后端注入记忆 + 自动提取）
    var companionId: Int? = nil
    /// 初始消息（默认沿用设计稿样例，AI 搭子可传欢迎语 / 空）
    var seedMessages: [Message] = MockData.conversation

    @State private var draft: String = ""
    @State private var messages: [Message] = []
    @State private var isStreaming = false
    @State private var assistBusy = false
    @State private var suggestions: [String] = []
    @State private var showPaywall = false
    @State private var capMessage: String?
    @State private var showStickerPanel = false
    @State private var previewSticker: Sticker?
    @State private var previewAuto = false
    @State private var toast: String?
    @State private var quoted: Message?
    @State private var muted = false
    @State private var showClearConfirm = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showMemories = false

    private let tones: [(key: String, value: String)] = [
        ("tone.natural", "自然"), ("tone.serious", "正经"),
        ("tone.funny", "幽默"), ("tone.gentle", "委婉"), ("tone.professional", "专业"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Text(loc.t("chat.today"))
                            .font(FlowTheme.caption(12))
                            .foregroundStyle(FlowTheme.ink.opacity(0.55))
                            .padding(.vertical, 6)
                        ForEach(Array(messages.enumerated()), id: \.element.id) { idx, msg in
                            MessageRow(message: msg, seed: UInt64(idx + 30)) { messageMenu(msg) }
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(ChatBackground())
                .onChange(of: messages.last?.id) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .background(PaperBackground())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if messages.isEmpty { messages = seedMessages }; loadMute(); ui.hideTabBar = true }
        .onDisappear { ui.hideTabBar = false }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        messages.append(Message(kind: .localImage(data), mine: true, time: Self.now()))
                    }
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            if case let .success(url) = result {
                messages.append(Message(kind: .file(name: url.lastPathComponent), mine: true, time: Self.now()))
            }
        }
        .confirmationDialog(loc.t("chat.clearConfirm"), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(loc.t("chat.clear"), role: .destructive) { clearHistory() }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(headline: capMessage).environmentObject(loc).environmentObject(auth)
        }
        .sheet(isPresented: $showStickerPanel) {
            StickerDrawerView { s in sendSticker(s); showStickerPanel = false }
                .environmentObject(loc)
        }
        .sheet(isPresented: $showMemories) {
            if let cid = companionId {
                MemoriesView(companionId: cid, companionName: chat.name).environmentObject(loc)
            }
        }
        .overlay { stickerPreview }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(FlowTheme.caption(13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(FlowTheme.ink.opacity(0.85)))
                    .padding(.bottom, 90)
                    .transition(.opacity)
            }
        }
    }

    private func sendSticker(_ s: Sticker) {
        messages.append(Message(kind: .imageURL(s.url), mine: true, time: Self.now()))
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    // MARK: 消息长按操作

    @ViewBuilder private func messageMenu(_ msg: Message) -> some View {
        if case let .text(t) = msg.kind {
            Button { UIPasteboard.general.string = t } label: { Label(loc.t("msg.copy"), systemImage: "doc.on.doc") }
            Button { quoted = msg } label: { Label(loc.t("msg.quote"), systemImage: "quote.bubble") }
            if let cid = companionId {
                Button {
                    Task {
                        _ = try? await APIClient.shared.addMemory(companionId: cid, content: t)
                        await MainActor.run { showToast(loc.t("msg.remembered")) }
                    }
                } label: { Label(loc.t("msg.remember"), systemImage: "brain") }
            }
        }
        if msg.mine {
            Button(role: .destructive) {
                messages.removeAll { $0.id == msg.id }
                showToast(loc.t("msg.recalled"))
            } label: { Label(loc.t("msg.recall"), systemImage: "arrow.uturn.backward") }
        }
        Button(role: .destructive) {
            messages.removeAll { $0.id == msg.id }
        } label: { Label(loc.t("msg.delete"), systemImage: "trash") }
    }

    private var muteKey: String { "flow.mute.\(chat.name)" }

    private func loadMute() { muted = UserDefaults.standard.bool(forKey: muteKey) }

    private func toggleMute() {
        muted.toggle()
        UserDefaults.standard.set(muted, forKey: muteKey)
        showToast(loc.t(muted ? "chat.muted" : "chat.unmuted"))
    }

    private func clearHistory() {
        withAnimation { messages = [] }
        showToast(loc.t("chat.cleared"))
    }

    /// 命中每日上限(429) → 弹付费墙，返回 true。
    private func handleCap(_ error: Error) -> Bool {
        if case let APIError.http(code, msg) = error, code == 429 {
            capMessage = msg
            showPaywall = true
            return true
        }
        return false
    }

    // MARK: 发送 + 流式

    private func send() {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isStreaming else { return }
        draft = ""
        // 带引用则把被引用内容作为前缀（AI 也能看到上下文）
        var text = raw
        if let q = quoted, case let .text(qt) = q.kind {
            let snippet = qt.count > 40 ? String(qt.prefix(40)) + "…" : qt
            text = "「\(snippet)」\n\(raw)"
            quoted = nil
        }
        messages.append(Message(kind: .text(text), mine: true, time: Self.now()))

        // 占位 AI 消息，后续逐字填充
        let aiId = UUID()
        messages.append(Message(id: aiId, kind: .text(""), mine: false, time: Self.now()))
        isStreaming = true

        let history = messages
            .compactMap { m -> ChatMessageDTO? in
                guard case let .text(t) = m.kind, !(m.id == aiId) else { return nil }
                return ChatMessageDTO(role: m.mine ? "user" : "assistant", content: t)
            }

        Task {
            do {
                try await APIClient.shared.streamChat(messages: history,
                                                      system: companionId == nil ? persona : nil,
                                                      companionId: companionId) { delta in
                    if let i = messages.firstIndex(where: { $0.id == aiId }),
                       case let .text(cur) = messages[i].kind {
                        messages[i].kind = .text(cur + delta)
                    }
                }
            } catch {
                messages.removeAll { $0.id == aiId }
                if !handleCap(error) {
                    messages.append(Message(kind: .text("⚠️ " + error.localizedDescription), mine: false, time: Self.now()))
                }
            }
            isStreaming = false
        }
    }

    private static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
            }
            Avatar(initials: chat.initials, tint: chat.tint, size: 38, imageURL: chat.imageURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                HStack(spacing: 5) {
                    OnlineDot(online: true)
                    Text(loc.t("status.online")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                }
            }
            if muted {
                Image(systemName: "bell.slash.fill").font(.system(size: 13)).foregroundStyle(FlowTheme.gray)
            }
            Spacer()
            Menu {
                if companionId != nil {
                    Button { showMemories = true } label: {
                        Label(loc.t("chat.memories"), systemImage: "brain")
                    }
                }
                Button { toggleMute() } label: {
                    Label(loc.t(muted ? "chat.unmute" : "chat.mute"),
                          systemImage: muted ? "bell" : "bell.slash")
                }
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label(loc.t("chat.clear"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(FlowTheme.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            FlowTheme.card
                .overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .bottom)
        )
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !suggestions.isEmpty { suggestionsRow }
            if let q = quoted, case let .text(qt) = q.kind { quoteBanner(qt) }

            HStack(spacing: 8) {
                assistMenu
                stickerButton
                attachButton

                HStack {
                    TextField(loc.t("chat.placeholder"), text: $draft)
                        .font(FlowTheme.body(15))
                        .onSubmit(send)
                        .submitLabel(.send)
                    Image(systemName: "mic.fill").foregroundStyle(FlowTheme.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 22).fill(FlowTheme.field))
                .sketchBorder(22, width: 1.4, seed: 42)

                Button(action: send) {
                    PillButton(title: loc.t("chat.send"), radius: 22, seed: 41)
                        .opacity(isStreaming ? 0.45 : 1)
                }
                .disabled(isStreaming)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
    }

    private var assistMenu: some View {
        Menu {
            Menu(loc.t("assist.rewrite")) {
                ForEach(tones, id: \.key) { t in
                    Button(loc.t(t.key)) { doRewrite(tone: t.value) }
                }
            }
            Button(loc.t("assist.translate")) { doTranslate() }
            Button(loc.t("assist.suggest")) { doSuggest() }
            Button(loc.t("assist.sticker")) { doSticker() }
        } label: {
            ZStack {
                Circle().fill(FlowTheme.teal.opacity(0.14)).frame(width: 40, height: 40)
                    .sketchBorder(20, width: 1.2, seed: 43)
                if assistBusy {
                    ProgressView().tint(FlowTheme.teal)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(FlowTheme.teal)
                }
            }
        }
        .disabled(assistBusy || isStreaming)
    }

    private func quoteBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(FlowTheme.teal).frame(width: 3, height: 28)
            Text(text).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                .lineLimit(1)
            Spacer()
            Button { quoted = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(FlowTheme.gray.opacity(0.6))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(FlowTheme.beige.opacity(0.5)))
    }

    private var stickerButton: some View {
        Button { showStickerPanel = true } label: {
            ZStack {
                Circle().fill(FlowTheme.sage.opacity(0.18)).frame(width: 40, height: 40)
                    .sketchBorder(20, width: 1.2, seed: 44)
                Image(systemName: "face.smiling").font(.system(size: 18)).foregroundStyle(FlowTheme.tealDark)
            }
        }
        .disabled(assistBusy)
    }

    private var attachButton: some View {
        Menu {
            Button { showPhotoPicker = true } label: { Label(loc.t("chat.photo"), systemImage: "photo") }
            Button { showFileImporter = true } label: { Label(loc.t("chat.file"), systemImage: "doc") }
        } label: {
            ZStack {
                Circle().fill(FlowTheme.gray.opacity(0.14)).frame(width: 40, height: 40)
                    .sketchBorder(20, width: 1.2, seed: 45)
                Image(systemName: "plus").font(.system(size: 18)).foregroundStyle(FlowTheme.gray)
            }
        }
    }

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { draft = s; suggestions = [] } label: {
                        Text(s)
                            .font(FlowTheme.caption(13))
                            .foregroundStyle(FlowTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 240, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
                            .sketchBorder(14, width: 1.2, seed: 55)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: 助手动作

    private func doRewrite(tone: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        runAssist {
            let r = try await APIClient.shared.rewrite(text: text, tone: tone)
            await MainActor.run { draft = r }
        }
    }

    private func doTranslate() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        runAssist {
            let r = try await APIClient.shared.translate(text: text)
            await MainActor.run { draft = r }
        }
    }

    private func doSuggest() {
        let history = messages.suffix(6).compactMap { m -> ChatMessageDTO? in
            guard case let .text(t) = m.kind, !t.isEmpty else { return nil }
            return ChatMessageDTO(role: m.mine ? "user" : "assistant", content: t)
        }
        guard !history.isEmpty else { return }
        runAssist {
            let s = try await APIClient.shared.replySuggest(messages: history)
            await MainActor.run { suggestions = s }
        }
    }

    private func doSticker() {
        let extra = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // 用最近对话做语境
        let ctx = messages.suffix(8).compactMap { m -> ChatMessageDTO? in
            guard case let .text(t) = m.kind, !t.isEmpty else { return nil }
            return ChatMessageDTO(role: m.mine ? "user" : "assistant", content: t)
        }
        runAssist {
            let sticker = try await APIClient.shared.generateSticker(
                prompt: extra, context: ctx.isEmpty ? nil : ctx)
            await MainActor.run {
                draft = ""
                if auth.user?.auto_send_stickers == true {
                    sendSticker(sticker)            // 已设自动 → 直接发
                } else {
                    previewAuto = false
                    previewSticker = sticker        // 否则先预览，选发送/丢弃
                }
            }
        }
    }

    // 生成贴纸预览：发送 or 丢弃（丢弃即删除）
    @ViewBuilder private var stickerPreview: some View {
        if let s = previewSticker {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { discardPreview() }
                VStack(spacing: 16) {
                    Text(loc.t("sticker.preview")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                    AsyncImage(url: URL(string: s.url)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(FlowTheme.teal).frame(width: 200, height: 200)
                    }
                    .frame(width: 200, height: 200)
                    .background(FlowTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .sketchBorder(16, width: 1.4, seed: 66)

                    Toggle(loc.t("sticker.autoRemember"), isOn: $previewAuto)
                        .toggleStyle(FlowToggleStyle())
                        .font(FlowTheme.caption(13))

                    HStack(spacing: 12) {
                        Button { discardPreview() } label: {
                            Text(loc.t("sticker.discard"))
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.gray)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 16).fill(FlowTheme.card))
                                .sketchBorder(16, width: 1.3, seed: 67)
                        }
                        Button { confirmPreview() } label: {
                            PrimaryButton(title: loc.t("sticker.send"))
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 22).fill(FlowTheme.parchment))
                .sketchBorder(22, width: 1.6, seed: 68)
                .padding(.horizontal, 44)
            }
            .transition(.opacity)
        }
    }

    private func confirmPreview() {
        guard let s = previewSticker else { return }
        if previewAuto { auth.setAutoSendStickers(true) }
        sendSticker(s)
        previewSticker = nil
    }

    private func discardPreview() {
        if let s = previewSticker {
            Task { try? await APIClient.shared.deleteSticker(id: s.id) }  // 丢弃即删除，不留库
        }
        previewSticker = nil
    }

    private func runAssist(_ op: @escaping () async throws -> Void) {
        assistBusy = true
        Task {
            do { try await op() }
            catch {
                await MainActor.run {
                    if !handleCap(error) { showToast("⚠️ " + error.localizedDescription) }
                }
            }
            await MainActor.run { assistBusy = false }
        }
    }
}

/// Gray-blue hand-drawn thread background (the dark sketch lightened).
/// 可自定义的聊天背景：内置预设 + 自定义上传图（存 AppStorage，全局生效）。
struct ChatBackground: View {
    @AppStorage("flow.chatBg") private var preset = "beige"
    @AppStorage("flow.chatBgURL") private var customURL = ""

    var body: some View {
        ZStack {
            switch preset {
            case "sage":
                FlowTheme.sage.opacity(0.35)
            case "plain":
                Color(hex: 0xF7F4EC)
            case "mist":
                Color(hex: 0xE7EEF1)
            case "blush":
                Color(hex: 0xF5E8E0)
            case "custom":
                if let u = URL(string: customURL), !customURL.isEmpty {
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
                } else {
                    FlowTheme.beige
                }
            default:   // beige（默认）及任何旧值都回落米色
                FlowTheme.beige
            }
        }
        .clipped()
    }
}

/// 聊天背景选择器：预设 + 自定义上传。
struct ChatBackgroundPicker: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    @AppStorage("flow.chatBg") private var preset = "beige"
    @AppStorage("flow.chatBgURL") private var customURL = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false

    private let presets: [(id: String, key: String)] = [
        ("beige", "bg.beige"), ("plain", "bg.plain"), ("sage", "bg.sage"),
        ("mist", "bg.mist"), ("blush", "bg.blush"),
    ]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 18) {
                Text(loc.t("bg.title")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink).padding(.top, 20)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(presets, id: \.id) { p in
                            Button { preset = p.id } label: { swatch(p.id, label: loc.t(p.key)) }.buttonStyle(.plain)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            VStack(spacing: 6) {
                                Image(systemName: uploading ? "arrow.up.circle" : "plus.circle")
                                    .font(.system(size: 24)).foregroundStyle(FlowTheme.teal)
                                Text(loc.t("bg.custom")).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.ink)
                            }
                            .frame(maxWidth: .infinity).frame(height: 88)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.card))
                            .sketchBorder(14, width: 1.3, seed: 71)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            uploading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let url = try? await APIClient.shared.uploadImage(data) {
                    await MainActor.run { customURL = url; preset = "custom" }
                }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
    }

    private func swatch(_ id: String, label: String) -> some View {
        ZStack {
            previewBg(id).frame(height: 88).clipShape(RoundedRectangle(cornerRadius: 14))
            if preset == id {
                RoundedRectangle(cornerRadius: 14).strokeBorder(FlowTheme.teal, lineWidth: 2.5)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(FlowTheme.teal).font(.system(size: 20))
            }
            Text(label).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.ink)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.7)))
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 6)
        }
        .sketchBorder(14, width: 1.3, seed: UInt64(id.hashValue & 0xffff))
    }

    @ViewBuilder private func previewBg(_ id: String) -> some View {
        switch id {
        case "sage": FlowTheme.sage.opacity(0.35)
        case "plain": Color(hex: 0xF7F4EC)
        case "mist": Color(hex: 0xE7EEF1)
        case "blush": Color(hex: 0xF5E8E0)
        default: FlowTheme.beige
        }
    }
}

struct MessageRow<Menu: View>: View {
    @EnvironmentObject var loc: Localization
    let message: Message
    var seed: UInt64 = 30
    @ViewBuilder var menu: () -> Menu

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.mine { Spacer(minLength: 50) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                bubble.contextMenu { menu() }   // 只罩气泡，不再是满屏行矩形
                Text(message.time).font(FlowTheme.caption(10)).foregroundStyle(FlowTheme.ink.opacity(0.55))
            }
            if !message.mine { Spacer(minLength: 50) }
        }
    }

    @ViewBuilder private var bubble: some View {
        switch message.kind {
        case .text(let t):
            Text(t)
                .font(FlowTheme.body(15))
                .foregroundStyle(message.mine ? FlowTheme.sageInk : FlowTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .sketchCard(18, fill: message.mine ? FlowTheme.sage : FlowTheme.card, seed: seed)
        case .image:
            ZStack {
                LinearGradient(colors: [Color(hex: 0xDCD0B8), Color(hex: 0xC9BBA0)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image("paper_light").resizable().scaledToFill().opacity(0.6)
            }
            .frame(width: 132, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .sketchBorder(16, width: 1.4, seed: seed)
        case .imageURL(let url):
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(FlowTheme.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView().tint(FlowTheme.teal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 168, height: 168)
            .background(FlowTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .sketchBorder(16, width: 1.4, seed: seed)
        case .localImage(let data):
            if let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 168, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .sketchBorder(16, width: 1.4, seed: seed)
            }
        case .file(let name):
            HStack(spacing: 10) {
                Image(systemName: "doc.fill").font(.system(size: 22)).foregroundStyle(FlowTheme.teal)
                Text(name).font(FlowTheme.body(14)).foregroundStyle(message.mine ? FlowTheme.sageInk : FlowTheme.ink)
                    .lineLimit(1).frame(maxWidth: 160, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .sketchCard(16, fill: message.mine ? FlowTheme.sage : FlowTheme.card, seed: seed)
        case .voice(let secs):
            VoiceBubble(seconds: secs, mine: message.mine, seed: seed)
        }
    }
}

struct VoiceBubble: View {
    let seconds: Int
    let mine: Bool
    var seed: UInt64 = 30
    private var fg: Color { mine ? FlowTheme.sageInk : FlowTheme.teal }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(fg)
            HStack(spacing: 2) {
                ForEach(0..<22, id: \.self) { i in
                    Capsule().fill(fg.opacity(0.8)).frame(width: 2.5, height: waveHeight(i))
                }
            }
            Text("0:\(String(format: "%02d", seconds))")
                .font(FlowTheme.caption(11)).foregroundStyle(fg.opacity(0.85))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .sketchCard(18, fill: mine ? FlowTheme.sage : FlowTheme.card, seed: seed)
    }

    private func waveHeight(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 12, 20, 14, 8, 18, 24, 10, 16, 22, 9, 14]
        return pattern[i % pattern.count]
    }
}
