import Foundation
import CoreLocation
import Combine

/// Thin wrapper over CLLocationManager tuned for a driving alert app:
/// high accuracy, background updates, automotive activity type.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var isRunning = false

    private let manager = CLLocationManager()
    /// Called on every accepted fix (background included).
    var onUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // A speedometer must keep receiving fixes when the car is *stopped*.
        // With a distance filter the OS goes silent once you stop moving and
        // the last speed stays frozen on screen — so we take every fix.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isRunning = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            if isRunning { start() }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Reject noisy fixes: negative accuracy is invalid, >50 m is too rough to alert on.
        guard let loc = locations.last, loc.horizontalAccuracy >= 0,
              loc.horizontalAccuracy <= 50 else { return }
        onUpdate?(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. .locationUnknown) are expected; ignore.
    }
}
