import Foundation
import CoreLocation

/// UserDefaults keys ＋「啟動讀回」的純函式，供 `SettingsView` 的 `@AppStorage`
/// 與 `AppModel.init()` 共用。
///
/// 每一個會被寫進 UserDefaults 的設定，都必須在這裡描述一次：UI 綁這裡的 key，
/// 啟動時透過下面的函式讀回來。**只寫不讀**正是「易肇事路段關不掉」的成因
/// （設定頁把 `k_accident` 存了，但啟動時沒讀回來），所以新增設定時一定要
/// 一併補上這裡的 key 與讀回函式。
///
/// 所有讀回函式都吃一個 `UserDefaults` 參數，因此可以用測試專用的 suite 直接驗證。
enum AppSettings {

    // MARK: - Keys（唯一來源；值就是實際存在 UserDefaults 的名字）

    /// 「依車速自動調整提醒距離」
    static let autoSpeedKey = "autoSpeed"
    /// 語速
    static let voiceRateKey = "voiceRate"

    /// 提醒種類開關
    static let kFixedKey    = "k_fixed"
    static let kIntervalKey = "k_interval"
    static let kTechKey     = "k_tech"
    static let kAccidentKey = "k_accident"

    /// 提醒距離開關
    static let s500Key = "s500"
    static let s300Key = "s300"
    static let s100Key = "s100"
    static let s0Key   = "s0"

    /// 提醒距離開關：(UserDefaults key, 公尺)
    static let manualStageKeys: [(key: String, metres: CLLocationDistance)] = [
        (s500Key, 500), (s300Key, 300), (s100Key, 100), (s0Key, 0)
    ]

    // MARK: - Defaults（必須與 SettingsView 的 @AppStorage 初始值一致）

    static let autoSpeedDefault = true
    static let toggleDefault    = true
    static let voiceRateDefault: Double = 0.5
    /// Slider 的合法範圍（語速）。
    static let voiceRateRange: ClosedRange<Double> = 0.3...0.7

    // MARK: - 啟動讀回

    /// 手動選擇的提醒距離；從未設定或全部關掉時回退到預設值。
    static func manualStages(from defaults: UserDefaults) -> [CLLocationDistance] {
        var stages: [CLLocationDistance] = []
        for (key, metres) in manualStageKeys where bool(key, in: defaults) {
            stages.append(metres)
        }
        return stages.isEmpty ? AlertEngine.defaultStages : stages
    }

    /// 依車速自動調整（預設開啟）。
    static func autoSpeed(from defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: autoSpeedKey) as? Bool) ?? autoSpeedDefault
    }

    /// 提醒種類：k_fixed / k_interval / k_tech / k_accident → `EnforcementKind`。
    /// 這裡的對應必須與 SettingsView 的 Toggle 一一對應。
    static func enabledKinds(from defaults: UserDefaults) -> Set<EnforcementKind> {
        var kinds: Set<EnforcementKind> = []
        if bool(kFixedKey, in: defaults)    { kinds.formUnion([.fixedSpeed, .highwaySpeed]) }
        if bool(kIntervalKey, in: defaults) { kinds.insert(.intervalSpeed) }
        if bool(kTechKey, in: defaults)     { kinds.formUnion([.techIntersection, .techOther]) }
        if bool(kAccidentKey, in: defaults) { kinds.insert(.accidentSegment) }
        return kinds
    }

    /// 語速（給 `SpeechService.rate`）。超出 Slider 範圍的殘值會被夾住，
    /// 避免壞掉的值讓語音變成聽不見或爆掉。
    static func voiceRate(from defaults: UserDefaults) -> Float {
        let raw = (defaults.object(forKey: voiceRateKey) as? Double) ?? voiceRateDefault
        return Float(min(max(raw, voiceRateRange.lowerBound), voiceRateRange.upperBound))
    }

    // MARK: -

    /// `Bool` 讀取：key 不存在時回傳預設值（與 @AppStorage 的預設值一致）。
    private static func bool(_ key: String, in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? toggleDefault
    }
}
