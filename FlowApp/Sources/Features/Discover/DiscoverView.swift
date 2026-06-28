import SwiftUI

/// 发现 = 三栏：搭子市场 / 群组广场 / 朋友圈。
struct DiscoverView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var ui: UIState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(loc.t("nav.discover")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

                Picker("", selection: $ui.discoverSection) {
                    Text(loc.t("disc.market")).tag(0)
                    Text(loc.t("disc.groups")).tag(1)
                    Text(loc.t("disc.moments")).tag(2)
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)

                switch ui.discoverSection {
                case 0: MarketListView()
                case 1: GroupPlazaView()
                default: MomentsView()
                }
            }
            .background(PaperBackground())
            .navigationDestination(for: MarketItem.self) { it in
                MarketDetailView(item: it)
            }
            .navigationDestination(for: PlazaGroup.self) { g in
                CommunityDetailView(group: g)
            }
            .navigationDestination(for: MomentPost.self) { p in
                PostDetailView(post: p)
            }
        }
    }

    private var comingSoon: some View {
        VStack {
            Spacer()
            Image(systemName: "hourglass").font(.system(size: 30)).foregroundStyle(FlowTheme.gray)
            Text(loc.t("disc.soon")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 搭子认领市场列表。
struct MarketListView: View {
    @EnvironmentObject var loc: Localization
    @State private var items: [MarketItem] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
            } else if items.isEmpty {
                Spacer(); Text(loc.t("market.empty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray); Spacer()
            } else {
                ScrollView {
                    Text(loc.t("market.subtitle")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                    LazyVStack(spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, it in
                            NavigationLink(value: it) { MarketCard(item: it, seed: UInt64(idx + 200)) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = (try? await APIClient.shared.listMarket()) ?? []
        loading = false
    }
}

struct MarketCard: View {
    @EnvironmentObject var loc: Localization
    let item: MarketItem
    var seed: UInt64 = 200

    var body: some View {
        Card(seed: seed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Avatar(initials: item.avatar, tint: item.tintColor, size: 46, seed: seed)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                        Text("\(loc.t("market.by"))\(item.publisher_name)")
                            .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                    }
                    Spacer()
                    if item.lineage_depth > 0 {
                        Text("\(loc.t("market.gen"))\(item.lineage_depth)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(FlowTheme.teal)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(FlowTheme.teal.opacity(0.12)))
                    }
                }
                Text(item.persona).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Label("\(item.memory_count) \(loc.t("market.memCount"))", systemImage: "brain").font(FlowTheme.caption(12))
                    Label("\(item.adopt_count) \(loc.t("market.adoptCount"))", systemImage: "person.2.fill").font(FlowTheme.caption(12))
                    Spacer()
                }
                .foregroundStyle(FlowTheme.gray)
            }
            .padding(16)
        }
    }
}
