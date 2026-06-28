import SwiftUI

struct CompanionsView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore

    @State private var companions: [Companion] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var publishTarget: Companion?
    @State private var detailTarget: Companion?
    @State private var editTarget: Companion?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if loading {
                    Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(companions.enumerated()), id: \.element.id) { idx, c in
                                NavigationLink(value: c) {
                                    CompanionRow(companion: c, seed: UInt64(idx + 100))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { detailTarget = c } label: {
                                        Label(loc.t("growth.profile"), systemImage: "chart.line.uptrend.xyaxis")
                                    }
                                    Button { editTarget = c } label: {
                                        Label(loc.t("companion.edit"), systemImage: "pencil")
                                    }
                                    Button { publishTarget = c } label: {
                                        Label(loc.t("publish.menu"), systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) { delete(c) } label: {
                                        Label(loc.t("companion.delete"), systemImage: "trash")
                                    }
                                }
                            }
                            createButton
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 96)
                    }
                }
            }
            .background(PaperBackground())
            .navigationDestination(for: Companion.self) { c in
                ChatDetailView(
                    chat: c.asChat,
                    persona: c.persona,
                    companionId: c.id,
                    seedMessages: c.greeting.isEmpty ? [] : [Message(kind: .text(c.greeting), mine: false, time: "")]
                )
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateCompanionView { c in companions.append(c) }
                .environmentObject(loc)
        }
        .sheet(item: $editTarget) { c in
            CreateCompanionView(editing: c) { updated in
                if let i = companions.firstIndex(where: { $0.id == updated.id }) { companions[i] = updated }
            }.environmentObject(loc)
        }
        .sheet(item: $publishTarget) { c in
            PublishView(companion: c).environmentObject(loc)
        }
        .sheet(item: $detailTarget) { c in
            CompanionDetailView(companion: c).environmentObject(loc)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(loc.t("companions.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
            Text(loc.t("companions.subtitle")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
    }

    private var createButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(loc.t("companions.create"))
            }
            .font(FlowTheme.body(15)).foregroundStyle(FlowTheme.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(FlowTheme.teal.opacity(0.6)))
        }
    }

    private func load() async {
        loading = true
        companions = (try? await APIClient.shared.listCompanions()) ?? []
        loading = false
    }

    private func delete(_ c: Companion) {
        companions.removeAll { $0.id == c.id }
        Task { try? await APIClient.shared.deleteCompanion(id: c.id) }
    }
}

struct CompanionRow: View {
    @EnvironmentObject var loc: Localization
    let companion: Companion
    var seed: UInt64 = 100

    var body: some View {
        HStack(spacing: 12) {
            Avatar(initials: companion.avatar, tint: companion.tintColor, size: 46, seed: seed, imageURL: companion.avatar_url)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(companion.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FlowTheme.ink)
                    LevelBadge(level: companion.level, stage: companion.stage, tint: companion.tintColor)
                }
                Text(companion.memory_count > 0
                     ? "\(loc.t("companion.memoryCount"))\(companion.memory_count)"
                     : companion.greeting)
                    .font(FlowTheme.caption(13))
                    .foregroundStyle(FlowTheme.gray)
                    .lineLimit(1)
                ExpBar(progress: companion.levelProgress, tint: companion.tintColor)
            }
            Spacer(minLength: 8)
            Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(FlowTheme.teal)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .sketchCard(18, fill: FlowTheme.card, seed: seed)
    }
}

/// 等级 + 阶段小徽章。
struct LevelBadge: View {
    let level: Int
    let stage: String
    var tint: Color = FlowTheme.teal
    var body: some View {
        HStack(spacing: 4) {
            Text("Lv.\(level)").font(.system(size: 10, weight: .bold))
            Text(stage).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(tint))
    }
}

/// 经验进度条（细，手绘描边）。
struct ExpBar: View {
    let progress: Double
    var tint: Color = FlowTheme.teal
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FlowTheme.ink.opacity(0.08))
                Capsule().fill(tint.opacity(0.85))
                    .frame(width: max(3, geo.size.width * progress))
            }
        }
        .frame(height: 4)
    }
}
