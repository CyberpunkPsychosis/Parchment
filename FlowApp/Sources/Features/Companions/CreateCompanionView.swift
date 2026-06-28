import SwiftUI
import PhotosUI

/// 创建 / 编辑自定义 AI 搭子。
struct CreateCompanionView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    /// 传入则为「编辑」模式
    var editing: Companion? = nil
    let onSaved: (Companion) -> Void

    @State private var name: String
    @State private var persona: String
    @State private var greeting: String
    @State private var tint: CompanionTint
    @State private var avatarURL: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var error: String?

    init(editing: Companion? = nil, onSaved: @escaping (Companion) -> Void) {
        self.editing = editing
        self.onSaved = onSaved
        _name = State(initialValue: editing?.name ?? "")
        _persona = State(initialValue: editing?.persona ?? "")
        _greeting = State(initialValue: editing?.greeting ?? "")
        _tint = State(initialValue: CompanionTint(rawValue: editing?.tint ?? "teal") ?? .teal)
        _avatarURL = State(initialValue: editing?.avatar_url)
    }

    private var isEditing: Bool { editing != nil }

    private var avatarInitials: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard let f = n.first else { return "AI" }
        return String(n.prefix(f.isASCII ? 2 : 1)).uppercased()
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    // 头像：点击上传图片
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(initials: avatarInitials, tint: tint.color, size: 72, seed: 7, imageURL: avatarURL)
                            ZStack {
                                Circle().fill(FlowTheme.teal).frame(width: 24, height: 24)
                                Image(systemName: uploading ? "arrow.up" : "camera.fill")
                                    .font(.system(size: 11)).foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.top, 24)

                    Card {
                        VStack(spacing: 16) {
                            field(loc.t("companion.name"), text: $name)
                            personaField
                            field(loc.t("companion.greeting"), text: $greeting)
                            HStack {
                                Text(loc.t("companion.tint")).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                Spacer()
                                HStack(spacing: 10) {
                                    ForEach(CompanionTint.allCases) { c in
                                        Circle().fill(c.color).frame(width: 26, height: 26)
                                            .overlay(Circle().stroke(FlowTheme.ink, lineWidth: tint == c ? 2 : 0))
                                            .onTapGesture { tint = c }
                                    }
                                }
                            }
                        }
                        .padding(18)
                    }
                    .padding(.horizontal, 16)

                    if let error { Text(error).font(FlowTheme.caption(13)).foregroundStyle(.red) }

                    Button(action: save) {
                        ZStack {
                            PrimaryButton(title: loc.t(isEditing ? "companion.update" : "companion.save")).opacity(canSave ? 1 : 0.5)
                            if saving { ProgressView().tint(.white) }
                        }
                    }
                    .disabled(!canSave || saving)
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(FlowTheme.gray.opacity(0.6))
            }.padding(16)
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !persona.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(FlowTheme.body(15))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field))
            .sketchBorder(12, width: 1.3, seed: 31)
    }

    private var personaField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.t("companion.persona")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            TextEditor(text: $persona)
                .font(FlowTheme.body(15))
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field))
                .sketchBorder(12, width: 1.3, seed: 32)
        }
    }

    private func save() {
        saving = true
        error = nil
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = persona.trimmingCharacters(in: .whitespaces)
        let g = greeting.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let c: Companion
                if let editing {
                    c = try await APIClient.shared.updateCompanion(
                        id: editing.id, name: n, persona: p, avatar: avatarInitials,
                        tint: tint.rawValue, greeting: g, avatarURL: avatarURL)
                } else {
                    c = try await APIClient.shared.createCompanion(
                        name: n, persona: p, avatar: avatarInitials,
                        tint: tint.rawValue, greeting: g, avatarURL: avatarURL)
                }
                onSaved(c)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
