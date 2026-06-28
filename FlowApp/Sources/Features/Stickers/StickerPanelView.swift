import SwiftUI

/// 我的表情包库（个人信息里）：最近 / 收藏 + 生成新贴纸；点贴纸=收藏/取消收藏（决定聊天抽屉里显示哪些），长按删除。
struct StickerPanelView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0           // 0=最近 1=收藏
    @State private var stickers: [Sticker] = []
    @State private var makePrompt = ""
    @State private var making = false
    @State private var loading = true

    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 14) {
                VStack(spacing: 3) {
                    Text(loc.t("profile.stickers")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                    Text(loc.t("sticker.libraryHint")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                }
                .padding(.top, 18)

                Picker("", selection: $tab) {
                    Text(loc.t("sticker.recent")).tag(0)
                    Text(loc.t("sticker.favorites")).tag(1)
                }
                .pickerStyle(.segmented).frame(width: 220)
                .onChange(of: tab) { _, _ in Task { await load() } }

                // 生成栏
                HStack(spacing: 8) {
                    TextField(loc.t("sticker.makeHint"), text: $makePrompt)
                        .font(FlowTheme.body(14))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
                        .sketchBorder(14, width: 1.3, seed: 51)
                    Button(action: make) {
                        ZStack {
                            PillButton(title: loc.t("sticker.make"), radius: 18, seed: 52)
                                .opacity(making || makePrompt.isEmpty ? 0.5 : 1)
                            if making { ProgressView().tint(.white) }
                        }
                    }.disabled(making || makePrompt.isEmpty)
                }
                .padding(.horizontal, 16)

                if loading {
                    Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
                } else if stickers.isEmpty {
                    Spacer()
                    Text(loc.t("sticker.empty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(stickers) { s in cell(s) }
                        }
                        .padding(16)
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

    private func cell(_ s: Sticker) -> some View {
        Button { Task { await favorite(s) } } label: {   // 点击=收藏/取消收藏
            AsyncImage(url: URL(string: s.url)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                ProgressView().tint(FlowTheme.teal)
            }
            .frame(width: 100, height: 100)
            .background(FlowTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .sketchBorder(14, width: 1.3, seed: UInt64(s.id + 60))
            .overlay(alignment: .topTrailing) {
                Image(systemName: s.is_favorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(s.is_favorite ? .yellow : FlowTheme.gray.opacity(0.7))
                    .padding(5)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { Task { await remove(s) } } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func load() async {
        loading = true
        stickers = (try? await APIClient.shared.listStickers(favorite: tab == 1)) ?? []
        loading = false
    }

    private func make() {
        let p = makePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        making = true
        Task {
            if let s = try? await APIClient.shared.generateSticker(prompt: p) {
                await MainActor.run { makePrompt = ""; if tab == 0 { stickers.insert(s, at: 0) } }
            }
            making = false
        }
    }

    private func favorite(_ s: Sticker) async {
        _ = try? await APIClient.shared.toggleStickerFavorite(id: s.id)
        await load()
    }

    private func remove(_ s: Sticker) async {
        try? await APIClient.shared.deleteSticker(id: s.id)
        await load()
    }
}
