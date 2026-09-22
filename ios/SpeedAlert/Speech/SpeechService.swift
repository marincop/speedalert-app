import Foundation
import AVFoundation
import Combine

/// Offline text-to-speech using the built-in Taiwanese Mandarin voice.
///
/// iOS ships a zh-TW voice ("Mei-Jia" / 美佳) that speaks Taiwan-accented
/// Mandarin — no account, no network, no API key. Higher-quality
/// "enhanced"/"premium" variants are downloadable in
/// Settings ▸ Accessibility ▸ Spoken Content ▸ Voices ▸ Chinese (Taiwan).
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var lastSpoken: String = ""

    /// 0.0...1.0, maps onto AVSpeechUtterance rate. 0.5 ≈ default.
    var rate: Float = 0.5

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var lastText = ""
    private var lastTime = Date.distantPast
    private let dedupeWindow: TimeInterval = 4

    override init() {
        voice = SpeechService.taiwanVoice()
        super.init()
        synthesizer.delegate = self
    }

    /// Best available zh-TW (Taiwan) voice; falls back to any zh-TW voice.
    static func taiwanVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        // Prefer a premium/enhanced zh-TW voice if the user downloaded one.
        let zhTW = all.filter { $0.language == "zh-TW" }
        if let premium = zhTW.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = zhTW.first(where: { $0.quality == .enhanced }) { return enhanced }
        if let any = zhTW.first { return any }
        return AVSpeechSynthesisVoice(language: "zh-TW")
    }

    var voiceName: String { voice?.name ?? "（無 zh-TW 語音）" }

    /// Configure the audio session so speech plays over music/nav and keeps
    /// working in the background.
    func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: [])
    }

    /// Speak `text`. Repeats of the same phrase inside `dedupeWindow` are dropped.
    func say(_ text: String, force: Bool = false) {
        let now = Date()
        if !force, text == lastText, now.timeIntervalSince(lastTime) < dedupeWindow { return }
        lastText = text
        lastTime = now
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-TW")
        utterance.rate = rate
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
        lastSpoken = text
    }

    /// Speak via the prerecorded **voice pack** when available, else fall back to TTS.
    func speak(text: String, tokens: [String]? = nil, force: Bool = false) {
        if let tokens, !tokens.isEmpty, VoicePack.shared.play(tokens) {
            lastSpoken = text
            return
        }
        say(text, force: force)
    }
}
