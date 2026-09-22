import Foundation
import AVFoundation

/// Modular **prerecorded voice pack**.
///
/// Sentences are assembled from short clips so a voice actor only records a
/// small set of tokens (see VOICEPACK.md). Clips are looked up in
/// `Documents/VoicePack/` first (drop-in, no rebuild), then the bundled
/// `VoicePack/` resource dir. If any clip is missing, `play(_:)` returns false
/// and the caller falls back to system TTS.
final class VoicePack {
    static let shared = VoicePack()

    private var searchDirs: [URL] = []
    private var players: [AVAudioPlayer] = []
    private let exts = ["m4a", "caf", "mp3", "wav", "aiff", "aif"]

    private init() {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            searchDirs.append(docs.appendingPathComponent("VoicePack", isDirectory: true))
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("VoicePack", isDirectory: true) {
            searchDirs.append(res)
        }
    }

    /// Directory currently providing clips (Documents first, else bundle).
    var activeDir: URL? {
        searchDirs.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func url(for token: String) -> URL? {
        for dir in searchDirs {
            for e in exts {
                let u = dir.appendingPathComponent("\(token).\(e)")
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    /// A pack is usable once the anchor clip exists.
    var isReady: Bool { url(for: "lead_front") != nil }

    /// Play `tokens` in order. Returns false if any clip is missing.
    @discardableResult
    func play(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        var made: [AVAudioPlayer] = []
        for t in tokens {
            guard let u = url(for: t), let p = try? AVAudioPlayer(contentsOf: u) else { return false }
            p.prepareToPlay()
            made.append(p)
        }
        players = made                     // retain so playback survives
        var offset: TimeInterval = 0
        for p in players {
            p.play(atTime: p.deviceCurrentTime + offset)
            offset += p.duration + 0.03
        }
        return true
    }

    func stop() {
        players.forEach { $0.stop() }
        players.removeAll()
    }
}
