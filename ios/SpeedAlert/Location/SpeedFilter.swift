import Foundation

/// Turns noisy, intermittent GPS speed readings into a stable display value.
///
/// ## 為什麼需要「兩個」訊號
///
/// 只靠 `CLLocation.speed` 判斷「停了沒」是做不到的：
///
///  - **靜止時杜普勒速度不會歸零**：市區、樹下、橋下會飄到 4~8 km/h。
///    這是實測回報的症狀——車停了，螢幕還顯示 5~8。
///  - **把門檻調高就換另一邊出錯**：真的慢慢滑行（5 km/h）會被顯示成 0。
///    這是行車安全 App，明明在動卻顯示 0 更危險。
///
/// ⇒ 只在同一個訊號上調參數是死結。**加第二個獨立證據：實際位移。**
///   位置不會騙人 —— 真的在動，6 秒會平移十幾公尺；靜止時只會在原點附近飄幾公尺。
///
/// ## 判定順序
///
/// ```
/// 位移明確「沒動」(< stillMeters)  → 強制 0（不管車速說幾 km/h） ← 解決停車雜訊
/// 車速有效且 < deadbandKph         → 0
/// 其他                              → 車速夠大時才離開 0（需連續 confirmSamples 筆）
/// ```
///
/// 煞車回 0 **不設遲滯**（要即時）；離開 0 要連續幾筆合格（擋掉單筆雜訊突波）。
/// `staleAfter` 秒沒有有效車速也歸零（隧道／訊號丟失）。
///
/// ⚠️ 已知限制：靜止但定位品質很差（水平精度 > maxHorizontalAccuracy）時，
///    位置會在原點附近大幅飄移，此時位移證據不成立，只能退回車速判斷。
///    在開闊路段與一般市區（精度 5~15 公尺）本過濾器可正確歸零。
///
/// 刻意只依賴 Foundation（距離用等距圓柱近似自算，不需要 CoreLocation），
/// 因此這個檔可以在 Mac 上直接編成命令列程式、餵假軌跡驗證，不必開模擬器或真車。
struct SpeedFilter {
    // ── 可調參數 ──

    /// 低於這個車速視為靜止（GPS 雜訊底噪），km/h。
    var deadbandKph: Double = 4.0
    /// 位移小於這個距離視為「確定沒動」，公尺。
    /// 訂 9.0 的理由：6 秒走 9 公尺 ≈ 5.4 km/h，
    /// 所以「時速 6 以上」的實際移動不會被誤判成靜止，而停車雜訊（位置不動）一定會歸零。
    var stillMeters: Double = 9.0
    /// 位移窗長度（秒）。
    var windowSeconds: TimeInterval = 6.0
    /// 位移窗至少要幾筆可信定位才算數。
    var minWindowFixes: Int = 3
    /// 離開 0 需要連續幾筆合格樣本（抑制單筆雜訊突波）。
    var confirmSamples: Int = 2
    /// ★ 暖機門檻：位移窗還沒滿（無法用位移判斷）時，車速要高於這個才敢離開 0。
    ///
    /// 為什麼需要：App 剛啟動／剛重置時沒有位移證據，此時若沿用 4 km/h 的門檻，
    /// 停車雜訊（4~8 km/h）會先讓數字跳出來、等位移窗滿了才被壓回 0 —— 出現閃動。
    /// 拉高到 12 km/h（＝3.3 m/s）則「停車雜訊到不了、真的在開一定過」。
    var warmupKph: Double = 12.0
    /// 多久沒有有效車速就歸零（秒）。
    var staleAfter: TimeInterval = 3.0
    /// 水平精度比這個差就不納入位移計算（公尺）。
    var maxHorizontalAccuracy: Double = 25.0
    /// 速度精度比這個差就不採用該筆車速（m/s）。
    var maxSpeedAccuracy: Double = 3.0

    private struct Fix {
        let t: Date
        let lat: Double
        let lon: Double
    }

    private var kph: Double = 0
    private var lastSpeedAt: Date?
    private var window: [Fix] = []
    private var confirmStreak = 0

    /// Feed a raw fix.
    ///
    /// - Parameters:
    ///   - speedMps: `CLLocation.speed`（負值 = 無效）。
    ///   - horizontalAccuracy: `CLLocation.horizontalAccuracy`（負值 = 不採用於位移）。
    ///   - speedAccuracy: `CLLocation.speedAccuracy`（負值 = 不檢查）。
    ///   - latitude/longitude: 座標（`.nan` = 沒有位置）。
    mutating func update(speedMps: Double,
                         horizontalAccuracy: Double = -1,
                         speedAccuracy: Double = -1,
                         latitude: Double = .nan,
                         longitude: Double = .nan,
                         at now: Date) {
        recordPosition(lat: latitude, lon: longitude,
                       horizontalAccuracy: horizontalAccuracy, at: now)

        // 車速可用嗎？（無效值或被判定為低品質 ⇒ 不採用）
        let speedUsable = speedMps >= 0 && (speedAccuracy < 0 || speedAccuracy <= maxSpeedAccuracy)
        if speedUsable { lastSpeedAt = now }
        let raw = speedUsable ? speedMps * 3.6 : -1

        // ── 位移證據：確定沒動就強制歸零（這是解決停車雜訊的關鍵）──
        let moved = displacement()
        if let moved, moved < stillMeters {
            kph = 0
            confirmStreak = 0
            return
        }

        // ── 車速本身很小 ⇒ 歸零（煞車要即時，這裡不設遲滯）──
        if speedUsable && raw < deadbandKph {
            kph = 0
            confirmStreak = 0
            return
        }

        guard speedUsable else { return }   // 沒有可用車速也沒有位移證據：維持現狀

        // ── 離開 0：要連續幾筆都超過門檻，擋掉單筆突波 ──
        if kph == 0 {
            // 位移窗還沒滿（moved == nil）時無法證明「真的在動」⇒ 門檻拉高到暖機值。
            // 這一條同時解掉兩個問題：啟動瞬間的閃動，以及定位品質太差時對雜訊的反應。
            let bar = (moved == nil) ? warmupKph : deadbandKph
            guard raw >= bar else {
                confirmStreak = 0
                return
            }
            confirmStreak += 1
            if confirmStreak >= confirmSamples {
                kph = raw
                confirmStreak = 0
            }
            return
        }

        // ── 已在移動：升速輕微平滑（數字不跳動）、降速不平滑（煞車即時）──
        kph = raw < kph ? raw : kph * 0.6 + raw * 0.4
    }

    /// Value to show right now. Call this from a 1 s timer too, so a stopped
    /// car reads 0 even after the OS stops delivering fixes.
    mutating func value(at now: Date) -> Double {
        if let last = lastSpeedAt, now.timeIntervalSince(last) > staleAfter {
            kph = 0
            confirmStreak = 0
            window.removeAll()
        } else {
            trimWindow(now)
        }
        return kph
    }

    mutating func reset() {
        kph = 0
        lastSpeedAt = nil
        window.removeAll()
        confirmStreak = 0
    }

    // ── 內部：位移窗 ──

    private mutating func recordPosition(lat: Double, lon: Double,
                                         horizontalAccuracy: Double, at now: Date) {
        guard !lat.isNaN, !lon.isNaN else { return }
        // 精度太差的定位不能拿來判斷「有沒有動」（會原地大幅飄移）
        if horizontalAccuracy >= 0 && horizontalAccuracy > maxHorizontalAccuracy { return }
        window.append(Fix(t: now, lat: lat, lon: lon))
        trimWindow(now)
    }

    private mutating func trimWindow(_ now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        if let first = window.first, first.t < cutoff {
            window.removeAll { $0.t < cutoff }
        }
    }

    /// 窗內最遠兩點的水平距離（公尺）。樣本不足時回 nil ⇒ 不以此為證據。
    func displacement() -> Double? {
        guard window.count >= minWindowFixes else { return nil }
        var best = 0.0
        for i in 0..<window.count {
            for j in (i + 1)..<window.count {
                let d = Self.meters(window[i].lat, window[i].lon, window[j].lat, window[j].lon)
                if d > best { best = d }
            }
        }
        return best
    }

    /// 等距圓柱近似（1 公里內誤差 < 1 公尺，足夠判斷「有沒有動」）。
    /// 自己算而不用 CLLocation，是為了讓這個檔不必依賴 CoreLocation、能獨立測試。
    static func meters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = phi2 - phi1
        let dLambda = (lon2 - lon1) * .pi / 180
        let x = dLambda * cos((phi1 + phi2) / 2)
        return r * (x * x + dPhi * dPhi).squareRoot()
    }
}
