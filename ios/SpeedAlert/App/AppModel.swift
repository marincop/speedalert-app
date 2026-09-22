import Foundation
import CoreLocation
import Combine

/// Keys shared with the `@AppStorage` bindings in SettingsView. Kept here so
/// AppModel can read the saved choices back at launch.
enum AppSettings {
    /// 「依車速自動調整提醒距離」
    static let autoSpeedKey = "autoSpeed"
    /// Manual distance toggles: (UserDefaults key, metres).
    static let manualStageKeys: [(key: String, metres: CLLocationDistance)] = [
        ("s500", 500), ("s300", 300), ("s100", 100), ("s0", 0)
    ]
}

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
    /// pushed here on change).
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
        let defaults = UserDefaults.standard
        var manual: [CLLocationDistance] = []
        for (key, metres) in AppSettings.manualStageKeys {
            if (defaults.object(forKey: key) as? Bool) ?? true { manual.append(metres) }
        }
        manualStages = manual.isEmpty ? AlertEngine.defaultStages : manual
        autoSpeedEnabled = (defaults.object(forKey: AppSettings.autoSpeedKey) as? Bool) ?? true
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
