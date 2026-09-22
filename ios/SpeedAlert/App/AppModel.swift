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
    /// pushed here on change).
    var enabledKinds: Set<EnforcementKind> = Set(EnforcementKind.allCases)
    var stages: [CLLocationDistance] = AlertEngine.defaultStages {
        didSet { engine.updateStages(stages) }
    }

    private let queryRadius: CLLocationDistance = 600   // covers the 500 m stage

    init() {
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
