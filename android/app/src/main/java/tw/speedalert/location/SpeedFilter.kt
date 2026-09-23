package tw.speedalert.location

/**
 * Turns noisy, intermittent GPS speed readings into a stable display value.
 * Mirrors iOS `SpeedFilter`.
 *
 *  1. Frozen value: the OS stops sending fixes once the car stops moving, so
 *     the last speed stays on screen. The staleness watchdog decays it to 0.
 *  2. GPS noise floor: Doppler speed hovers a few km/h while stationary; the
 *     dead-band snaps that to 0.
 *
 * Rising speed is lightly smoothed; falling speed is not, so braking feels
 * immediate.
 */
class SpeedFilter(
    private val deadbandKph: Double = 3.0,
    private val staleAfterMs: Long = 3_000L,
) {
    private var kph: Double = 0.0
    private var lastFixAt: Long = 0L

    /** Feed a raw fix. `speedMps` is `Location.getSpeed()` (metres/second). */
    fun update(speedMps: Double, now: Long) {
        if (speedMps < 0) return            // invalid reading: keep last, watchdog handles it
        lastFixAt = now
        val raw = speedMps * 3.6
        kph = when {
            raw < deadbandKph -> 0.0         // dead-band: snap the noise floor to zero
            kph == 0.0 -> raw                // starting to move: take it as-is
            else -> kph * 0.6 + raw * 0.4    // light smoothing while cruising
        }
    }

    /** Value to show right now. Also call from a 1 s ticker so a stopped car reads 0. */
    fun value(now: Long): Double {
        if (lastFixAt != 0L && now - lastFixAt > staleAfterMs) kph = 0.0
        return kph
    }

    fun reset() {
        kph = 0.0
        lastFixAt = 0L
    }
}
