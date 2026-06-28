import SwiftUI

/// 市场搭子详情：人设 + 公开的记忆(美好回忆) + 认领。
struct MarketDetailView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let item: MarketItem
    var onAdopted: () -> Void = {}

    @State private var detail: MarketItem?
    @State private var adopting = false
    @State private var done = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Avatar(initials: item.avatar, tint: item.tintColor, size: 84, seed: 7).padding(.top, 20)
                    VStack(spacing: 5) {
                        Text(item.name).font(FlowTheme.heading(22)).foregroundStyle(FlowTheme.ink)
                        Text("\(loc.t("market.by"))\(item.publisher_name)")
                            .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                        if item.lineage_depth > 0 {
                            Text("\(loc.t("market.lineage"))\(item.lineage_depth)\(loc.t("market.genUnit"))")
                                .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.teal)
                        }
                    }

                    Card { Text(item.persona).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                        .padding(.horizontal, 16)

                    // 公开的记忆
                    if let mems = detail?.memories, !mems.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(loc.t("market.memories")).font(FlowTheme.heading(16)).foregroundStyle(FlowTheme.ink)
                                ForEach(mems, id: \.self) { m in
                                    HStack(spacing: 10) {
                                        Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(FlowTheme.teal)
                                        Text(m).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                                        Spacer()
                                    }
                                }
                                if let hidden = detail?.hidden_count, hidden > 0 {
                                    HStack(spacing: 8) {
                                        Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(FlowTheme.gray)
                                        Text("\(loc.t("market.hiddenA"))\(hidden)\(loc.t("market.hiddenB"))")
                                            .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(16)
                        }
                        .padding(.horizontal, 16)
                    }

                    Button(action: adopt) {
                        ZStack {
                            PrimaryButton(title: loc.t(done ? "market.adopted" : "market.adopt"))
                                .opacity(adopting || done ? 0.6 : 1)
                            if adopting { ProgressView().tint(.white) }
                        }
                    }
                    .disabled(adopting || done)
                    .padding(.horizontal, 16)

                    Text(loc.t("market.adoptNote"))
                        .font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                        .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(FlowTheme.ink)
            }.padding(16)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { detail = try? await APIClient.shared.marketDetail(id: item.id) }
    }

    private func adopt() {
        adopting = true
        Task {
            _ = try? await APIClient.shared.adopt(snapshotId: item.id)
            done = true
            onAdopted()
            try? await Task.sleep(nanoseconds: 800_000_000)
            adopting = false
            dismiss()
        }
    }
}
