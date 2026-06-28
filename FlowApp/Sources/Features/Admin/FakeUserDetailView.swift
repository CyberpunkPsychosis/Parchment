import SwiftUI
import PhotosUI

/// 替某个假用户发朋友圈 / 建搭子 / 建群；也可删除该假用户。
struct FakeUserDetailView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let user: AdminFakeUser
    var onChanged: () -> Void

    @State private var sheet: Action?
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
                            Avatar(initials: String(user.nickname.prefix(1)), tint: FlowTheme.teal, size: 54, imageURL: user.avatar_url)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.nickname).font(.system(size: 17, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                if let b = user.bio, !b.isEmpty { Text(b).font(FlowTheme.caption(12)).foregroundStyle(FlowTheme.gray) }
                            }
                            Spacer()
                        }.padding(18)
                    }
                    actionRow("photo.on.rectangle", loc.t("admin.postMoment")) { sheet = .moment }
                    actionRow("sparkles", loc.t("admin.makeCompanion")) { sheet = .companion }
                    actionRow("person.3", loc.t("admin.makeGroup")) { sheet = .group }
                    Button(role: .destructive) { showDelete = true } label: {
                        HStack { Image(systemName: "trash"); Text(loc.t("admin.deleteUser")) }
                            .font(FlowTheme.body(15)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.4), lineWidth: 1.3))
                    }
                }.padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .navigationTitle(user.nickname).navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(FlowTheme.caption(13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(FlowTheme.teal)).padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.4), value: toast)
        .sheet(item: $sheet) { a in
            ComposeAsFakeView(uid: user.id, action: a) { msg in flash(msg); onChanged() }.environmentObject(loc)
        }
        .alert(loc.t("admin.deleteUser"), isPresented: $showDelete) {
            Button(loc.t("admin.deleteUser"), role: .destructive) {
                Task { try? await APIClient.shared.adminDeleteFakeUser(uid: user.id); await MainActor.run { onChanged(); dismiss() } }
            }
            Button(loc.t("common.cancel"), role: .cancel) {}
        }
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
    private func flash(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await MainActor.run { toast = nil } }
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
                    }.disabled(saving || f1.trimmingCharacters(in: .whitespaces).isEmpty)
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
        Task {
            do {
                switch action {
                case .moment:
                    try await APIClient.shared.adminPostMoment(uid: uid, content: a, imageURL: imageURL)
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
