import SwiftUI

// MARK: - Hand-drawn sketch border

/// Deterministic RNG so the wobble is stable across redraws (no shimmering).
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// A rounded rectangle whose straight edges are slightly jittered to look
/// hand-drawn (the SwiftUI equivalent of the preview's turbulence filter).
struct SketchyRoundedRect: Shape {
    var cornerRadius: CGFloat = 16
    var jitter: CGFloat = 1.1
    var seed: UInt64 = 1

    func path(in rect: CGRect) -> Path {
        var rng = SeededRNG(seed: seed)
        func j() -> CGFloat { CGFloat.random(in: -jitter...jitter, using: &rng) }
        func jp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + j(), y: p.y + j()) }

        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY

        func wavy(_ path: inout Path, from a: CGPoint, to b: CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            let steps = max(2, Int(len / 26))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                path.addLine(to: jp(CGPoint(x: a.x + (b.x - a.x) * t,
                                            y: a.y + (b.y - a.y) * t)))
            }
        }

        var p = Path()
        p.move(to: jp(CGPoint(x: minX + r, y: minY)))
        wavy(&p, from: CGPoint(x: minX + r, y: minY), to: CGPoint(x: maxX - r, y: minY))
        p.addQuadCurve(to: jp(CGPoint(x: maxX, y: minY + r)), control: CGPoint(x: maxX, y: minY))
        wavy(&p, from: CGPoint(x: maxX, y: minY + r), to: CGPoint(x: maxX, y: maxY - r))
        p.addQuadCurve(to: jp(CGPoint(x: maxX - r, y: maxY)), control: CGPoint(x: maxX, y: maxY))
        wavy(&p, from: CGPoint(x: maxX - r, y: maxY), to: CGPoint(x: minX + r, y: maxY))
        p.addQuadCurve(to: jp(CGPoint(x: minX, y: maxY - r)), control: CGPoint(x: minX, y: maxY))
        wavy(&p, from: CGPoint(x: minX, y: maxY - r), to: CGPoint(x: minX, y: minY + r))
        p.addQuadCurve(to: jp(CGPoint(x: minX + r, y: minY)), control: CGPoint(x: minX, y: minY))
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Overlay a hand-drawn outline.
    func sketchBorder(_ radius: CGFloat = 16, color: Color = FlowTheme.line,
                      width: CGFloat = 1.6, seed: UInt64 = 1) -> some View {
        overlay(SketchyRoundedRect(cornerRadius: radius, seed: seed).stroke(color, lineWidth: width))
    }

    /// Fill + hand-drawn outline (the standard sketch card / bubble).
    func sketchCard(_ radius: CGFloat = 18, fill: Color = FlowTheme.card,
                    line: Color = FlowTheme.line, width: CGFloat = 1.6, seed: UInt64 = 1) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .sketchBorder(radius, color: line, width: width, seed: seed)
    }
}

// MARK: - Reusable pieces

struct PaperBackground: View {
    var dark: Bool = false
    var body: some View {
        ZStack {
            (dark ? FlowTheme.ink : FlowTheme.parchment).ignoresSafeArea()
            Image(dark ? "paper_dark" : "paper_light")
                .resizable(resizingMode: .tile)
                .opacity(dark ? 0.16 : 0.10)
                .ignoresSafeArea()
        }
    }
}

/// The FLOW logo mark: "F" in a sketch-bordered block.
struct FlowLogo: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("F")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(FlowTheme.ink))
            Text("FLOW")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(FlowTheme.ink)
        }
    }
}

/// Circular avatar with initials and a sketchy ring.
struct Avatar: View {
    let initials: String
    var tint: Color = FlowTheme.teal
    var size: CGFloat = 44
    var seed: UInt64 = 3
    var body: some View {
        Circle().fill(tint.opacity(0.16))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .serif))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
            .overlay(SketchyRoundedRect(cornerRadius: size / 2, jitter: 0.8, seed: seed)
                .stroke(tint.opacity(0.6), lineWidth: 1.3))
    }
}

struct OnlineDot: View {
    var online: Bool = true
    var body: some View {
        Circle().fill(online ? FlowTheme.online : FlowTheme.gray).frame(width: 9, height: 9)
    }
}

/// Teal pill (JOIN / 加入 / SEND-style actions).
struct PillButton: View {
    let title: String
    var radius: CGFloat = 16
    var seed: UInt64 = 5
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: radius).fill(FlowTheme.teal))
            .sketchBorder(radius, color: FlowTheme.tealDark, width: 1.2, seed: seed)
    }
}

/// Full-width primary action button.
struct PrimaryButton: View {
    let title: String
    var seed: UInt64 = 9
    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(FlowTheme.teal))
            .sketchBorder(16, color: FlowTheme.tealDark, width: 1.3, seed: seed)
    }
}

/// Raised cream card with a hand-drawn outline.
struct Card<Content: View>: View {
    var radius: CGFloat = 20
    var seed: UInt64 = 1
    var content: Content
    init(radius: CGFloat = 20, seed: UInt64 = 1, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.seed = seed
        self.content = content()
    }
    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(FlowTheme.card)
                .shadow(color: FlowTheme.shadow, radius: 10, x: 0, y: 4))
            .sketchBorder(radius, seed: seed)
    }
}

/// Toggle with a sketch-bordered teal track.
struct FlowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 14)
                .fill(configuration.isOn ? FlowTheme.teal : FlowTheme.gray.opacity(0.4))
                .frame(width: 46, height: 28)
                .overlay(Circle().fill(.white).padding(3)
                    .frame(width: 28, height: 28)
                    .offset(x: configuration.isOn ? 9 : -9))
                .sketchBorder(14, width: 1.3, seed: 12)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
