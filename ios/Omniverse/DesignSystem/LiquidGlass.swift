import SwiftUI

/// Core palette aligned with Apple space-black and electric cyan liquid glass styling.
enum LiquidColors {
    static let ink = Color(hex: 0x05070C)
    static let dusk = Color(hex: 0x0F141C)
    static let deepTeal = Color(hex: 0x0A192F)
    static let cyan = Color(hex: 0x38BDF8)
    static let rose = Color(hex: 0x0284C7)
    static let gold = Color(hex: 0x94A3B8)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// The ambient backdrop behind every screen — a deep diagonal gradient that
/// makes the translucent glass panels read vividly on top. This is the
/// "Apple TV" canvas the rest of the UI floats over.
struct LiquidBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(hex: 0x05070C),
                    Color(hex: 0x0A111E),
                    Color(hex: 0x0F1B2E),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let driftX = sin(t * 0.12) * 40.0
                let driftY = cos(t * 0.14) * 35.0
                let scalePulse = 1.0 + sin(t * 0.18) * 0.08

                GeometryReader { geo in
                    ZStack {
                        Circle()
                            .fill(LiquidColors.cyan.opacity(0.22))
                            .frame(width: geo.size.width * 0.95 * scalePulse)
                            .blur(radius: 140)
                            .offset(x: -geo.size.width * 0.28 + driftX, y: -geo.size.height * 0.22 + driftY)
                        Circle()
                            .fill(LiquidColors.rose.opacity(0.18))
                            .frame(width: geo.size.width * 0.85 / scalePulse)
                            .blur(radius: 150)
                            .offset(x: geo.size.width * 0.38 - driftX, y: geo.size.height * 0.48 - driftY)
                    }
                }
            }
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// Spring touch feedback style for buttons and cards.
struct SpringTouchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .shadow(color: configuration.isPressed ? LiquidColors.cyan.opacity(0.35) : .clear, radius: 10, y: 2)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

/// Vivid frosted-glass panel. Uses a real system material for the live blur,
/// then layers a white gradient sheen, a hairline border, and a crimson glow —
/// matching the Flutter `GlassPanel` but pushing the glassmorphism further.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var opacity: Double = 0.12
    var borderOpacity: Double = 0.18
    var padding: CGFloat = 18
    var glow: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(opacity + 0.08),
                            Color.white.opacity(opacity),
                            Color.white.opacity(opacity * 0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderOpacity + 0.12),
                                Color.white.opacity(borderOpacity * 0.5),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 28, x: 0, y: 18)
            .shadow(color: glow ? LiquidColors.cyan.opacity(0.10) : .clear, radius: 18, y: -2)
    }
}

/// Pill-shaped glass capsule (chips, badges, small controls).
struct GlassCapsule<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .clipShape(Capsule())
    }
}

/// Circular glass icon button.
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Primary accent (crimson) capsule button — the "Play" call to action.
struct AccentButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background {
                if filled {
                    Capsule().fill(LiquidColors.cyan.opacity(configuration.isPressed ? 0.34 : 0.24))
                } else {
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.06))
                }
            }
            .overlay(Capsule().strokeBorder(
                filled ? LiquidColors.cyan.opacity(0.5) : Color.white.opacity(0.22),
                lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Drop-in screen wrapper: paints the liquid backdrop behind any content.
    func liquidScaffold() -> some View {
        ZStack { LiquidBackdrop(); self }
            .preferredColorScheme(.dark)
            .tint(LiquidColors.cyan)
    }
}
