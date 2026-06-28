import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var theme: Theme
    @State private var showPaywall = false
    @State private var cacheText = "—"
    @State private var cacheCleared = false
    @State private var showBlocklist = false
    @State private var showAdmin = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("settings.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    // 外观：跟随系统 / 浅色 / 深色
                    Card {
                        HStack {
                            Text(loc.t("settings.appearance")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                            Spacer()
                            Picker("", selection: $theme.mode) {
                                ForEach(AppearanceMode.allCases) { Text(loc.t($0.key)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                        }
                        .padding(18)
                    }

                    Card {
                        // 清除缓存
                        Button { clearCache() } label: {
                            HStack {
                                Text(loc.t("settings.clearCache")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                                Spacer()
                                Text(cacheText).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
                            }
                            .padding(18)
                        }
                    }

                    // Language switch (中 / 英)
                    Card {
                        HStack {
                            Text(loc.t("settings.language")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                            Spacer()
                            Picker("", selection: Binding(get: { loc.lang }, set: { loc.set($0) })) {
                                ForEach(Lang.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        .padding(18)
                    }

                    // 运营后台（仅管理员可见）
                    if auth.user?.isAdmin == true {
                        Card {
                            Button { showAdmin = true } label: {
                                HStack {
                                    Image(systemName: "wand.and.stars").foregroundStyle(FlowTheme.teal)
                                    Text(loc.t("admin.title")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
                                }
                                .padding(18)
                            }
                        }
                    }

                    // 黑名单管理
                    Card {
                        Button { showBlocklist = true } label: {
                            HStack {
                                Text(loc.t("safety.blocklist")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
                            }
                            .padding(18)
                        }
                    }

                    // Account / membership
                    if let user = auth.user {
                        Card {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(user.nickname).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                                        Text(user.email).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                                    }
                                    Spacer()
                                    Text(loc.t(user.isPro ? "auth.member.pro" : "auth.member.free"))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(user.isPro ? .white : FlowTheme.gray)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 10)
                                            .fill(user.isPro ? FlowTheme.teal : FlowTheme.beige))
                                        .sketchBorder(10, width: 1, seed: 88)
                                }
                                if !user.isPro {
                                    Divider().overlay(FlowTheme.stroke)
                                    Button { showPaywall = true } label: {
                                        HStack {
                                            Image(systemName: "crown.fill").foregroundStyle(FlowTheme.teal)
                                            Text(loc.t("membership.upgrade"))
                                                .font(FlowTheme.body(16)).foregroundStyle(FlowTheme.teal)
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
                                        }
                                    }
                                } else if let exp = user.tier_expiry {
                                    Divider().overlay(FlowTheme.stroke)
                                    HStack {
                                        Text(loc.t("membership.expiry")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                        Spacer()
                                        Text(String(exp.prefix(10))).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                    }
                                }
                                Divider().overlay(FlowTheme.stroke)
                                Button { auth.logout() } label: {
                                    Text(loc.t("auth.logout"))
                                        .font(FlowTheme.body(16)).foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(18)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .background(PaperBackground())
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(loc).environmentObject(auth)
        }
        .sheet(isPresented: $showBlocklist) {
            BlockListView().environmentObject(loc)
        }
        .sheet(isPresented: $showAdmin) {
            AdminView().environmentObject(loc)
        }
        .alert(loc.t("settings.cacheCleared"), isPresented: $cacheCleared) {
            Button("OK", role: .cancel) {}
        }
        .onAppear { refreshCacheSize() }
    }

    private func refreshCacheSize() {
        let bytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        cacheText = bytes < 1024 ? "\(bytes) B"
            : bytes < 1024 * 1024 ? String(format: "%.0f KB", Double(bytes) / 1024)
            : String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        refreshCacheSize()
        cacheCleared = true
    }
}
