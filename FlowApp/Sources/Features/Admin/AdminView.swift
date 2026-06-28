import SwiftUI
import PhotosUI

/// 运营后台：建假用户、批量生成、每日滑入、一键清空；进入某假用户可替他发内容。
struct AdminView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss

    @State private var stats: AdminStats?
    @State private var users: [AdminFakeUser] = []
    @State private var loading = true
    @State private var busy = false
    @State private var showCreate = false
    @State private var showWipeConfirm = false
    @State private var route: AdminFakeUser?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        statsCard
                        actions
                        usersSection
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
            }
            .navigationTitle(loc.t("admin.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("common.done")) { dismiss() }
                }
            }
            .navigationDestination(item: $route) { u in
                FakeUserDetailView(user: u) { Task { await reload() } }.environmentObject(loc)
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(FlowTheme.teal)).padding(.top, 8)
                }
            }
            .animation(.spring(response: 0.4), value: toast)
            .task { await reload() }
            .sheet(isPresented: $showCreate) {
                CreateFakeUserView { Task { await reload() } }.environmentObject(loc)
            }
            .alert(loc.t("admin.wipeConfirm"), isPresented: $showWipeConfirm) {
                Button(loc.t("admin.wipe"), role: .destructive) { wipe() }
                Button(loc.t("common.cancel"), role: .cancel) {}
            } message: { Text(loc.t("admin.wipeMsg")) }
        }
    }

    private var statsCard: some View {
        Card {
            HStack(spacing: 20) {
                stat("\(stats?.real_users ?? 0)", loc.t("admin.realUsers"))
                stat("\(stats?.fake_users ?? 0)", loc.t("admin.fakeUsers"))
                stat("\(stats?.posts ?? 0)", loc.t("admin.posts"))
            }.frame(maxWidth: .infinity).padding(18)
        }
    }
    private func stat(_ n: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(n).font(FlowTheme.title(24)).foregroundStyle(FlowTheme.ink)
            Text(label).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { showCreate = true } label: {
                rowLabel("plus.circle", loc.t("admin.newFakeUser"), FlowTheme.teal)
            }
            Button { generate(10) } label: {
                rowLabel("wand.and.stars", loc.t("admin.generate10"), FlowTheme.teal)
            }.disabled(busy)
            Button { dailyTick() } label: {
                rowLabel("calendar.badge.plus", loc.t("admin.dailyTick"), FlowTheme.teal)
            }.disabled(busy)
            Button { showWipeConfirm = true } label: {
                rowLabel("trash", loc.t("admin.wipe"), .red)
            }.disabled(busy)
        }
    }
    private func rowLabel(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(FlowTheme.body(15)).foregroundStyle(color)
            Spacer()
            if busy { ProgressView().tint(FlowTheme.teal) }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.card)).sketchBorder(14, width: 1.2, seed: 71)
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("admin.fakeUserList")).font(FlowTheme.caption(13).weight(.bold)).foregroundStyle(FlowTheme.gray)
            if loading {
                ProgressView().tint(FlowTheme.teal).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if users.isEmpty {
                Text(loc.t("admin.empty")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(users) { u in
                    Button { route = u } label: { userRow(u) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func userRow(_ u: AdminFakeUser) -> some View {
        HStack(spacing: 11) {
            Avatar(initials: String(u.nickname.prefix(1)), tint: FlowTheme.teal, size: 42, imageURL: u.avatar_url)
            VStack(alignment: .leading, spacing: 3) {
                Text(u.nickname).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                Text("\(loc.t("admin.posts"))\(u.post_count) · 搭子\(u.companion_count) · 群\(u.group_count)")
                    .font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .sketchCard(16, fill: FlowTheme.card, seed: UInt64(u.id + 300))
    }

    private func reload() async {
        loading = true
        let s = try? await APIClient.shared.adminStats()
        let us = (try? await APIClient.shared.adminListFakeUsers()) ?? []
        await MainActor.run { stats = s; users = us; loading = false }
    }
    private func flash(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); await MainActor.run { toast = nil } }
    }
    private func generate(_ n: Int) {
        busy = true
        Task { try? await APIClient.shared.adminGenerate(count: n); await reload(); await MainActor.run { busy = false; flash(loc.t("admin.done")) } }
    }
    private func dailyTick() {
        busy = true
        Task { try? await APIClient.shared.adminDailyTick(); await reload(); await MainActor.run { busy = false; flash(loc.t("admin.done")) } }
    }
    private func wipe() {
        busy = true
        Task { try? await APIClient.shared.adminWipeAllFakeData(); await reload(); await MainActor.run { busy = false; flash(loc.t("admin.wiped")) } }
    }
}

/// 新建单个假用户（名/签名/头像可选上传，不传则后端从素材池分配）。
struct CreateFakeUserView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void
    @State private var nickname = ""
    @State private var bio = ""
    @State private var avatarURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(initials: String(nickname.prefix(1)).uppercased(), tint: FlowTheme.teal, size: 72, imageURL: avatarURL)
                            ZStack { Circle().fill(FlowTheme.teal).frame(width: 24, height: 24)
                                Image(systemName: uploading ? "arrow.up" : "camera.fill").font(.system(size: 11)).foregroundStyle(.white) }
                        }
                    }.padding(.top, 24)
                    Card {
                        VStack(spacing: 14) {
                            field(loc.t("admin.nickname"), text: $nickname)
                            field(loc.t("admin.bio"), text: $bio)
                            Text(loc.t("admin.avatarHint")).font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(18)
                    }.padding(.horizontal, 16)
                    Button(action: save) {
                        ZStack { PrimaryButton(title: loc.t("admin.create")); if saving { ProgressView().tint(.white) } }
                    }.disabled(saving).padding(.horizontal, 16)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6)) }.padding(16)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            uploading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let url = try? await APIClient.shared.uploadImage(data) { await MainActor.run { avatarURL = url } }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
    }
    private func field(_ ph: String, text: Binding<String>) -> some View {
        TextField(ph, text: text).font(FlowTheme.body(15))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field)).sketchBorder(12, width: 1.3, seed: 31)
    }
    private func save() {
        saving = true
        let n = nickname.trimmingCharacters(in: .whitespaces)
        let b = bio.trimmingCharacters(in: .whitespaces)
        Task {
            _ = try? await APIClient.shared.adminCreateFakeUser(nickname: n.isEmpty ? nil : n, bio: b.isEmpty ? nil : b, avatarURL: avatarURL)
            await MainActor.run { saving = false; onSaved(); dismiss() }
        }
    }
}
