// SpeedFilter 的假軌跡測試。
//
// 為什麼要這樣測：老闆過去「改了好幾次」的成本，是每一次都要真的開車上路。
// 這個檔把 SpeedFilter 編成 macOS 命令列程式，餵「合成的 GPS 軌跡」驗證，
// 不必開模擬器、不必上車。
//
// 執行：
//   xcrun swiftc -O -o /tmp/sf/run SpeedFilter.swift main.swift && /tmp/sf/run

import Foundation

// ── 決定性亂數（測試要可重現，不能用系統 RNG）──
final class Rng {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed }
    func unit() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 11) & 0x1F_FFFF_FFFF_FFFF) / Double(1 << 53)
    }
    func pm(_ r: Double) -> Double { unit() * 2 * r - r }   // -r ..< r
}
var rng = Rng(20260929)

let METERS_PER_DEG_LAT = 111_320.0

// ── 一條合成軌跡 ──
struct Trace {
    var filter = SpeedFilter()
    var t = Date(timeIntervalSince1970: 1_700_000_000)
    var lat = 25.0330
    var lon = 121.5654
    var shown: [Double] = []

    /// 餵一筆定位：向北移動 `meters`、車速 `speedKph`、位置雜訊 ±`jitter` 公尺
    mutating func step(speedKph: Double, meters: Double, jitter: Double = 0,
                       accuracy: Double = 5, speedAccuracy: Double = 0.5) {
        lat += meters / METERS_PER_DEG_LAT
        let jLat = jitter == 0 ? 0 : rng.pm(jitter) / METERS_PER_DEG_LAT
        filter.update(speedMps: speedKph / 3.6,
                      horizontalAccuracy: accuracy,
                      speedAccuracy: speedAccuracy,
                      latitude: lat + jLat,
                      longitude: lon,
                      at: t)
        shown.append(filter.value(at: t))      // 對齊 AppModel：update 後立刻 value
        t = t.addingTimeInterval(1)
    }

    /// 完全沒有定位（隧道）時，只有每秒的 watchdog 在跑
    mutating func idle(seconds: Int) {
        for _ in 0..<seconds {
            shown.append(filter.value(at: t))
            t = t.addingTimeInterval(1)
        }
    }

    func tail(_ n: Int) -> [Double] { Array(shown.suffix(n)) }
}

var pass = 0, fail = 0
func check(_ ok: Bool, _ label: String, _ detail: String) {
    if ok { pass += 1; print("  ✅ \(label)  \(detail)") }
    else { fail += 1; print("  ❌ \(label)  \(detail)") }
}

// ══════════════════════════════════════════════════════════════
print("\n═══ ① 核心案例：行駛 → 煞停 → 靜止但餵 0~8 km/h 雜訊 30 秒 ═══")
var a = Trace()
for _ in 0..<5 { a.step(speedKph: 40, meters: 11.1) }           // 行駛 40 km/h
for i in 0..<6 { a.step(speedKph: max(0, 40 - Double(i) * 7), meters: 6 - Double(i)) } // 煞車
for _ in 0..<30 {                                                // 靜止：亂數雜訊 0~8
    a.step(speedKph: rng.unit() * 8, meters: 0, jitter: 2.0)
}
let stillTail = a.tail(20)
check(stillTail.allSatisfy { $0 == 0 },
      "靜止 30 秒後顯示必須全程為 0",
      "最後 20 秒: \(stillTail.map { Int($0) })")

// ══════════════════════════════════════════════════════════════
print("\n═══ ② 靜止 → 起步加速到 20 km/h ═══")
var b = Trace()
for _ in 0..<10 { b.step(speedKph: rng.unit() * 6, meters: 0, jitter: 1.5) }  // 先停著
for i in 1...6 { b.step(speedKph: Double(i) * 3.5, meters: Double(i) * 1.0) } // 起步
let accel = b.tail(6)
check(accel.contains { $0 > 15 }, "起步後必須顯示真實車速（不能卡在 0）",
      "起步 6 秒: \(accel.map { Int($0) })")

// ══════════════════════════════════════════════════════════════
print("\n═══ ③ 穩定以 8 km/h 行駛 12 秒（6 秒位移 13.3 公尺 > 門檻）═══")
var c = Trace()
for _ in 0..<12 { c.step(speedKph: 8, meters: 2.22, jitter: 1.0) }
let cruise = c.tail(6)
check(cruise.allSatisfy { $0 > 0 }, "實際移動就要顯示速度", "顯示: \(cruise.map { Int($0) })")

// ══════════════════════════════════════════════════════════════
print("\n═══ ④ 行駛中進隧道：10 秒沒有任何有效車速／定位 ═══")
var d = Trace()
for _ in 0..<8 { d.step(speedKph: 50, meters: 13.9) }
for _ in 0..<10 { d.step(speedKph: -1, meters: 0, jitter: 0, accuracy: -1, speedAccuracy: -1) }
let tunnel = d.tail(10)
check(tunnel.last == 0 && tunnel.suffix(6).allSatisfy { $0 == 0 },
      "失去訊號必須歸零（不能凍結在 50）", "隧道 10 秒: \(tunnel.map { Int($0) })")

// ══════════════════════════════════════════════════════════════
print("\n═══ ⑤ 門檻邊緣抖動：位置幾乎不動、車速在 2~6 之間亂跳 20 秒 ═══")
var e = Trace()
for _ in 0..<20 { e.step(speedKph: 2 + rng.unit() * 4, meters: 0, jitter: 1.0) }
let edge = e.tail(20)
var flips = 0
for i in 1..<edge.count where (edge[i] == 0) != (edge[i - 1] == 0) { flips += 1 }
check(flips == 0, "不得在 0 與非 0 之間反覆閃動", "20 秒內翻轉 \(flips) 次")

// ══════════════════════════════════════════════════════════════
print("\n═══ ⑥ 靜止但定位品質極差（位置 ±12 公尺亂飄、精度 40 → 不納入位移）═══")
var f = Trace()
for _ in 0..<25 { f.step(speedKph: rng.unit() * 7, meters: 0, jitter: 12.0, accuracy: 40) }
let bad = f.tail(15)
check(bad.allSatisfy { $0 == 0 }, "無位移證據時也不能被 7 km/h 雜訊騙到",
      "顯示: \(bad.map { Int($0) })")

// ══════════════════════════════════════════════════════════════
print("\n═══ ⑦ 刻意的取捨：真的慢慢滑行 5 km/h（6 秒只走 8.3 公尺）═══")
var g = Trace()
for _ in 0..<15 { g.step(speedKph: 5, meters: 1.39, jitter: 0.8) }
let creep = g.tail(5)
print("\n  顯示: \(creep.map { Int($0) })")
print("  → 5 km/h 位移 < 9 公尺門檻 ⇒ 依設計顯示 0（寧可對慢速顯示 0，不要對停車顯示數字）")

// ══════════════════════════════════════════════════════════════
print("\n═══ ⑧ 冷啟動時車子已經在行駛（40 km/h）——不能被暖機門檻卡住 ═══")
var h = Trace()
for _ in 0..<6 { h.step(speedKph: 40, meters: 11.1) }
let cold = h.tail(6)
check(cold.suffix(4).allSatisfy { $0 > 30 }, "行駛中啟動要在 2 秒內顯示真實車速",
      "顯示: \(cold.map { Int($0) })")

print("\n══════════════════════════════════════════")
print("結果：pass \(pass) / fail \(fail)")
if fail > 0 { exit(1) }
