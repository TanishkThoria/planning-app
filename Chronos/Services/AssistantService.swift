import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The Coach's brain. When the device supports Apple Intelligence (iOS 26+
/// on capable hardware), this runs Apple's on-device Foundation Model —
/// completely free, private, and offline, with no API key. Everywhere else it
/// reports as unavailable and the Coach falls back to its built-in heuristic
/// answers, so the experience degrades gracefully instead of breaking.
@MainActor
final class AssistantService {
    static let shared = AssistantService()
    private init() {}

    enum Status: Equatable {
        case ready
        case unavailable(String)
    }

    /// Persona + rules for the model. Kept tight so replies stay grounded,
    /// short, and human.
    static let instructions = """
    You are Chronos, a warm, sharp personal planning companion living inside a \
    time-blocking app. You help the user plan their day, stay focused, protect \
    their energy, and build good habits.

    Rules:
    - Be concise: 2–4 short sentences, conversational and encouraging.
    - Ground every answer in the CONTEXT you're given (their real blocks, tasks, \
    habits, streaks, and routine). Never invent events, numbers, or names that \
    aren't in the context.
    - When it helps, suggest ONE concrete next step (e.g. "want me to plan your \
    day?").
    - Talk like a supportive friend who knows them, not a robot. No bullet lists \
    unless asked. No headers. Don't repeat the context back verbatim.
    - If the context shows nothing scheduled, gently encourage planning rather \
    than pretending there's data.
    """

    var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                return .unavailable("On-device AI needs a newer iPhone (15 Pro or later).")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in Settings to chat with your coach.")
            case .unavailable(.modelNotReady):
                return .unavailable("The on-device model is still getting ready — try again shortly.")
            case .unavailable:
                return .unavailable("On-device AI is unavailable right now.")
            @unknown default:
                return .unavailable("On-device AI is unavailable right now.")
            }
        }
        #endif
        return .unavailable("On-device AI needs iOS 26 on a supported device.")
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// A short label for the current mode, shown under the Coach title.
    var modeLabel: String {
        isReady ? "On-device AI" : "Quick planning"
    }

    #if canImport(FoundationModels)
    /// Boxed as `Any?` because a stored property can't be typed to an
    /// `@available`-gated class directly.
    private var chatBox: Any?
    #endif

    /// Ask the model a grounded question. Returns nil when on-device AI isn't
    /// available, signalling the caller to use its heuristic fallback.
    func reply(to question: String, context: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), isReady {
            let chat = existingChat() ?? makeChat()
            let prompt = """
            CONTEXT (the user's current situation):
            \(context)

            The user says: \(question)
            """
            do {
                return try await chat.respond(to: prompt)
            } catch {
                // Most likely the context window filled up — start fresh once.
                let fresh = makeChat()
                if let retry = try? await fresh.respond(to: prompt) { return retry }
                return nil
            }
        }
        #endif
        return nil
    }

    func resetConversation() {
        #if canImport(FoundationModels)
        chatBox = nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func existingChat() -> FoundationChat? { chatBox as? FoundationChat }

    @available(iOS 26.0, macOS 26.0, *)
    private func makeChat() -> FoundationChat {
        let chat = FoundationChat()
        chatBox = chat
        return chat
    }
    #endif
}

#if canImport(FoundationModels)
/// Thin wrapper around a single `LanguageModelSession` so the conversation
/// keeps its short-term memory across turns.
@available(iOS 26.0, macOS 26.0, *)
private final class FoundationChat {
    private let session = LanguageModelSession {
        AssistantService.instructions
    }

    func respond(to prompt: String) async throws -> String {
        try await session.respond(to: prompt).content
    }
}
#endif
