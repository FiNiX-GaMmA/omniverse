import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return PlayerOrientation.lockMask
    }
}

@main
struct OmniverseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = AppState()
    @State private var booted = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .task {
                    if !booted { booted = true; await state.initialize() }
                }
                .onOpenURL { url in Task { await state.handleIncomingURL(url) } }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:     Task { await state.syncNow() }            // pull latest on foreground
                    case .background: Task { try? await state.syncSettingsToTrakt(silent: true) } // push before suspend
                    default: break
                    }
                }
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}

/// Splash → Onboarding (if no Trakt) → main AppShell.
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var splashDone = false

    var body: some View {
        ZStack {
            LiquidBackdrop()
            if !state.initialized {
                ProgressView().tint(LiquidColors.cyan)
            } else if !splashDone {
                SplashView { splashDone = true }
            } else if !state.credentials.hasTraktUser {
                TraktOnboardingScreen()
            } else {
                AppShell()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.initialized)
        .animation(.easeInOut(duration: 0.4), value: splashDone)
        .preferredColorScheme(.dark)
        .tint(LiquidColors.cyan)
    }
}

/// Cinematic, Netflix-style branded splash: accent light-beams sweep up and
/// converge to center, a bloom flash fires as the logo scales in with a glow,
/// then a shimmer sweeps across the OMNIVERSE wordmark before handing off.
struct SplashView: View {
    var onDone: () -> Void

    @State private var beamsUp = false
    @State private var converge = false
    @State private var logoIn = false
    @State private var bloom = false
    @State private var flash: Double = 0
    @State private var wordmark = false
    @State private var shimmer: CGFloat = -1.2

    private let accents: [Color] = [
        LiquidColors.cyan, LiquidColors.rose, LiquidColors.gold,
        LiquidColors.cyan, LiquidColors.rose, LiquidColors.gold, LiquidColors.cyan,
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color.black
                LiquidBackdrop().opacity(logoIn ? 1 : 0)

                // Converging light beams.
                ForEach(accents.indices, id: \.self) { i in
                    let n = max(accents.count - 1, 1)
                    let spread = w * 0.64
                    let baseX = -spread / 2 + spread * CGFloat(i) / CGFloat(n)
                    Capsule()
                        .fill(accents[i])
                        .frame(width: 7, height: beamsUp ? h * 0.72 : 0)
                        .blur(radius: 9)
                        .opacity(converge ? 0 : 0.9)
                        .offset(x: converge ? 0 : baseX)
                        .blendMode(.screen)
                }

                // Bloom flash behind the logo.
                Circle()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.95), LiquidColors.cyan.opacity(0.45), .clear],
                        center: .center, startRadius: 0, endRadius: 260))
                    .frame(width: 560, height: 560)
                    .scaleEffect(bloom ? 1.15 : 0.25)
                    .opacity(flash)
                    .blendMode(.screen)

                // Logo + wordmark.
                VStack(spacing: 24) {
                    Image("AppLogo")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 144, height: 144)
                        .scaleEffect(logoIn ? 1 : 0.5)
                        .opacity(logoIn ? 1 : 0)
                        .shadow(color: LiquidColors.cyan.opacity(0.6), radius: bloom ? 46 : 16)
                    wordmarkView(width: w)
                }
            }
            .frame(width: w, height: h)
            .onAppear { run() }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func wordmarkView(width: CGFloat) -> some View {
        let font = Font.system(size: 28, weight: .black, design: .rounded)
        Text("OMNIVERSE")
            .font(font).tracking(8).foregroundStyle(.white)
            .opacity(wordmark ? 1 : 0)
            .overlay(
                LinearGradient(colors: [.clear, .white, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 90)
                    .offset(x: shimmer * (width * 0.5))
                    .blendMode(.screen)
                    .mask(Text("OMNIVERSE").font(font).tracking(8))
                    .opacity(wordmark ? 1 : 0)
            )
    }

    private func run() {
        withAnimation(.easeOut(duration: 0.6)) { beamsUp = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeInOut(duration: 0.45)) { converge = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.08)) { logoIn = true }
            withAnimation(.easeOut(duration: 0.55).delay(0.08)) { bloom = true }
            flash = 0.9
            withAnimation(.easeOut(duration: 0.75).delay(0.08)) { flash = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.4)) { wordmark = true }
            withAnimation(.easeInOut(duration: 0.95).delay(0.1)) { shimmer = 1.2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { onDone() }
    }
}
