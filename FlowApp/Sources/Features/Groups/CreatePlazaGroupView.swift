import SwiftUI

struct CreatePlazaGroupView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    let onCreated: (PlazaGroup) -> Void

    @State private var name = ""
    @State private var desc = ""
    @State private var tint: CompanionTint = .teal
    @State private var mode = "open"
    @State private var cap = 200.0
    @State private var saving = false

    private var initials: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard let f = n.first else { return "群" }
        return String(n.prefix(f.isASCII ? 2 : 1))
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Avatar(initials: initials, tint: tint.color, size: 72, seed: 7).padding(.top, 24)
                    Card {
                        VStack(spacing: 16) {
                            field(loc.t("group.name"), text: $name)
                            field(loc.t("group.desc"), text: $desc)
                            // 加入方式
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("group.joinMode")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                                Picker("", selection: $mode) {
                                    Text(loc.t("group.mode.open")).tag("open")
                                    Text(loc.t("group.mode.code")).tag("code")
                                    Text(loc.t("group.mode.approval")).tag("approval")
                                }.pickerStyle(.segmented)
                            }
                            // 人数上限
                            HStack {
                                Text(loc.t("group.cap")).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                Spacer()
                                Text("\(Int(cap))").font(FlowTheme.body(15)).foregroundStyle(FlowTheme.teal)
                            }
                            Slider(value: $cap, in: 10...2000, step: 10).tint(FlowTheme.teal)
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

                    Button(action: save) {
                        ZStack {
                            PrimaryButton(title: loc.t("group.createCta"))
                                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || saving ? 0.5 : 1)
                            if saving { ProgressView().tint(.white) }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
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

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(FlowTheme.body(15))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(FlowTheme.field))
            .sketchBorder(12, width: 1.3, seed: 33)
    }

    private func save() {
        saving = true
        Task {
            if let g = try? await APIClient.shared.createGroup(
                name: name.trimmingCharacters(in: .whitespaces),
                description: desc.trimmingCharacters(in: .whitespaces),
                avatar: initials, tint: tint.rawValue, joinMode: mode, memberCap: Int(cap)) {
                onCreated(g)
                dismiss()
            }
            saving = false
        }
    }
}
