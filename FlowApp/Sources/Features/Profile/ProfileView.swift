import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var showStickers = false
    @State private var showEdit = false

    private var initials: String {
        let name = auth.user?.nickname ?? "U"
        return String(name.prefix(name.first.map { $0.isASCII ? 2 : 1 } ?? 1)).uppercased()
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    profileCard
                    editEntry
                    stickersEntry
                    settingsCard
                    if let user = auth.user, !user.isPro {
                        upgradeCard
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }
            .padding(18)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(loc).environmentObject(auth)
        }
        .sheet(isPresented: $showStickers) {
            StickerPanelView().environmentObject(loc).environmentObject(auth)
        }
        .sheet(isPresented: $showEdit) {
            EditProfileView().environmentObject(loc).environmentObject(auth)
        }
    }

    private var editEntry: some View {
        Button { showEdit = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(FlowTheme.tealDark)
                Text(loc.t("profile.edit")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(FlowTheme.card))
            .sketchBorder(20, width: 1.4, seed: 10)
        }
        .buttonStyle(.plain)
    }

    private var stickersEntry: some View {
        Button { showStickers = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "face.smiling").font(.system(size: 20)).foregroundStyle(FlowTheme.tealDark)
                Text(loc.t("profile.stickers")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(FlowTheme.card))
            .sketchBorder(20, width: 1.4, seed: 9)
        }
        .buttonStyle(.plain)
    }

    private var profileCard: some View {
        Card {
            VStack(spacing: 18) {
                Avatar(initials: initials, tint: FlowTheme.teal, size: 84, seed: 7, imageURL: auth.user?.avatar_url)
                    .padding(.top, 20)

                VStack(spacing: 5) {
                    Text(auth.user?.nickname ?? "")
                        .font(FlowTheme.heading(22)).foregroundStyle(FlowTheme.ink)
                    HStack(spacing: 6) {
                        Image(systemName: auth.isPro ? "crown.fill" : "person")
                            .font(.system(size: 11))
                            .foregroundStyle(auth.isPro ? FlowTheme.teal : FlowTheme.gray)
                        Text(loc.t(auth.isPro ? "auth.member.pro" : "auth.member.free"))
                            .font(FlowTheme.caption(13)).foregroundStyle(auth.isPro ? FlowTheme.teal : FlowTheme.gray)
                    }
                    if let bio = auth.user?.bio, !bio.isEmpty {
                        Text(bio).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                            .multilineTextAlignment(.center).padding(.top, 2)
                    }
                }

                Divider().overlay(FlowTheme.stroke)

                infoRow(icon: "envelope", text: auth.user?.email ?? "—")
                if auth.isPro, let exp = auth.user?.tier_expiry {
                    infoRow(icon: "calendar", text: loc.t("membership.expiry") + " " + String(exp.prefix(10)))
                }
            }
            .padding(18)
        }
    }

    private var settingsCard: some View {
        Card {
            Toggle(isOn: Binding(
                get: { auth.user?.auto_send_stickers ?? false },
                set: { auth.setAutoSendStickers($0) }
            )) {
                Text(loc.t("sticker.autoSetting")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
            }
            .toggleStyle(FlowToggleStyle())
            .padding(18)
        }
    }

    private var upgradeCard: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").font(.system(size: 20)).foregroundStyle(FlowTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("paywall.title")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                    Text(loc.t("paywall.subtitle")).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(FlowTheme.teal.opacity(0.08)))
            .sketchBorder(20, width: 1.4, seed: 8)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(FlowTheme.teal).frame(width: 20)
            Text(text).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
            Spacer()
        }
    }
}
