import Foundation

/// Turns noisy, intermittent GPS speed readings into a stable display value.
///
/// Two real-world problems this solves:
///
///  1. **Frozen value.** Core Location stops delivering fixes once you stop
///     moving (the distance filter), so the last speed — the one just before
///     you braked — stays on screen. A staleness watchdog decays it to 0 when
///     no fresh fix arrives.
///  2. **GPS noise floor.** Doppler speed rarely reads exactly 0 while
///     stationary; it hovers a few km/h. A dead-band snaps that to 0.
///
/// Rising speed is lightly smoothed to stop the digits flickering; falling
/// speed is *not* smoothed, so braking feels immediate.
struct SpeedFilter {
    /// Below this the vehicle is treated as stopped (GPS noise floor), km/h.
    var deadbandKph: Double = 3.0
    /// Drop to 0 if no fresh fix arrives for this long (seconds).
    var staleAfter: TimeInterval = 3.0

    private var kph: Double = 0
    private var lastFixAt: Date?

    /// Feed a raw fix. `speedMps` is `CLLocation.speed` (negative == invalid).
    mutating func update(speedMps: Double, at now: Date) {
        guard speedMps >= 0 else { return }   // invalid reading: keep last, watchdog handles it
        lastFixAt = now
        let raw = speedMps * 3.6
        if raw < deadbandKph {
            kph = 0                            // dead-band: snap the noise floor to zero
        } else if kph == 0 {
            kph = raw                          // starting to move: take it as-is
        } else {
            kph = kph * 0.6 + raw * 0.4        // light smoothing while cruising
        }
    }

    /// Value to show right now. Call this from a 1 s timer too, so a stopped
    /// car reads 0 even after the OS stops sending fixes.
    mutating func value(at now: Date) -> Double {
        if let last = lastFixAt, now.timeIntervalSince(last) > staleAfter {
            kph = 0
        }
        return kph
    }

    mutating func reset() {
        kph = 0
        lastFixAt = nil
    }
}
