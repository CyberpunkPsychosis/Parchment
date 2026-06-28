import SwiftUI

/// 搭子成长档案：等级/经验 + 亲密度 + 里程碑 + 成长动态 + 传承家谱。
/// 「共同养成」护城河的可视化窗口。
struct CompanionDetailView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let companion: Companion

    @State private var affinity: AffinityDTO?
    @State private var milestones: [MilestoneDTO] = []
    @State private var diary: [DiaryDTO] = []
    @State private var lineage: LineageDTO?
    @State private var showMemories = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 16) {
                    growthHeader
                    affinityCard
                    if !milestones.isEmpty { milestonesCard }
                    if !diary.isEmpty { diaryCard }
                    lineageCard
                    // 认领来的搭子：记忆锁定（不可查看/删除前任主人的记忆），保留惊喜感
                    if !companion.adopted {
                        Button { showMemories = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                Text(loc.t("growth.memories"))
                            }
                            .font(FlowTheme.body(15)).foregroundStyle(FlowTheme.teal)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(FlowTheme.teal.opacity(0.5), lineWidth: 1.4))
                        }
                        .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.top, 18)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }.padding(16)
        }
        .sheet(isPresented: $showMemories) {
            MemoriesView(companionId: companion.id, companionName: companion.name).environmentObject(loc)
        }
        .task { await load() }
    }

    private var growthHeader: some View {
        VStack(spacing: 10) {
            Avatar(initials: companion.avatar, tint: companion.tintColor, size: 76, seed: 9, imageURL: companion.avatar_url)
            HStack(spacing: 6) {
                Text(companion.name).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                LevelBadge(level: companion.level, tint: companion.tintColor)
            }
            VStack(spacing: 4) {
                ExpBar(progress: companion.levelProgress, tint: companion.tintColor)
                    .frame(height: 6).padding(.horizontal, 40)
                Text("\(loc.t("growth.expLabel")) \(companion.exp) / \(companion.level_max_exp)")
                    .font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .sketchCard(20, fill: FlowTheme.card, seed: 11).padding(.horizontal, 16)
    }

    private var affinityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(loc.t("growth.affinity"), systemImage: "heart.fill")
                        .font(FlowTheme.heading(15)).foregroundStyle(FlowTheme.ink)
                    Spacer()
                    Text("\(affinity?.points ?? 0)").font(FlowTheme.body(15).weight(.bold)).foregroundStyle(FlowTheme.teal)
                }
                ExpBar(progress: affinity?.progress ?? 0, tint: FlowTheme.teal).frame(height: 6)
                Text(loc.t("growth.affinityHint")).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
            }.padding(16)
        }.padding(.horizontal, 16)
    }

    private var milestonesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.t("growth.milestones"), systemImage: "flag.checkered")
                    .font(FlowTheme.heading(15)).foregroundStyle(FlowTheme.ink)
                ForEach(milestones) { m in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(FlowTheme.teal).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.content).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                            Text(m.day).font(.system(size: 10)).foregroundStyle(FlowTheme.gray)
                        }
                        Spacer()
                    }
                }
            }.padding(16)
        }.padding(.horizontal, 16)
    }

    private var diaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.t("growth.diary"), systemImage: "book.closed")
                    .font(FlowTheme.heading(15)).foregroundStyle(FlowTheme.ink)
                ForEach(diary) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(d.content)”").font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                        Text(d.day).font(.system(size: 10)).foregroundStyle(FlowTheme.gray)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(16)
        }.padding(.horizontal, 16)
    }

    private var lineageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.t("growth.lineage"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(FlowTheme.heading(15)).foregroundStyle(FlowTheme.ink)
                if let nodes = lineage?.lineage, nodes.count > 1 {
                    ForEach(Array(nodes.enumerated()), id: \.offset) { idx, n in
                        HStack(spacing: 10) {
                            Image(systemName: n.is_current ? "leaf.fill" : "arrow.up")
                                .font(.system(size: 12)).foregroundStyle(FlowTheme.teal)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.name).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                                if let p = n.publisher_name, !p.isEmpty {
                                    Text("\(loc.t("growth.byOwner"))\(p)").font(.system(size: 10)).foregroundStyle(FlowTheme.gray)
                                } else if n.is_current {
                                    Text(loc.t("growth.thisOne")).font(.system(size: 10)).foregroundStyle(FlowTheme.gray)
                                }
                            }
                            Spacer()
                        }
                    }
                } else {
                    Text(loc.t("growth.lineageEmpty")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                }
            }.padding(16)
        }.padding(.horizontal, 16)
    }

    private func load() async {
        async let a = try? await APIClient.shared.companionAffinity(companion.id)
        async let m = (try? await APIClient.shared.companionMilestones(companion.id)) ?? []
        async let d = (try? await APIClient.shared.companionDiary(companion.id)) ?? []
        async let l = try? await APIClient.shared.companionLineage(companion.id)
        let (av, ms, dy, lin) = await (a, m, d, l)
        await MainActor.run {
            affinity = av; milestones = ms; diary = dy; lineage = lin
        }
    }
}
