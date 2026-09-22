import Foundation
import CoreLocation

/// Multi-stage alert engine.
///
/// Fires at 500 m → 300 m → 100 m → 0 m (passed), per point, exactly once
/// per approach. State resets when the driver has clearly moved away, so the
/// same camera re-alerts on the next pass.
final class AlertEngine {

    /// Distances (metres) to alert at. 0 == "passed".
    static let defaultStages: [CLLocationDistance] = [500, 300, 100, 0]

    private struct State {
        var fired: Set<Int> = []
        var lastDistance: CLLocationDistance = .greatestFiniteMagnitude
        var lastSeen: Date = Date()
        var passed = false
    }

    /// stages sorted descending (approach order): [500, 300, 100, 0]
    private var stages: [CLLocationDistance]
    private var states: [Int: State] = [:]

    /// Called with (spoken text, item, stage).
    var onAlert: ((String, EnforcementItem, CLLocationDistance) -> Void)?

    private let resetFactor: Double = 1.5     // move > maxStage*1.5 away -> reset
    private let passedWindow: CLLocationDistance = 60  // "close" when passing
    private let staleSeconds: TimeInterval = 120

    init(stages: [CLLocationDistance] = AlertEngine.defaultStages) {
        self.stages = stages.sorted(by: >)
    }

    func updateStages(_ newStages: [CLLocationDistance]) {
        stages = newStages.sorted(by: >)
        states.removeAll()
    }

    func reset() { states.removeAll() }

    /// Process one GPS fix together with the nearby hits for that fix.
    /// `hits` must include everything within the largest stage (pull at least 600 m).
    func process(location: CLLocation, hits: [NearbyHit], now: Date = Date()) {
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
                emit(hit.item, stage: 0)
            }

            // Approach stages (ignore 0 here; handled above).
            for stage in stages where stage > 0 {
                if d <= stage, !st.fired.contains(Int(stage)) {
                    st.fired.insert(Int(stage))
                    emit(hit.item, stage: stage)
                }
            }

            st.lastDistance = d
            st.lastSeen = now
            states[id] = st
        }

        // Forget items we haven't seen for a while (keeps the map tiny).
        states = states.filter { now.timeIntervalSince($0.value.lastSeen) < staleSeconds }
    }

    private func emit(_ item: EnforcementItem, stage: CLLocationDistance) {
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
