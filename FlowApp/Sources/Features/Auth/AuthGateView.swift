import SwiftUI

/// 登录闸：未登录看 AuthView，已登录看 RootView。
struct AuthGateView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var theme: Theme

    var body: some View {
        Group {
            if auth.isBootstrapping {
                ZStack {
                    PaperBackground()
                    ProgressView().tint(FlowTheme.teal)
                }
            } else if auth.isLoggedIn {
                RootView()
            } else {
                AuthView()
            }
        }
        .preferredColorScheme(theme.preferredScheme)
    }
}
