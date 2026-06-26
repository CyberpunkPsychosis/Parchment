import SwiftUI

/// Parchment background: cream base + faint hand-drawn sketch overlay
/// (asset cropped from the design system sheet).
struct PaperBackground: View {
    var dark: Bool = false
    var body: some View {
        ZStack {
            (dark ? FlowTheme.ink : FlowTheme.parchment).ignoresSafeArea()
            Image(dark ? "paper_dark" : "paper_light")
                .resizable(resizingMode: .tile)
                .opacity(dark ? 0.18 : 0.10)
                .ignoresSafeArea()
        }
    }
}

/// Circular avatar with initials (no networked images in the frontend mock).
struct Avatar: View {
    let initials: String
    var tint: Color = FlowTheme.teal
    var size: CGFloat = 44
    var body: some View {
        Circle()
            .fill(tint.opacity(0.18))
            .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 1))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

struct OnlineDot: View {
    var online: Bool = true
    var body: some View {
        Circle()
            .fill(online ? FlowTheme.online : FlowTheme.gray)
            .frame(width: 9, height: 9)
    }
}

/// Teal "JOIN / 加入" pill button used on Discover cards.
struct JoinPill: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Capsule().fill(FlowTheme.teal))
    }
}

/// Filled primary action button (主要按钮).
struct PrimaryButton: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(FlowTheme.teal))
    }
}

/// Raised cream card container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: FlowTheme.cornerCard)
                    .fill(FlowTheme.card)
                    .shadow(color: FlowTheme.shadow, radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowTheme.cornerCard)
                    .stroke(FlowTheme.stroke, lineWidth: 1)
            )
    }
}

/// Toggle styled with the teal track from the design sheet.
struct FlowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? FlowTheme.teal : FlowTheme.gray.opacity(0.4))
                .frame(width: 46, height: 28)
                .overlay(
                    Circle().fill(.white)
                        .padding(3)
                        .frame(width: 28, height: 28)
                        .offset(x: configuration.isOn ? 9 : -9)
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
