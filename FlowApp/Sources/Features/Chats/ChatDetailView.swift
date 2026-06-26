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
                        .foregroundStyle(FlowTheme.gray)
                        .padding(.vertical, 6)
                    ForEach(MockData.conversation) { msg in
                        MessageRow(message: msg)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
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
            .background(Capsule().fill(FlowTheme.beige))
            .overlay(Capsule().stroke(FlowTheme.stroke, lineWidth: 1))

            Text(loc.t("chat.send"))
                .font(.system(size: 14, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(FlowTheme.teal))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FlowTheme.card.overlay(Rectangle().fill(FlowTheme.stroke).frame(height: 1), alignment: .top))
    }
}

struct MessageRow: View {
    @EnvironmentObject var loc: Localization
    let message: Message

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.mine { Spacer(minLength: 50) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                bubble
                Text(message.time).font(FlowTheme.caption(10)).foregroundStyle(FlowTheme.gray)
            }
            if !message.mine { Spacer(minLength: 50) }
        }
    }

    @ViewBuilder private var bubble: some View {
        switch message.kind {
        case .text(let t):
            Text(t)
                .font(FlowTheme.body(15))
                .foregroundStyle(message.mine ? .white : FlowTheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(message.mine ? FlowTheme.sage : FlowTheme.beige)
                )
        case .image:
            RoundedRectangle(cornerRadius: 16)
                .fill(FlowTheme.beige)
                .frame(width: 150, height: 96)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundStyle(FlowTheme.gray)
                )
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(FlowTheme.stroke, lineWidth: 1))
        case .voice(let secs):
            VoiceBubble(seconds: secs, mine: message.mine)
        }
    }
}

struct VoiceBubble: View {
    let seconds: Int
    let mine: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(mine ? .white : FlowTheme.teal)
            HStack(spacing: 2) {
                ForEach(0..<22, id: \.self) { i in
                    Capsule()
                        .fill((mine ? Color.white : FlowTheme.teal).opacity(0.85))
                        .frame(width: 2.5, height: waveHeight(i))
                }
            }
            Text("0:\(String(format: "%02d", seconds))")
                .font(FlowTheme.caption(11))
                .foregroundStyle(mine ? .white.opacity(0.9) : FlowTheme.gray)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(mine ? FlowTheme.sage : FlowTheme.beige))
    }

    private func waveHeight(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 12, 20, 14, 8, 18, 24, 10, 16, 22, 9, 14]
        return pattern[i % pattern.count]
    }
}
