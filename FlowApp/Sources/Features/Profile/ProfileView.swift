import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var loc: Localization

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("profile.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    ContactCardView()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .background(PaperBackground())
    }
}

/// Contact / profile card reproduced from the design system sheet (陈亚历山大).
struct ContactCardView: View {
    @EnvironmentObject var loc: Localization

    var body: some View {
        Card {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Avatar(initials: "陈", tint: FlowTheme.sage, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.lang == .zh ? "陈亚历山大" : "Alexander Chen")
                            .font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                        Text(loc.t("profile.company"))
                            .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    }
                    Spacer()
                }

                Divider().overlay(FlowTheme.stroke)

                infoRow(icon: "number", text: "+1009003 Khatu")
                infoRow(icon: "phone", text: "(123) 455-7679")
                infoRow(icon: "envelope", text: "chioion@gmail.com")

                HStack {
                    Spacer()
                    Text(loc.t("profile.edit"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Capsule().fill(FlowTheme.teal))
                }
            }
            .padding(18)
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(FlowTheme.teal).frame(width: 20)
            Text(text).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
            Spacer()
        }
    }
}
