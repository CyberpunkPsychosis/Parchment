import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var loc: Localization

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("discover.title")).font(FlowTheme.caption(14)).foregroundStyle(FlowTheme.gray)
                Text(loc.t("discover.elite")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(MockData.services) { ServiceCardView(service: $0) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .background(PaperBackground())
    }
}

struct ServiceCardView: View {
    @EnvironmentObject var loc: Localization
    let service: EliteService

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Image(service.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(loc.lang == .zh ? service.titleZh : service.titleEn)
                    .font(FlowTheme.heading(18)).foregroundStyle(FlowTheme.ink)
                Text(loc.lang == .zh ? service.subtitleZh : service.subtitleEn)
                    .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    JoinPill(title: loc.t("discover.join"))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.system(size: 12))
                        Text(service.members).font(FlowTheme.caption(13))
                    }
                    .foregroundStyle(FlowTheme.gray)
                }
            }
            .padding(16)
        }
    }
}
