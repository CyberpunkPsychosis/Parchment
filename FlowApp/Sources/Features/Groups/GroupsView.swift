import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var loc: Localization
    @State private var showCreate = false

    private var groups: [ChatSummary] { MockData.chats.filter { $0.isGroup } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("groups.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                Spacer()
                Button { showCreate = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24)).foregroundStyle(FlowTheme.teal)
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(groups) { ChatRowView(chat: $0) }

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
        }
        .background(PaperBackground())
        .sheet(isPresented: $showCreate) { CreateGroupView().environmentObject(loc) }
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
                        .background(RoundedRectangle(cornerRadius: FlowTheme.cornerField).fill(FlowTheme.beige))

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
                                    Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(c.id) ? FlowTheme.teal : FlowTheme.gray.opacity(0.5))
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
