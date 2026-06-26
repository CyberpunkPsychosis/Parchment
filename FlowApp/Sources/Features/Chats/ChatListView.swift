import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var loc: Localization

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(MockData.chats.enumerated()), id: \.element.id) { idx, chat in
                            NavigationLink(value: chat) {
                                ChatRowView(chat: chat, seed: UInt64(idx + 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(PaperBackground())
            .navigationDestination(for: ChatSummary.self) { chat in
                ChatDetailView(chat: chat)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(loc.t("chats.title"))
                .font(FlowTheme.title(30))
                .foregroundStyle(FlowTheme.ink)
            Spacer()
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(FlowTheme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

struct ChatRowView: View {
    let chat: ChatSummary
    var seed: UInt64 = 1

    var body: some View {
        HStack(spacing: 12) {
            Avatar(initials: chat.initials, tint: chat.tint, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .lineLimit(1)
                Text(chat.preview)
                    .font(FlowTheme.caption(13))
                    .foregroundStyle(FlowTheme.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(chat.time)
                    .font(FlowTheme.caption(11))
                    .foregroundStyle(FlowTheme.gray)
                if chat.unread > 0 {
                    Text("\(chat.unread)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(FlowTheme.teal))
                } else {
                    HStack(spacing: 2) {
                        Circle().fill(FlowTheme.gray.opacity(0.5)).frame(width: 5, height: 5)
                        Circle().fill(FlowTheme.gray.opacity(0.5)).frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .sketchCard(18, fill: FlowTheme.card, seed: seed)
    }
}
