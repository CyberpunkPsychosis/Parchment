import SwiftUI

struct ChatDetailView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let chat: ChatSummary
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 14) {
                    Text(loc.t("chat.today"))
                        .font(FlowTheme.caption(12))
                        .foregroundStyle(FlowTheme.ink.opacity(0.55))
                        .padding(.vertical, 6)
                    ForEach(Array(MockData.conversation.enumerated()), id: \.element.id) { idx, msg in
                        MessageRow(message: msg, seed: UInt64(idx + 30))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ChatBackground())
            inputBar
        }
        .background(PaperBackground())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
            }
            Avatar(initials: chat.initials, tint: chat.tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                HStack(spacing: 5) {
                    OnlineDot(online: true)
                    Text(loc.t("status.online")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                }
            }
            Spacer()
            Image(systemName: "video").font(.system(size: 18)).foregroundStyle(FlowTheme.ink)
            Image(systemName: "phone").font(.system(size: 17)).foregroundStyle(FlowTheme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            FlowTheme.card
                .overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .bottom)
        )
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack {
                TextField(loc.t("chat.placeholder"), text: $draft)
                    .font(FlowTheme.body(15))
                Image(systemName: "mic.fill").foregroundStyle(FlowTheme.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.9)))
            .sketchBorder(22, width: 1.4, seed: 42)

            PillButton(title: loc.t("chat.send"), radius: 22, seed: 41)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
    }
}

/// Gray-blue hand-drawn thread background (the dark sketch lightened).
struct ChatBackground: View {
    var body: some View {
        ZStack {
            Color(hex: 0xDFE3E2)
            Image("paper_dark").resizable().scaledToFill().opacity(0.5)
        }
        .clipped()
    }
}

struct MessageRow: View {
    @EnvironmentObject var loc: Localization
    let message: Message
    var seed: UInt64 = 30

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.mine { Spacer(minLength: 50) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                bubble
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
                .sketchCard(18, fill: message.mine ? FlowTheme.sage : Color(hex: 0xFCFAF4), seed: seed)
        case .image:
            ZStack {
                LinearGradient(colors: [Color(hex: 0xDCD0B8), Color(hex: 0xC9BBA0)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image("paper_light").resizable().scaledToFill().opacity(0.6)
            }
            .frame(width: 132, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .sketchBorder(16, width: 1.4, seed: seed)
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
        .sketchCard(18, fill: mine ? FlowTheme.sage : Color(hex: 0xFCFAF4), seed: seed)
    }

    private func waveHeight(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 12, 20, 14, 8, 18, 24, 10, 16, 22, 9, 14]
        return pattern[i % pattern.count]
    }
}
