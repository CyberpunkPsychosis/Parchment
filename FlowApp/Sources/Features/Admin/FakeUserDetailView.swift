import SwiftUI
import PhotosUI

/// 假用户详情：编辑资料(头像/昵称/签名/城市)、替他发/改/删朋友圈、建搭子、建群、删除该用户。
struct FakeUserDetailView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let onChanged: () -> Void
    @State private var u: AdminFakeUser

    init(user: AdminFakeUser, onChanged: @escaping () -> Void) {
        self.onChanged = onChanged
        _u = State(initialValue: user)
    }

    @State private var sheet: Action?
    @State private var editingUser = false
    @State private var editingMoment: AdminMoment?
    @State private var moments: [AdminMoment] = []
    @State private var showDelete = false
    @State private var toast: String?

    enum Action: String, Identifiable { case moment, companion, group; var id: String { rawValue } }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        HStack(spacing: 12) {
                            Avatar(initials: String(u.nickname.prefix(1)), tint: FlowTheme.teal, size: 54, imageURL: u.avatar_url)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(u.nickname).font(.system(size: 17, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                if let c = u.city, !c.isEmpty {
                                    Text("📍\(c)").font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray)
                                }
                                if let b = u.bio, !b.isEmpty { Text(b).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray) }
                            }
                            Spacer()
                        }.padding(18)
                    }
                    actionRow("pencil", loc.t("admin.editProfile")) { editingUser = true }
                    actionRow("photo.on.rectangle", loc.t("admin.postMoment")) { sheet = .moment }
                    actionRow("sparkles", loc.t("admin.makeCompanion")) { sheet = .companion }
                    actionRow("person.3", loc.t("admin.makeGroup")) { sheet = .group }

                    momentsSection

                    Button(role: .destructive) { showDelete = true } label: {
                        HStack { Image(systemName: "trash"); Text(loc.t("admin.deleteUser")) }
                            .font(FlowTheme.body(15)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.4), lineWidth: 1.3))
                    }
                }.padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .navigationTitle(u.nickname).navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(FlowTheme.teal)).padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.4), value: toast)
        .task { await loadMoments() }
        .sheet(item: $sheet) { a in
            ComposeAsFakeView(uid: u.id, action: a) { msg in flash(msg); onChanged(); Task { await loadMoments() } }.environmentObject(loc)
        }
        .sheet(isPresented: $editingUser) {
            EditFakeUserView(user: u) { updated in u = updated; onChanged() }.environmentObject(loc)
        }
        .sheet(item: $editingMoment) { m in
            EditFakeMomentView(moment: m) { flash(loc.t("admin.done")); onChanged(); Task { await loadMoments() } }.environmentObject(loc)
        }
        .alert(loc.t("admin.deleteUser"), isPresented: $showDelete) {
            Button(loc.t("admin.deleteUser"), role: .destructive) {
                Task { try? await APIClient.shared.adminDeleteFakeUser(uid: u.id); await MainActor.run { onChanged(); dismiss() } }
            }
            Button(loc.t("common.cancel"), role: .cancel) {}
        }
    }

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("admin.momentList")).font(FlowTheme.caption(13).weight(.bold)).foregroundStyle(FlowTheme.gray)
            if moments.isEmpty {
                Text(loc.t("admin.noMoments")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            } else {
                ForEach(moments) { m in
                    Button { editingMoment = m } label: { momentRow(m) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func momentRow(_ m: AdminMoment) -> some View {
        HStack(spacing: 10) {
            if let url = m.image_url, let uu = URL(string: url) {
                AsyncImage(url: uu) { i in i.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(FlowTheme.beige).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "text.alignleft").font(.system(size: 13)).foregroundStyle(FlowTheme.gray))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.content.isEmpty ? "[图片]" : m.content).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.ink).lineLimit(1)
                if let l = m.location, !l.isEmpty { Text("📍\(l)").font(FlowTheme.caption(11)).foregroundStyle(FlowTheme.gray) }
            }
            Spacer(); Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(FlowTheme.gray)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.card)).sketchBorder(12, width: 1, seed: UInt64(m.id + 500))
    }

    private func actionRow(_ icon: String, _ text: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(FlowTheme.teal)
                Text(text).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.card)).sketchBorder(14, width: 1.2, seed: 72)
        }
    }
    private func loadMoments() async {
        let m = (try? await APIClient.shared.adminUserMoments(uid: u.id)) ?? []
        await MainActor.run { moments = m }
    }
    private func flash(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await MainActor.run { toast = nil } }
    }
}

/// 编辑假用户资料：头像(上传) + 昵称 + 签名 + 城市。
struct EditFakeUserView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let user: AdminFakeUser
    var onSaved: (AdminFakeUser) -> Void

    @State private var nickname: String
    @State private var bio: String
    @State private var city: String
    @State private var avatarURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false

    init(user: AdminFakeUser, onSaved: @escaping (AdminFakeUser) -> Void) {
        self.user = user; self.onSaved = onSaved
        _nickname = State(initialValue: user.nickname)
        _bio = State(initialValue: user.bio ?? "")
        _city = State(initialValue: user.city ?? "")
        _avatarURL = State(initialValue: user.avatar_url)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(initials: String(nickname.prefix(1)), tint: FlowTheme.teal, size: 80, imageURL: avatarURL)
                            ZStack { Circle().fill(FlowTheme.teal).frame(width: 26, height: 26)
                                Image(systemName: uploading ? "arrow.up" : "camera.fill").font(.system(size: 12)).foregroundStyle(.white) }
                        }
                    }.padding(.top, 24)
                    Card {
                        VStack(spacing: 14) {
                            field(loc.t("admin.nickname"), text: $nickname)
                            field(loc.t("profile.signature"), text: $bio)
                            field(loc.t("profile.city"), text: $city)
                        }.padding(18)
                    }.padding(.horizontal, 16)
                    Button(action: save) {
                        ZStack { PrimaryButton(title: loc.t("admin.save")); if saving { ProgressView().tint(.white) } }
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
            .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field)).sketchBorder(12, width: 1.3, seed: 35)
    }
    private func save() {
        saving = true
        Task {
            let updated = try? await APIClient.shared.adminUpdateFakeUser(
                uid: user.id, nickname: nickname.trimmingCharacters(in: .whitespaces),
                bio: bio, city: city.trimmingCharacters(in: .whitespaces), avatarURL: avatarURL ?? "")
            await MainActor.run { saving = false; if let updated { onSaved(updated) }; dismiss() }
        }
    }
}

/// 编辑已发布的朋友圈：正文 + 配图(上传/替换) + 地点；可删除。
struct EditFakeMomentView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let moment: AdminMoment
    var onChanged: () -> Void

    @State private var content: String
    @State private var location: String
    @State private var imageURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var showDelete = false

    init(moment: AdminMoment, onChanged: @escaping () -> Void) {
        self.moment = moment; self.onChanged = onChanged
        _content = State(initialValue: moment.content)
        _location = State(initialValue: moment.location ?? "")
        _imageURL = State(initialValue: moment.image_url)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Text(loc.t("admin.editMoment")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("admin.momentText")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                TextEditor(text: $content).font(FlowTheme.body(15)).frame(height: 90).scrollContentBackground(.hidden)
                                    .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field)).sketchBorder(12, width: 1.3, seed: 36)
                            }
                            if let url = imageURL, let uu = URL(string: url) {
                                AsyncImage(url: uu) { i in i.resizable().scaledToFill() } placeholder: { FlowTheme.beige }
                                    .frame(height: 140).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                HStack { Image(systemName: uploading ? "arrow.up" : "photo")
                                    Text(imageURL == nil ? loc.t("admin.addImage") : loc.t("admin.replaceImage")) }
                                    .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.teal)
                            }
                            TextField(loc.t("admin.location"), text: $location).font(FlowTheme.body(15))
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field)).sketchBorder(12, width: 1.3, seed: 37)
                        }.padding(18)
                    }
                    Button(action: save) {
                        ZStack { PrimaryButton(title: loc.t("admin.save")); if saving { ProgressView().tint(.white) } }
                    }.disabled(saving)
                    Button(role: .destructive) { showDelete = true } label: {
                        Text(loc.t("admin.deleteMoment")).font(FlowTheme.body(15)).foregroundStyle(.red)
                    }
                }.padding(16)
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
                   let url = try? await APIClient.shared.uploadImage(data) { await MainActor.run { imageURL = url } }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
        .alert(loc.t("admin.deleteMoment"), isPresented: $showDelete) {
            Button(loc.t("admin.deleteMoment"), role: .destructive) {
                Task { try? await APIClient.shared.adminDeleteMoment(pid: moment.id); await MainActor.run { onChanged(); dismiss() } }
            }
            Button(loc.t("common.cancel"), role: .cancel) {}
        }
    }
    private func save() {
        saving = true
        Task {
            try? await APIClient.shared.adminUpdateMoment(
                pid: moment.id, content: content,
                imageURL: imageURL ?? "", location: location.trimmingCharacters(in: .whitespaces))
            await MainActor.run { saving = false; onChanged(); dismiss() }
        }
    }
}

/// 三合一的「替假用户发内容」表单：朋友圈 / 搭子 / 群。
struct ComposeAsFakeView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let uid: Int
    let action: FakeUserDetailView.Action
    var onDone: (String) -> Void

    @State private var f1 = ""        // moment content / companion name / group name
    @State private var f2 = ""        // companion persona / group description
    @State private var f3 = ""        // companion greeting
    @State private var loc1 = ""      // moment location
    @State private var imageURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Text(title).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Card {
                        VStack(spacing: 14) {
                            switch action {
                            case .moment:
                                editor(loc.t("admin.momentText"), text: $f1)
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    HStack { Image(systemName: uploading ? "arrow.up" : "photo")
                                        Text(imageURL == nil ? loc.t("admin.addImage") : loc.t("admin.imageAdded")) }
                                        .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.teal)
                                }
                                field(loc.t("admin.location"), text: $loc1)
                            case .companion:
                                field(loc.t("admin.companionName"), text: $f1)
                                editor(loc.t("admin.companionPersona"), text: $f2)
                                field(loc.t("admin.companionGreeting"), text: $f3)
                            case .group:
                                field(loc.t("admin.groupName"), text: $f1)
                                field(loc.t("admin.groupDesc"), text: $f2)
                            }
                        }.padding(18)
                    }
                    Button(action: submit) {
                        ZStack { PrimaryButton(title: loc.t("admin.submit")); if saving { ProgressView().tint(.white) } }
                    }.disabled(saving || (action != .moment && f1.trimmingCharacters(in: .whitespaces).isEmpty))
                }.padding(16)
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
                   let url = try? await APIClient.shared.uploadImage(data) { await MainActor.run { imageURL = url } }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
    }
    private var title: String {
        switch action { case .moment: return loc.t("admin.postMoment"); case .companion: return loc.t("admin.makeCompanion"); case .group: return loc.t("admin.makeGroup") }
    }
    private func field(_ ph: String, text: Binding<String>) -> some View {
        TextField(ph, text: text).font(FlowTheme.body(15))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field)).sketchBorder(12, width: 1.3, seed: 33)
    }
    private func editor(_ ph: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ph).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            TextEditor(text: text).font(FlowTheme.body(15)).frame(height: 90).scrollContentBackground(.hidden)
                .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field)).sketchBorder(12, width: 1.3, seed: 34)
        }
    }
    private func submit() {
        saving = true
        let a = f1.trimmingCharacters(in: .whitespaces)
        let b = f2.trimmingCharacters(in: .whitespaces)
        let c = f3.trimmingCharacters(in: .whitespaces)
        let lc = loc1.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                switch action {
                case .moment:
                    try await APIClient.shared.adminPostMoment(uid: uid, content: a, imageURL: imageURL, location: lc.isEmpty ? nil : lc)
                case .companion:
                    try await APIClient.shared.adminMakeCompanion(uid: uid, name: a, persona: b.isEmpty ? a : b, greeting: c, tint: "teal")
                case .group:
                    try await APIClient.shared.adminMakeGroup(uid: uid, name: a, description: b, memberSeedUsers: 6)
                }
                await MainActor.run { saving = false; onDone(loc.t("admin.done")); dismiss() }
            } catch {
                await MainActor.run { saving = false }
            }
        }
    }
}
