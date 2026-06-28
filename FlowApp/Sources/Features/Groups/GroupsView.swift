import SwiftUI

/// 群组 = 我加入的群/社群（点进直接群聊）。浏览/发现新社群在「发现」页。
struct GroupsView: View {
    @EnvironmentObject var loc: Localization
    @State private var showCreate = false
    @State private var showContacts = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text(loc.t("groups.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                    Spacer()
                    Button { showContacts = true } label: {
                        Image(systemName: "person.2").font(.system(size: 20)).foregroundStyle(FlowTheme.ink)
                    }
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(FlowTheme.teal)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

                // 我加入的群组：点击直接进群聊（详情/加入在「发现」页）
                GroupPlazaView(mineOnly: true, entersChat: true)
            }
            .background(PaperBackground())
        }
        .sheet(isPresented: $showCreate) { CreatePlazaGroupView { _ in }.environmentObject(loc) }
        .sheet(isPresented: $showContacts) { ContactsView() }
    }
}

struct CreateGroupView: View {
    @EnvironmentObject var loc: Localization
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("groups.create")).font(FlowTheme.heading(20)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.gray) }
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(loc.t("groups.name")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    TextField(loc.t("groups.name"), text: $name)
                        .font(FlowTheme.body(16))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: FlowTheme.cornerField).fill(FlowTheme.field))
                        .sketchBorder(FlowTheme.cornerField, width: 1.4, seed: 62)

                    Text(loc.t("groups.members")).font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    VStack(spacing: 10) {
                        ForEach(MockData.contacts) { c in
                            Button {
                                if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(initials: c.initials, tint: c.tint, size: 38)
                                    Text(c.name).font(FlowTheme.body(15)).foregroundStyle(FlowTheme.ink)
                                    Spacer()
                                    CheckBox(checked: selected.contains(c.id))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Button { dismiss() } label: { PrimaryButton(title: loc.t("groups.confirm")) }
                .padding(20)
        }
        .background(PaperBackground())
    }
}
