import SwiftUI

/// 会员付费墙。复用手绘组件。当前为 mock 支付（点击直接升级）。
struct PaywallView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    /// 顶部提示语（如从"次数用完"进入时显示）
    var headline: String? = nil

    @State private var info: MembershipInfo?
    @State private var selected: String = "yearly"
    @State private var buying = false
    @State private var error: String?
    @State private var done = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if let benefits = info?.benefits {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(benefits, id: \.self) { b in
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(FlowTheme.teal)
                                        Text(b.text(loc.lang)).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(18)
                        }
                        .padding(.horizontal, 20)
                    }

                    if let plans = info?.plans {
                        VStack(spacing: 12) {
                            ForEach(plans) { plan in
                                planCard(plan)
                            }
                        }
                        .padding(.horizontal, 20)
                    } else {
                        ProgressView().tint(FlowTheme.teal).padding(40)
                    }

                    if let error {
                        Text(error).font(FlowTheme.caption(13)).foregroundStyle(.red)
                    }

                    Button(action: buy) {
                        ZStack {
                            PrimaryButton(title: loc.t(buying ? "paywall.buying" : "paywall.cta"))
                                .opacity(buying || info == nil ? 0.5 : 1)
                            if buying { ProgressView().tint(.white) }
                        }
                    }
                    .disabled(buying || info == nil)
                    .padding(.horizontal, 20)

                    Text(loc.t("paywall.note"))
                        .font(FlowTheme.caption(11))
                        .foregroundStyle(FlowTheme.gray)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                }
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }
            .padding(20)
        }
        .task { info = try? await APIClient.shared.membershipInfo() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill").font(.system(size: 40)).foregroundStyle(FlowTheme.teal)
            Text(loc.t(done ? "paywall.success" : "paywall.title"))
                .font(FlowTheme.title(26)).foregroundStyle(FlowTheme.ink)
            Text(headline ?? loc.t("paywall.subtitle"))
                .font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private func planCard(_ plan: MembershipPlan) -> some View {
        let isSel = selected == plan.id
        return Button { selected = plan.id } label: {
            HStack(spacing: 14) {
                Image(systemName: isSel ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSel ? FlowTheme.teal : FlowTheme.gray)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name(loc.lang)).font(.system(size: 16, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                    Text(plan.desc(loc.lang)).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                }
                Spacer()
                Text("¥\(plan.price_cny)")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(FlowTheme.teal)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(isSel ? FlowTheme.teal.opacity(0.08) : FlowTheme.card))
            .sketchBorder(16, width: isSel ? 1.8 : 1.3, seed: plan.id == "yearly" ? 91 : 92)
        }
        .buttonStyle(.plain)
    }

    private func buy() {
        buying = true
        error = nil
        Task {
            do {
                try await auth.purchase(planId: selected)
                done = true
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            buying = false
        }
    }
}
