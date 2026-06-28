import SwiftUI

/// 发布搭子到认领市场：勾选要公开分享的记忆（隐私控制），再发布。
struct PublishView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let companion: Companion

    @State private var memories: [Memory] = []
    @State private var loading = true
    @State private var publishing = false
    @State private var done = false
    @State private var error: String?

    private let minMemories = 8   // 与后端 MIN_PUBLISH_MEMORIES 保持一致
    private var shareableCount: Int { memories.filter { $0.visibility == "shareable" }.count }
    private var enoughMemories: Bool { memories.count >= minMemories }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(loc.t("publish.title")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                    Text(loc.t("publish.subtitle")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 18).padding(.horizontal, 24)

                if loading {
                    Spacer(); ProgressView().tint(FlowTheme.teal); Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            if memories.isEmpty {
                                Text(loc.t("publish.noMem")).font(FlowTheme.caption(13))
                                    .foregroundStyle(FlowTheme.gray).padding(.top, 30)
                            }
                            ForEach(memories) { m in memoryRow(m) }
                        }
                        .padding(16)
                    }
                }

                if !loading && !enoughMemories {
                    Text("\(loc.t("publish.gate"))（\(memories.count)/\(minMemories)）")
                        .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                if let error {
                    Text(error).font(FlowTheme.caption(12)).foregroundStyle(.red)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }

                Button(action: publish) {
                    ZStack {
                        PrimaryButton(title: done ? loc.t("publish.done")
                                      : "\(loc.t("publish.cta"))（\(loc.t("publish.share"))\(shareableCount)）")
                            .opacity(publishing || !enoughMemories ? 0.5 : 1)
                        if publishing { ProgressView().tint(.white) }
                    }
                }
                .disabled(publishing || loading || !enoughMemories)
                .padding(.horizontal, 16).padding(.bottom, 8)

                Text(loc.t("publish.privacyNote"))
                    .font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 20)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }.padding(16)
        }
        .task { await load() }
    }

    private func memoryRow(_ m: Memory) -> some View {
        let shareable = m.visibility == "shareable"
        return Button { toggle(m) } label: {
            HStack(spacing: 10) {
                Image(systemName: shareable ? "globe" : "lock.fill")
                    .font(.system(size: 13)).foregroundStyle(shareable ? FlowTheme.teal : FlowTheme.gray)
                Text(m.content).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text(loc.t(shareable ? "publish.shared" : "publish.private"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(shareable ? FlowTheme.teal : FlowTheme.gray)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .sketchCard(14, fill: shareable ? FlowTheme.teal.opacity(0.08) : FlowTheme.card,
                        seed: UInt64(m.id + 40))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true
        memories = (try? await APIClient.shared.listMemories(companionId: companion.id)) ?? []
        loading = false
    }

    private func toggle(_ m: Memory) {
        let want = m.visibility != "shareable"
        Task {
            if let updated = try? await APIClient.shared.setMemoryVisibility(id: m.id, shareable: want) {
                await MainActor.run {
                    if let i = memories.firstIndex(where: { $0.id == m.id }) { memories[i] = updated }
                }
            }
        }
    }

    private func publish() {
        guard enoughMemories else { return }
        publishing = true; error = nil
        Task {
            do {
                try await APIClient.shared.publishCompanion(id: companion.id)
                done = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run { publishing = false; dismiss() }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; publishing = false }
            }
        }
    }
}
