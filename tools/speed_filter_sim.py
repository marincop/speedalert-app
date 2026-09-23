#!/usr/bin/env python3
"""
speed_filter_sim.py — 驗證 SpeedFilter 邏輯（與 Swift/Kotlin 同一套演算法）

情境：0→50 km/h 巡航 → t=5s 起煞停 → 靜止到 t=20s。GPS 1 Hz、杜普勒噪聲 ~N(0,1.5) km/h。

【舊版】距離過濾：移動 <10m 就不送點 → 停止送點後顯示值凍結。
【新版】minDistance=0 連續送點 + dead-band(<=3 歸零) + 看門狗(>3s 無點歸零)。
"""

import random

random.seed(11)
MPS = 3.6
DEADBAND = 3.0
STALE_AFTER = 3.0
DT = 0.5


def true_speed(t):                       # km/h
    if t < 1:  return 20 * t
    if t < 5:  return 50
    if t < 5.6: return max(0.0, 50 - (50 / 0.6) * (t - 5))
    return 0.0


def gps_fix(t):
    """回傳 (noisy_speed_kmh, moved_m_this_tick)。靜止時杜普勒仍會飄幾 km/h。"""
    v = true_speed(t)
    if v <= 0.5:
        return (max(0.0, random.gauss(0, 1.5)), 0.0)     # 靜止：位置不動，但 1Hz 仍送速度
    return (max(0.0, v + random.gauss(0, 1.5)), v / MPS)


def run():
    old_disp, dist = 0.0, 0.0            # 舊版
    new_kph, last_fix = 0.0, None        # 新版
    print(f"{'t':>4} {'真實':>6} {'GPS':>6} | {'舊版顯示':>8} {'新版顯示':>8}")
    print("-" * 44)
    for i in range(0, 41):
        t = i * DT
        v, moved = gps_fix(t)

        # ── 舊版：距離過濾(>=10m 才更新) + 直接顯示 ──
        dist += moved * DT
        if dist >= 10.0:
            old_disp, dist = v, 0.0

        # ── 新版：連續送點 → dead-band + 輕平滑 + 看門狗 ──
        if v < DEADBAND:
            new_kph = 0.0
        elif new_kph == 0.0:
            new_kph = v
        else:
            new_kph = new_kph * 0.6 + v * 0.4
        last_fix = t
        if last_fix is not None and t - last_fix > STALE_AFTER:
            new_kph = 0.0

        print(f"{t:>4.1f} {true_speed(t):>6.1f} {v:>6.1f} | {old_disp:>8.1f} {new_kph:>8.1f}")


run()
print("\n重點：煞停後舊版『凍結』在煞停前值（你的情況 ~5-10）；新版 <=0.5s 歸零。")
