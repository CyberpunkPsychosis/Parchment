import SwiftUI

/// 启动封面：羊皮纸 Logo + 名称，短暂展示后淡出进入 App。
struct SplashView: View {
    @EnvironmentObject var loc: Localization
    @State private var appear = false

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                Text(loc.t("app.name"))
                    .font(FlowTheme.title(34)).foregroundStyle(FlowTheme.ink)
                Text(loc.t("app.tagline"))
                    .font(FlowTheme.caption(13)).foregroundStyle(FlowTheme.gray)
            }
            .scaleEffect(appear ? 1 : 0.96)
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: appear)
        }
        .onAppear { appear = true }
    }
}
