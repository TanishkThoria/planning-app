import SwiftUI

/// A single chat message in the Coach conversation.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, coach }
    let id = UUID()
    let role: Role
    var text: String
    var action: QuickAction?
    var actionLabel: String?
}

/// Holds the Coach conversation outside the view so it survives tab switches.
/// When the user navigates away from a real conversation, it's archived (not
/// destroyed) and the screen returns to a fresh greeting — with a "continue
/// previous conversation" affordance to bring it back.
@MainActor
final class CoachStore: ObservableObject {
    static let shared = CoachStore()
    private init() {}

    @Published var messages: [ChatMessage] = []
    @Published var archived: [ChatMessage] = []

    /// A "real" conversation is one where the user actually said something —
    /// not just the opening greeting.
    var hasRealConversation: Bool { messages.contains { $0.role == .user } }
    var hasArchive: Bool { !archived.isEmpty }

    /// Called when leaving the Coach: keep a real conversation around but reset
    /// the visible thread so returning shows a clean slate.
    func archiveIfLeaving() {
        guard hasRealConversation else { return }
        archived = messages
        messages = []
    }

    /// Bring the archived conversation back into view.
    func restore() {
        guard hasArchive else { return }
        messages = archived
        archived = []
    }

    /// Full reset (the "new conversation" button).
    func clear() {
        messages = []
        archived = []
    }
}
