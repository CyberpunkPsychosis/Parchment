import SwiftUI
import PhotosUI

/// 编辑个人资料：头像（上传）+ 昵称 + 个性签名。
struct EditProfileView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var bio = ""
    @State private var avatarURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false

    private var initials: String {
        let n = nickname.isEmpty ? "U" : nickname
        return String(n.prefix(n.first.map { $0.isASCII ? 2 : 1 } ?? 1)).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Text(loc.t("common.cancel")).foregroundStyle(FlowTheme.gray) }
                Spacer()
                Text(loc.t("profile.edit")).font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { save() } label: { Text(loc.t("profile.save")).fontWeight(.semibold).foregroundStyle(FlowTheme.teal) }
                    .disabled(saving)
            }
            .padding(20)

            ScrollView {
                VStack(spacing: 20) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(initials: initials, tint: FlowTheme.teal, size: 96, seed: 7, imageURL: avatarURL)
                            Image(systemName: uploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                                .font(.system(size: 13)).foregroundStyle(.white)
                                .padding(7).background(Circle().fill(FlowTheme.teal))
                        }
                    }
                    .padding(.top, 12)

                    field(loc.t("profile.nickname"), text: $nickname, seed: 31)
                    field(loc.t("profile.signature"), text: $bio, seed: 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(PaperBackground())
        .onAppear {
            nickname = auth.user?.nickname ?? ""
            bio = auth.user?.bio ?? ""
            avatarURL = auth.user?.avatar_url
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            uploading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let url = try? await APIClient.shared.uploadImage(data) {
                    await MainActor.run { avatarURL = url }
                }
                await MainActor.run { uploading = false; photoItem = nil }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, seed: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            TextField(title, text: text)
                .font(FlowTheme.body(16))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
                .sketchBorder(14, width: 1.3, seed: seed)
        }
    }

    private func save() {
        saving = true
        Task {
            await auth.updateProfile(nickname: nickname.trimmingCharacters(in: .whitespaces),
                                     avatarURL: avatarURL ?? "", bio: bio)
            await MainActor.run { saving = false; dismiss() }
        }
    }
}
