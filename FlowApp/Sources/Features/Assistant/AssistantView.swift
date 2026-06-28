import SwiftUI

/// 羊皮纸助手返回的动作提案。
struct AssistantProposal: Codable, Hashable {
    let kind: String          // answer | send_message | post_moment | summarize
    let say: String
    var content: String? = nil
    var conversation_id: Int? = nil
    var conversation_title: String? = nil
}

/// 助手面板里的一条记录。
private struct AssistantMsg: Identifiable {
    let id = UUID()
    let mine: Bool
    var text: String
    var proposal: AssistantProposal? = nil   // 需用户确认的动作（发消息/发朋友圈）
    var resolved: String? = nil              // 已执行/已取消后的状态文案
}

/// 羊皮纸助手：自然语言在站内办事（发消息/发朋友圈/总结群/回答）。
/// 有副作用的动作先弹确认卡，确认后才真正执行。
struct AssistantView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    @State private var msgs: [AssistantMsg] = []
    @State private var draft = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if msgs.isEmpty { intro }
                            ForEach(msgs) { m in row(m) }
                            if busy { HStack { ProgressView().tint(FlowTheme.teal); Spacer() } }
                        }
                        .padding(16)
                    }
                    .onChange(of: msgs.count) { _, _ in
                        if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                inputBar
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(FlowTheme.teal)
            Text(loc.t("quick.aiName")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .bottom))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("quick.aiGreeting")).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
            Text(loc.t("assistant.examples")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).sketchCard(16, fill: FlowTheme.card, seed: 12)
    }

    @ViewBuilder private func row(_ m: AssistantMsg) -> some View {
        HStack {
            if m.mine { Spacer(minLength: 40) }
            VStack(alignment: m.mine ? .trailing : .leading, spacing: 8) {
                Text(m.text).font(FlowTheme.body(15))
                    .foregroundStyle(m.mine ? FlowTheme.sageInk : FlowTheme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .sketchCard(16, fill: m.mine ? FlowTheme.sage : Color(hex: 0xFCFAF4), seed: UInt64(m.id.hashValue & 0xffff))
                if let p = m.proposal { confirmCard(m, p) }
                if let r = m.resolved {
                    Text(r).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.teal)
                }
            }
            if !m.mine { Spacer(minLength: 40) }
        }
    }

    /// 发消息 / 发朋友圈 的确认卡。
    @ViewBuilder private func confirmCard(_ m: AssistantMsg, _ p: AssistantProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: p.kind == "post_moment" ? "photo.on.rectangle" : "paperplane")
                    .font(.system(size: 12)).foregroundStyle(FlowTheme.teal)
                Text(p.kind == "post_moment" ? loc.t("assistant.willPost")
                     : "\(loc.t("assistant.willSend"))【\(p.conversation_title ?? "")】")
                    .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
            }
            Text(p.content ?? "").font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Button { execute(m, p) } label: {
                    Text(loc.t("assistant.confirm")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(FlowTheme.teal))
                }
                Button { cancel(m) } label: {
                    Text(loc.t("common.cancel")).font(.system(size: 13)).foregroundStyle(FlowTheme.gray)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(FlowTheme.card))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .sketchCard(16, fill: FlowTheme.card, seed: UInt64((m.id.hashValue >> 1) & 0xffff))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(loc.t("assistant.placeholder"), text: $draft).font(FlowTheme.body(15)).onSubmit { send() }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.9)))
                .sketchBorder(22, width: 1.4, seed: 42)
            Button { send() } label: { PillButton(title: loc.t("chat.send"), radius: 22, seed: 41) }
                .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        draft = ""; busy = true
        msgs.append(AssistantMsg(mine: true, text: text))
        Task {
            let p = try? await APIClient.shared.assistantAct(text: text)
            await MainActor.run {
                busy = false
                guard let p else { msgs.append(AssistantMsg(mine: false, text: loc.t("assistant.failed"))); return }
                let needsConfirm = (p.kind == "send_message" || p.kind == "post_moment")
                msgs.append(AssistantMsg(mine: false, text: p.say, proposal: needsConfirm ? p : nil))
            }
        }
    }

    private func execute(_ m: AssistantMsg, _ p: AssistantProposal) {
        Task {
            var ok = false
            if p.kind == "send_message", let cid = p.conversation_id, let c = p.content {
                ok = ((try? await APIClient.shared.sendMessage(conversationId: cid, content: c)) != nil)
            } else if p.kind == "post_moment", let c = p.content {
                ok = ((try? await APIClient.shared.createPost(content: c, imageURL: nil)) != nil)
            }
            await MainActor.run {
                if let i = msgs.firstIndex(where: { $0.id == m.id }) {
                    msgs[i].proposal = nil
                    msgs[i].resolved = ok
                        ? (p.kind == "post_moment" ? loc.t("assistant.posted")
                           : "\(loc.t("assistant.sent"))【\(p.conversation_title ?? "")】")
                        : loc.t("assistant.failed")
                }
            }
        }
    }

    private func cancel(_ m: AssistantMsg) {
        if let i = msgs.firstIndex(where: { $0.id == m.id }) {
            msgs[i].proposal = nil
            msgs[i].resolved = loc.t("assistant.cancelled")
        }
    }
}
