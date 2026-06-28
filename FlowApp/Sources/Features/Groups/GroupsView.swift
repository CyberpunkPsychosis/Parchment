import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var loc: Localization
    @State private var seg = 0
    @State private var showCreate = false
    @State private var showContacts = false

    private var groups: [ChatSummary] { MockData.chats.filter { $0.isGroup } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text(loc.t("groups.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                    Spacer()
                    Button { showContacts = true } label: {
                        Image(systemName: "person.2").font(.system(size: 20)).foregroundStyle(FlowTheme.ink)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

                Picker("", selection: $seg) {
                    Text(loc.t("groups.seg.groups")).tag(0)
                    Text(loc.t("groups.seg.communities")).tag(1)
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)

                if seg == 0 { friendGroups } else { GroupPlazaView(mineOnly: true) }
            }
            .background(PaperBackground())
            .navigationDestination(for: PlazaGroup.self) { g in CommunityDetailView(group: g) }
        }
        .sheet(isPresented: $showCreate) { CreateGroupView().environmentObject(loc) }
        .sheet(isPresented: $showContacts) { ContactsView().environmentObject(loc) }
    }

    private var friendGroups: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                    ChatRowView(chat: g, seed: UInt64(idx + 50))
                }
                Button { showCreate = true } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text(loc.t("groups.create"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FlowTheme.teal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(FlowTheme.teal.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
