// "Read the brief" in the app: the brief's speech text spoken with AVSpeechSynthesizer while the app is open.

import AVFoundation
import Foundation
import Observation

/// Speaks the brief in the app (SIRI-02: the brief is spoken). Pass `BriefModel.speechText(at:)`, which starts with a
/// spoken notice when the brief is a saved copy.
///
/// It speaks only while the app is in use: the app declares no audio background mode, so speech stops when the app
/// leaves the foreground, and nothing here claims lock-screen or background playback, which only a real device can
/// show. On iPhone and iPad it uses the playback category with the spoken-audio mode, lowering other audio while it
/// speaks, and gives the audio session back when it finishes. With VoiceOver on, VoiceOver's speech settings apply.
@MainActor
@Observable
final class BriefSpeaker {
    /// Whether the brief is being spoken.
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let events = SpeechEvents()

    init() {
        events.speaker = self
        synthesizer.delegate = events
    }

    /// Speaks `text`, replacing anything being spoken.
    func speak(_ text: String) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        activateAudio()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage)
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    /// Stops speaking at once.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Called when an utterance finished or was stopped.
    fileprivate func utteranceEnded() {
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        deactivateAudio()
    }

    /// The person's language when it is a variant of English, the language of Lisa's text; otherwise US English.
    private static var voiceLanguage: String {
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        return preferred.hasPrefix("en") ? preferred : "en-US"
    }

    private func activateAudio() {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        #endif
    }

    private func deactivateAudio() {
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// Forwards the synthesizer's events to the speaker on the main actor; the synthesizer may report them on any thread.
@MainActor
private final class SpeechEvents: NSObject, AVSpeechSynthesizerDelegate {
    weak var speaker: BriefSpeaker?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaker?.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaker?.utteranceEnded() }
    }
}
