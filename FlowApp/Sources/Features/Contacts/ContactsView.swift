import SwiftUI

/// Sketch-bordered checkbox used in member selection.
struct CheckBox: View {
    let checked: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(checked ? FlowTheme.teal : FlowTheme.field)
            .frame(width: 23, height: 23)
            .overlay {
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .sketchBorder(6, width: 1.2, seed: checked ? 60 : 61)
    }
}

/// Contacts list with search + alphabetical index (设计系统「联系人列表」).
struct ContactsView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Row: Identifiable { let id = UUID(); let letter, initials, name: String; let tint: Color }
    private let rows: [Row] = [
        .init(letter: "A", initials: "ON", name: "Original names", tint: FlowTheme.gray),
        .init(letter: "W", initials: "王", name: "王伟", tint: FlowTheme.teal),
        .init(letter: "L", initials: "李", name: "李娜", tint: FlowTheme.sage),
        .init(letter: "Z", initials: "张", name: "张强", tint: FlowTheme.tealDark),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.lang == .zh ? "联系人" : "Contacts")
                    .font(FlowTheme.heading(22)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }
            .padding(20)

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(FlowTheme.gray)
                    TextField(loc.lang == .zh ? "搜索联系人" : "Search", text: $query)
                        .font(FlowTheme.body(15))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
                .sketchBorder(14, width: 1.4, seed: 70)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                            HStack(spacing: 11) {
                                Text(r.letter).font(.system(size: 11, weight: .bold)).foregroundStyle(FlowTheme.gray).frame(width: 14)
                                Avatar(initials: r.initials, tint: r.tint, size: 38, seed: UInt64(idx + 80))
                                Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(FlowTheme.ink)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button { dismiss() } label: { PillButton(title: loc.lang == .zh ? "添加" : "Add", radius: 22, seed: 71) }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 16)
        }
        .background(PaperBackground())
    }
}
