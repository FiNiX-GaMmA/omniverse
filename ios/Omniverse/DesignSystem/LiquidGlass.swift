import SwiftUI

/// Core palette ported 1:1 from the Flutter `LiquidColors`.
/// Apple-TV inspired, dark-first, with a cyan/rose/gold accent triad.
enum LiquidColors {
    static let ink = Color(hex: 0x0B0A12)
    static let dusk = Color(hex: 0x24152B)
    static let deepTeal = Color(hex: 0x082C2E)
    static let cyan = Color(hex: 0x8DEBE6)
    static let rose = Color(hex: 0xFF8EA8)
    static let gold = Color(hex: 0xFFD36E)
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
                    LiquidColors.ink,
                    Color(hex: 0x050A0B),
                    Color(hex: 0x061715),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft colored aurora blobs for depth — heavily blurred so the
            // glass tinting picks them up without being distracting.
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(LiquidColors.cyan.opacity(0.20))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 140)
                        .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.2)
                    Circle()
                        .fill(LiquidColors.rose.opacity(0.16))
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 150)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.5)
                    Circle()
                        .fill(LiquidColors.gold.opacity(0.08))
                        .frame(width: geo.size.width * 0.6)
                        .blur(radius: 130)
                        .offset(x: geo.size.width * 0.1, y: geo.size.height * 0.9)
                }
            }
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// Vivid frosted-glass panel. Uses a real system material for the live blur,
/// then layers a white gradient sheen, a hairline border, and a cyan glow —
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

/// Primary accent (cyan) capsule button — the "Play" call to action.
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
