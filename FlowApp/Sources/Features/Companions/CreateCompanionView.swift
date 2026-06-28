import SwiftUI

/// 创建自定义 AI 搭子。
struct CreateCompanionView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Companion) -> Void

    @State private var name = ""
    @State private var persona = ""
    @State private var greeting = ""
    @State private var tint: CompanionTint = .teal
    @State private var saving = false
    @State private var error: String?

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
                    Avatar(initials: avatarInitials, tint: tint.color, size: 72, seed: 7).padding(.top, 24)

                    Card {
                        VStack(spacing: 16) {
                            field(loc.t("companion.name"), text: $name)
                            personaField
                            field(loc.t("companion.greeting"), text: $greeting)
                            // 配色
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
                            PrimaryButton(title: loc.t("companion.save")).opacity(canSave ? 1 : 0.5)
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
        Task {
            do {
                let c = try await APIClient.shared.createCompanion(
                    name: name.trimmingCharacters(in: .whitespaces),
                    persona: persona.trimmingCharacters(in: .whitespaces),
                    avatar: avatarInitials, tint: tint.rawValue,
                    greeting: greeting.trimmingCharacters(in: .whitespaces))
                onCreated(c)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
