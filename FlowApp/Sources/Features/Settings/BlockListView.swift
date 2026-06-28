import SwiftUI

/// 黑名单管理：查看已拉黑的人，可解除。
struct BlockListView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    @State private var blocks: [BlockedUser] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                Text(loc.t("safety.blocklist")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink).padding(.vertical, 18)
                if loading {
                    Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
                } else if blocks.isEmpty {
                    Spacer()
                    Text(loc.t("safety.blocklistEmpty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(blocks) { b in
                                HStack(spacing: 12) {
                                    Avatar(initials: b.initials, tint: FlowTheme.gray, size: 40, imageURL: b.avatar_url)
                                    Text(b.nickname).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                    Spacer()
                                    Button { unblock(b) } label: {
                                        Text(loc.t("safety.unblock")).font(.system(size: 13, weight: .semibold)).foregroundStyle(FlowTheme.teal)
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            .background(Capsule().fill(FlowTheme.teal.opacity(0.12)))
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .sketchCard(14, fill: FlowTheme.card, seed: UInt64(b.user_id + 30))
                            }
                        }.padding(16)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }.padding(16)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        blocks = (try? await APIClient.shared.listBlocks()) ?? []
        loading = false
    }

    private func unblock(_ b: BlockedUser) {
        blocks.removeAll { $0.user_id == b.user_id }
        Task { try? await APIClient.shared.unblockUser(b.user_id) }
    }
}
