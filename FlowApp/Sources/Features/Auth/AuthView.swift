import SwiftUI

/// 手绘风输入框（复用 sketchBorder）。
struct SketchField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var seed: UInt64 = 1

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(FlowTheme.body(16))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.field))
        .sketchBorder(14, width: 1.4, seed: seed)
    }
}

/// 登录 / 注册（同一界面切换）。复用 FlowLogo / SketchField / PrimaryButton。
struct AuthView: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var auth: AuthStore

    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 22) {
                Spacer()
                FlowLogo()
                Text(loc.t("auth.tagline"))
                    .font(FlowTheme.caption(14))
                    .foregroundStyle(FlowTheme.gray)

                Card {
                    VStack(spacing: 16) {
                        Text(loc.t(isRegister ? "auth.createAccount" : "auth.welcome"))
                            .font(FlowTheme.heading(20))
                            .foregroundStyle(FlowTheme.ink)

                        if isRegister {
                            SketchField(placeholder: loc.t("auth.nickname"), text: $nickname, seed: 21)
                        }
                        SketchField(placeholder: loc.t("auth.email"), text: $email,
                                    keyboard: .emailAddress, seed: 22)
                        SketchField(placeholder: loc.t("auth.password"), text: $password,
                                    secure: true, seed: 23)

                        if let error {
                            Text(error)
                                .font(FlowTheme.caption(13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submit) {
                            ZStack {
                                PrimaryButton(title: loc.t(isRegister ? "auth.register" : "auth.login"))
                                    .opacity(loading ? 0.5 : 1)
                                if loading { ProgressView().tint(.white) }
                            }
                        }
                        .disabled(loading)

                        Button {
                            withAnimation { isRegister.toggle(); error = nil }
                        } label: {
                            Text(loc.t(isRegister ? "auth.toLogin" : "auth.toRegister"))
                                .font(FlowTheme.caption(14))
                                .foregroundStyle(FlowTheme.teal)
                        }
                    }
                    .padding(20)
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
        }
    }

    private func submit() {
        error = nil
        loading = true
        Task {
            do {
                if isRegister {
                    try await auth.register(email: email, password: password, nickname: nickname)
                } else {
                    try await auth.login(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
