import UIKit
import SwiftUI

/// Centralizes the two device behaviors the brief calls out:
///  1. Drive animations at the display's MAXIMUM refresh rate (ProMotion 120Hz).
///  2. Keep the screen awake while media is playing.
enum DeviceTuning {

    /// The maximum refresh rate the current screen supports (e.g. 120 on
    /// ProMotion iPhones/iPads, 60 otherwise). Paired with the
    /// `CADisableMinimumFrameDurationOnPhone` Info.plist flag, this lets
    /// CADisplayLink-driven work run at full rate.
    static var maxRefreshRate: Float {
        Float(UIScreen.main.maximumFramesPerSecond)
    }

    /// Apply the preferred high frame-rate range to a CADisplayLink.
    static func preferHighFrameRate(_ link: CADisplayLink) {
        let max = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: max, preferred: max)
    }

    /// Keep the display on (call when playback starts, clear when it stops).
    static func keepScreenOn(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }
}

/// A SwiftUI modifier that keeps the screen awake while the view is on-screen
/// (used by the player). Mirrors Android's FLAG_KEEP_SCREEN_ON behavior.
struct KeepAwakeModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, newValue in DeviceTuning.keepScreenOn(newValue) }
            .onAppear { DeviceTuning.keepScreenOn(active) }
            .onDisappear { DeviceTuning.keepScreenOn(false) }
    }
}

extension View {
    func keepScreenAwake(_ active: Bool = true) -> some View { modifier(KeepAwakeModifier(active: active)) }
}
