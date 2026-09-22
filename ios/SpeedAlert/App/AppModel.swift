import Foundation
import CoreLocation
import Combine

/// Top-level coordinator: wires location → store → alert engine → speech
/// and publishes the state the UI needs.
final class AppModel: ObservableObject {
    let store = EnforcementStore()
    let location = LocationService()
    let speech = SpeechService()

    private let engine = AlertEngine()

    @Published var driving = false
    @Published var speedKph: Double = 0
    @Published var nearest: [NearbyHit] = []
    @Published var lastAlert: String = ""
    @Published var alertCount: Int = 0

    /// Which hazard kinds are enabled (persisted via @AppStorage in the UI and
    /// read back from UserDefaults in `init()`; pushed here on every UI change).
    var enabledKinds: Set<EnforcementKind> = Set(EnforcementKind.allCases)

    /// 依車速自動調整提醒距離（預設開啟）。
    private(set) var autoSpeedEnabled = true
    /// 手動選擇的提醒距離（關閉自動調整時使用）。
    private(set) var manualStages: [CLLocationDistance] = AlertEngine.defaultStages

    private let queryRadius: CLLocationDistance = 600   // covers the 500 m stage

    init() {
        // Read the saved choices back before driving starts: @AppStorage only
        // pushes them into the model while the settings sheet is on screen, so
        // without this a relaunch would silently revert to the defaults.
        //
        // EVERY persisted setting must be read back here (the mapping lives in
        // AppSettings) — a setting that is written by the sheet but not read
        // here reverts to its default on relaunch. That is exactly what used to
        // happen to 「提醒種類」 (k_accident 關掉後重啟又提醒) and 「語速」.
        let defaults = UserDefaults.standard
        manualStages = AppSettings.manualStages(from: defaults)
        autoSpeedEnabled = AppSettings.autoSpeed(from: defaults)
        enabledKinds = AppSettings.enabledKinds(from: defaults)
        speech.rate = AppSettings.voiceRate(from: defaults)
        engine.applySettings(manualStages: manualStages, autoSpeed: autoSpeedEnabled)

        engine.onAlert = { [weak self] text, item, stage in
            guard let self else { return }
            self.speech.speak(text: text, tokens: AlertPhrase.tokens(for: item, stage: stage))
            self.lastAlert = text
            self.alertCount += 1
        }
        location.onUpdate = { [weak self] loc in
            self?.handle(loc)
        }
    }

    /// Push the settings sheet's choices into the running engine.
    func applySettings(manualStages: [CLLocationDistance], autoSpeed: Bool) {
        self.manualStages = manualStages.isEmpty ? AlertEngine.defaultStages : manualStages
        autoSpeedEnabled = autoSpeed
        engine.applySettings(manualStages: self.manualStages, autoSpeed: autoSpeed)
    }

    func toggleDriving() {
        driving.toggle()
        if driving {
            speech.activateSession()
            location.requestPermission()
            engine.reset()
            location.start()
        } else {
            location.stop()
            nearest = []
            speedKph = 0
        }
    }

    private func handle(_ loc: CLLocation) {
        speedKph = max(0, loc.speed) * 3.6
        let hits = store.nearby(loc.coordinate, radius: queryRadius, kinds: enabledKinds)
        nearest = Array(hits.prefix(8))
        engine.process(location: loc, hits: hits)
    }
}
