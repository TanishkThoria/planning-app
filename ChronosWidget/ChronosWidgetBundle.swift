import WidgetKit
import SwiftUI

/// The widget extension's entry point. Bundles the home-screen / Lock Screen
/// timeline widgets and (on iOS 16.1+) the focus-session Live Activity.
///
/// This file — and every file in the ChronosWidget/ folder — belongs to the
/// ChronosWidget target ONLY. The shared model files (SharedData.swift,
/// ChronosActivityAttributes.swift) belong to BOTH targets.
@main
struct ChronosWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChronosTodayWidget()
        ChronosUpNextWidget()
        ChronosHabitsWidget()
        ChronosMomentumWidget()
        ChronosNextInlineWidget()
        if #available(iOS 16.1, *) {
            ChronosFocusLiveActivity()
        }
    }
}
