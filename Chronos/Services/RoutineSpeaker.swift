import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// On-device text-to-speech for the guided routine runner, so steps can be
/// announced hands-free ("Now: shower · 10 minutes"). Uses Apple's built-in
/// speech synthesizer — free, offline, no entitlement.
@MainActor
final class RoutineSpeaker {
    static let shared = RoutineSpeaker()
    private init() {}

    #if canImport(AVFoundation)
    private let synth = AVSpeechSynthesizer()
    #endif

    func speak(_ text: String) {
        #if canImport(AVFoundation)
        activateSession()
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
        #endif
    }

    func stop() {
        #if canImport(AVFoundation)
        synth.stopSpeaking(at: .immediate)
        #endif
    }

    private func activateSession() {
        #if os(iOS) && canImport(AVFoundation)
        // Mix with other audio and duck it briefly, so a routine prompt doesn't
        // stop the user's music.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        #endif
    }
}
