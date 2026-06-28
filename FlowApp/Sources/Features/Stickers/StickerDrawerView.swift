import SwiftUI

/// 聊天里的"收藏表情包"抽屉（向上滑出）。只显示已收藏的，点击即发送。
struct StickerDrawerView: View {
    @EnvironmentObject var loc: Localization
    let onSend: (Sticker) -> Void

    @State private var stickers: [Sticker] = []
    @State private var loading = true

    private let cols = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 12) {
                Text(loc.t("sticker.favDrawer"))
                    .font(FlowTheme.heading(17)).foregroundStyle(FlowTheme.ink)
                    .padding(.top, 16)

                if loading {
                    Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
                } else if stickers.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "star").font(.system(size: 28)).foregroundStyle(FlowTheme.gray)
                        Text(loc.t("sticker.favEmpty"))
                            .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(stickers) { s in
                                Button { onSend(s) } label: {
                                    AsyncImage(url: URL(string: s.url)) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: { ProgressView().tint(FlowTheme.teal) }
                                    .frame(width: 92, height: 92)
                                    .background(FlowTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .sketchBorder(14, width: 1.3, seed: UInt64(s.id + 70))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
        .task {
            stickers = (try? await APIClient.shared.listStickers(favorite: true)) ?? []
            loading = false
        }
    }
}
