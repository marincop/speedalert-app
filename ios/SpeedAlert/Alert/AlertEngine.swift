import Foundation
import CoreLocation

/// Multi-stage alert engine.
///
/// Fires at 500 m → 300 m → 100 m → 0 m (passed), per point, exactly once
/// per approach. State resets when the driver has clearly moved away, so the
/// same camera re-alerts on the next pass.
///
/// Stage set follows the *smoothed* vehicle speed when `autoSpeedAdjust` is on:
/// fast roads keep the long 500 m heads-up, dense slow traffic only warns at
/// 100 m. The stage set is swapped only when it really changes, so a new GPS
/// fix with the same speed band never re-announces a point.
final class AlertEngine {

    // MARK: - Stage presets

    /// Distances (metres) to alert at. 0 == "passed".
    static let defaultStages: [CLLocationDistance] = [500, 300, 100, 0]

    /// > 60 km/h — expressway / highway.
    static let fastStages: [CLLocationDistance] = [500, 300, 100, 0]
    /// 30–60 km/h — ordinary road.
    static let mediumStages: [CLLocationDistance] = [300, 100, 0]
    /// < 30 km/h — slow / congested traffic.
    static let slowStages: [CLLocationDistance] = [100, 0]
    /// Used while no valid speed reading exists (treated as "ordinary road").
    static let unknownSpeedStages: [CLLocationDistance] = [300, 100, 0]

    /// Band edges, km/h.
    static let fastSpeedKph: Double = 60
    static let slowSpeedKph: Double = 30
    /// Hysteresis (km/h) on band changes: a speed sitting exactly on an edge
    /// (e.g. 60 ± 1) would otherwise flip the stage set back and forth, and
    /// every flip clears per-point state → repeated alerts. 5 → enter "fast"
    /// above 65, leave it below 55; enter "slow" below 25, leave it above 35.
    static let speedHysteresisKph: Double = 5
    /// Sliding window (seconds) used for the smoothed speed.
    static let speedWindow: TimeInterval = 30
    /// Global minimum gap between two spoken alerts (seconds). Dense urban
    /// data would otherwise turn into non-stop chatter even across points.
    static let minAlertInterval: TimeInterval = 15
    /// Anything faster than this is a GPS glitch, not a car.
    private static let maxPlausibleSpeedKph: Double = 300
    /// Speeds reported with worse accuracy than this (m/s) are ignored.
    private static let maxUsableSpeedAccuracy: Double = 10

    enum SpeedBand { case fast, medium, slow }

    private struct State {
        var fired: Set<Int> = []
        var lastDistance: CLLocationDistance = .greatestFiniteMagnitude
        var lastSeen: Date = Date()
        var passed = false
    }

    private struct SpeedSample {
        let at: Date
        let kph: Double
    }

    /// When true the stage set is derived from the smoothed speed; driven by
    /// the "依車速自動調整" switch in SettingsView (default on).
    var autoSpeedAdjust = true

    /// stages sorted descending (approach order): [500, 300, 100, 0]
    private var stages: [CLLocationDistance]
    private var states: [Int: State] = [:]

    /// Recent valid speed readings (last `speedWindow` seconds).
    private var speedSamples: [SpeedSample] = []
    /// Band currently applied; nil until a valid reading arrives.
    private var speedBand: SpeedBand?
    /// When the last alert was actually spoken (global min-gap).
    private var lastEmitAt: Date?

    /// Called with (spoken text, item, stage).
    var onAlert: ((String, EnforcementItem, CLLocationDistance) -> Void)?

    private let resetFactor: Double = 1.5     // move > maxStage*1.5 away -> reset
    private let passedWindow: CLLocationDistance = 60  // "close" when passing
    private let staleSeconds: TimeInterval = 120

    init(stages: [CLLocationDistance] = AlertEngine.defaultStages) {
        self.stages = stages.sorted(by: >)
    }

    /// Stage set for a band; nil (no speed known yet) → safe middle ground.
    static func stages(for band: SpeedBand?) -> [CLLocationDistance] {
        switch band {
        case .fast:   return AlertEngine.fastStages
        case .medium: return AlertEngine.mediumStages
        case .slow:   return AlertEngine.slowStages
        case .none:   return AlertEngine.unknownSpeedStages
        }
    }

    // MARK: - Configuration

    /// Apply the user's settings in one go.
    /// - `autoSpeed == false` → use `manualStages` verbatim (previous behaviour).
    /// - `autoSpeed == true`  → derive from the smoothed speed, falling back to
    ///   `unknownSpeedStages` while no valid speed is known.
    func applySettings(manualStages: [CLLocationDistance], autoSpeed: Bool) {
        let manual = manualStages.isEmpty ? AlertEngine.defaultStages : manualStages
        autoSpeedAdjust = autoSpeed
        updateStages(autoSpeed ? AlertEngine.stages(for: speedBand) : manual)
    }

    /// Swap the stage set. Per-point state is cleared only when the set really
    /// changed — calling this on every GPS fix would re-announce points that
    /// were already announced.
    func updateStages(_ newStages: [CLLocationDistance]) {
        let next = newStages.sorted(by: >)
        guard next != stages else { return }
        stages = next
        states.removeAll()
    }

    func reset() {
        states.removeAll()
        lastEmitAt = nil
        speedSamples.removeAll()
        speedBand = nil
        if autoSpeedAdjust { updateStages(AlertEngine.unknownSpeedStages) }
    }

    // MARK: - Processing

    /// Process one GPS fix together with the nearby hits for that fix.
    /// `hits` must include everything within the largest stage (pull at least 600 m).
    func process(location: CLLocation, hits: [NearbyHit], now: Date = Date()) {
        if autoSpeedAdjust {
            updateSpeedEstimate(location, now: now)
        }

        let maxStage = stages.first ?? 500

        for hit in hits {
            let id = hit.item.id
            let d = hit.distance
            var st = states[id] ?? State(lastSeen: now)

            // Clearly past everything -> drop state so next approach re-alerts.
            if d > maxStage * resetFactor {
                states[id] = nil
                continue
            }

            // "0 m" pass detection: was close, now moving away -> just passed it.
            if stages.contains(0), !st.passed,
               st.lastDistance < passedWindow, d > st.lastDistance + 5 {
                st.passed = true
                st.fired.insert(0)
                emit(hit.item, stage: 0, now: now)
            }

            // Approach stages, nearest first: when several qualify on the same
            // fix (app started mid-approach) the most accurate distance is the
            // one that gets spoken; the global min-gap silences the rest.
            for stage in stages.reversed() where stage > 0 {
                if d <= stage, !st.fired.contains(Int(stage)) {
                    st.fired.insert(Int(stage))
                    emit(hit.item, stage: stage, now: now)
                }
            }

            st.lastDistance = d
            st.lastSeen = now
            states[id] = st
        }

        // Forget items we haven't seen for a while (keeps the map tiny).
        states = states.filter { now.timeIntervalSince($0.value.lastSeen) < staleSeconds }
    }

    // MARK: - Speed → stages

    /// Update the smoothed speed and, only if the band actually changed, swap
    /// the stage set. Invalid / missing readings change nothing, so the last
    /// good stage set is kept.
    private func updateSpeedEstimate(_ location: CLLocation, now: Date) {
        let raw = location.speed                 // m/s, negative == invalid
        let accuracy = location.speedAccuracy

        let usable = raw.isFinite && raw >= 0
            && (accuracy.isNaN || accuracy < AlertEngine.maxUsableSpeedAccuracy)

        if usable {
            let kph = min(raw * 3.6, AlertEngine.maxPlausibleSpeedKph)
            speedSamples.append(SpeedSample(at: now, kph: kph))
        }
        // Sliding average over the last 30 s: robust to a single wild reading,
        // and steady enough that accelerating out of a red light or joining a
        // highway does not jitter the stage set.
        speedSamples.removeAll { now.timeIntervalSince($0.at) > AlertEngine.speedWindow }
        guard !speedSamples.isEmpty else { return }

        let avgKph = speedSamples.reduce(0) { $0 + $1.kph } / Double(speedSamples.count)
        let band = bandFor(kph: avgKph)
        guard band != speedBand else { return }   // 階段沒變 → 不動 per-point state
        speedBand = band
        updateStages(AlertEngine.stages(for: band))
    }

    /// Band lookup with hysteresis so a speed sitting on an edge does not flap.
    private func bandFor(kph: Double) -> SpeedBand {
        let h = AlertEngine.speedHysteresisKph
        let enterFast = AlertEngine.fastSpeedKph + h   // 65
        let stayFast  = AlertEngine.fastSpeedKph - h   // 55
        let enterSlow = AlertEngine.slowSpeedKph - h   // 25
        let staySlow  = AlertEngine.slowSpeedKph + h   // 35

        switch speedBand {
        case .fast:
            if kph >= stayFast { return .fast }
            return kph < enterSlow ? .slow : .medium
        case .slow:
            if kph <= staySlow { return .slow }
            return kph > enterFast ? .fast : .medium
        case .medium, .none:
            if kph > enterFast { return .fast }
            if kph < enterSlow { return .slow }
            return .medium
        }
    }

    // MARK: - Emit

    /// Speaks an alert, subject to the global minimum gap between two alerts.
    ///
    /// 「已通過」(stage 0) is deliberately *not* exempt: if pass confirmations
    /// bypassed the gap, a dense stretch of points would produce a run of
    /// "已通過…已通過…" announcements that defeats the anti-chatter goal. A
    /// skipped confirmation costs the driver nothing — the approach alert
    /// already told them the point was coming, and the fired mark still stops
    /// it re-firing on this pass.
    private func emit(_ item: EnforcementItem, stage: CLLocationDistance, now: Date) {
        if let last = lastEmitAt,
           now.timeIntervalSince(last) < AlertEngine.minAlertInterval {
            return
        }
        lastEmitAt = now
        onAlert?(AlertPhrase.text(for: item, stage: stage), item, stage)
    }
}

/// Builds the natural-sounding Traditional-Chinese alert strings.
enum AlertPhrase {

    static func text(for item: EnforcementItem, stage: CLLocationDistance) -> String {
        let noun = item.kind.spokenNoun

        if stage == 0 {
            return "已通過\(noun)"
        }

        let distance = "前方\(chineseNumber(Int(stage)))公尺"
        switch item.kind {
        case .accidentSegment:
            return "\(distance)易肇事路段，請小心駕駛"
        default:
            if let limit = item.limit {
                return "\(distance)\(noun)，限速\(chineseNumber(limit))公里"
            }
            return "\(distance)\(noun)"
        }
    }

    /// 500 -> 五百, 50 -> 五十, 110 -> 一百一十 … (0…9999)
    static func chineseNumber(_ n: Int) -> String {
        if n <= 0 { return "零" }
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let units = ["", "十", "百", "千"]
        let chars = Array(String(n)).compactMap { $0.wholeNumberValue }
        var out = ""
        let len = chars.count
        for (i, d) in chars.enumerated() {
            let pos = len - i - 1
            if d == 0 {
                if !out.isEmpty, out.last != "零" { out.append("零") }
                continue
            }
            // 10-19 read "十X", not "一十X"
            if pos == 1, d == 1, out.isEmpty { out.append("十"); continue }
            out.append(digits[d])
            out.append(units[pos])
        }
        while out.hasSuffix("零") { out.removeLast() }
        return out
    }
}

// MARK: - Voice-pack tokens

extension AlertPhrase {
    /// Clip token for a hazard kind.
    static func kindToken(_ k: EnforcementKind) -> String {
        switch k {
        case .fixedSpeed, .highwaySpeed:    return "kind_fixed"     // 測速照相
        case .intervalSpeed:                return "kind_interval"  // 區間測速
        case .techIntersection, .techOther: return "kind_tech"      // 科技執法
        case .accidentSegment:              return "kind_accident"  // 易肇事路段
        }
    }

    /// Token sequence for the voice pack, mirroring `text(for:stage:)`.
    static func tokens(for item: EnforcementItem, stage: CLLocationDistance) -> [String] {
        let kind = kindToken(item.kind)
        if stage == 0 { return ["passed", kind] }
        var t = ["lead_front", "dist_\(Int(stage))", "unit_m"]
        if item.kind == .accidentSegment {
            t += ["kind_accident", "accident_warn"]
        } else {
            t.append(kind)
            if let limit = item.limit { t += ["limit_pre", "num_\(limit)", "limit_post"] }
        }
        return t
    }
}
