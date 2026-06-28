import SwiftUI

/// 查看 / 管理某搭子的记忆。
struct MemoriesView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let companionId: Int
    let companionName: String

    @State private var memories: [Memory] = []
    @State private var loading = true
    @State private var newMemory = ""

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text(loc.t("memories.title")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                    Text(companionName + loc.t("memories.subtitle")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                }
                .padding(.top, 18)

                // 手动添加
                HStack(spacing: 8) {
                    TextField(loc.t("memories.addHint"), text: $newMemory)
                        .font(FlowTheme.body(14))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
                        .sketchBorder(14, width: 1.3, seed: 53)
                    Button { add() } label: {
                        PillButton(title: loc.t("memories.add"), radius: 18, seed: 54)
                            .opacity(newMemory.isEmpty ? 0.5 : 1)
                    }.disabled(newMemory.isEmpty)
                }
                .padding(.horizontal, 16)

                if loading {
                    Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
                } else if memories.isEmpty {
                    Spacer()
                    Text(loc.t("memories.empty")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(memories) { m in row(m) }
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

    private func row(_ m: Memory) -> some View {
        let shareable = m.visibility == "shareable"
        return HStack(spacing: 10) {
            Image(systemName: m.origin != nil ? "arrow.triangle.branch"
                  : (m.source == "manual" ? "hand.point.up.left" : "sparkles"))
                .font(.system(size: 13)).foregroundStyle(FlowTheme.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.content).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                if let o = m.origin {
                    Text("\(loc.t("memories.from"))\(o)")
                        .font(.system(size: 10)).foregroundStyle(FlowTheme.teal)
                }
            }
            Spacer()
            // 分享/私密 切换（认领时只有"分享"的会被公开）
            Button { Task { await toggleShare(m) } } label: {
                Image(systemName: shareable ? "globe" : "lock.fill")
                    .font(.system(size: 12)).foregroundStyle(shareable ? FlowTheme.teal : FlowTheme.gray.opacity(0.7))
            }
            Button { Task { await remove(m) } } label: {
                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(FlowTheme.gray)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .sketchCard(14, fill: FlowTheme.card, seed: UInt64(m.id + 40))
    }

    private func toggleShare(_ m: Memory) async {
        if let updated = try? await APIClient.shared.setMemoryVisibility(
            id: m.id, shareable: m.visibility != "shareable") {
            if let i = memories.firstIndex(where: { $0.id == m.id }) { memories[i] = updated }
        }
    }

    private func load() async {
        loading = true
        memories = (try? await APIClient.shared.listMemories(companionId: companionId)) ?? []
        loading = false
    }

    private func add() {
        let c = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        newMemory = ""
        Task {
            if let m = try? await APIClient.shared.addMemory(companionId: companionId, content: c) {
                await MainActor.run { memories.insert(m, at: 0) }
            }
        }
    }

    private func remove(_ m: Memory) async {
        try? await APIClient.shared.deleteMemory(id: m.id)
        await load()
    }
}
