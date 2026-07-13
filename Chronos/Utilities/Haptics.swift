import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Small, tasteful haptics. Completing something should *feel* like a small
/// win — that tactile confirmation is a big part of why an app feels
/// satisfying to use. No-ops on macOS.
enum Haptics {
    static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func soft() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
