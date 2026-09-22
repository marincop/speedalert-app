#!/usr/bin/env python3
"""Generate the bundled voice pack with edge-tts (Taiwan Mandarin neural voices).

Writes <token>.mp3 into BOTH the Android assets and the iOS resources, so the
app plays prerecorded clips and does NOT depend on the device's TTS engine.

    pip install edge-tts
    python3 tools/make_voicepack.py            # default voice: zh-TW-HsiaoChenNeural
    VOICE=zh-TW-HsiaoYuNeural python3 tools/make_voicepack.py

Clips are meant to be a start; replace with a voice actor's recordings later
(same filenames). See ios/VOICEPACK.md.
"""
from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = [
    ROOT / "android" / "app" / "src" / "main" / "assets" / "VoicePack",
    ROOT / "ios" / "SpeedAlert" / "Resources" / "VoicePack",
]
VOICE = os.environ.get("VOICE", "zh-TW-HsiaoChenNeural")

CLIPS = {
    "lead_front": "前方",
    "unit_m": "公尺",
    "limit_pre": "限速",
    "limit_post": "公里",
    "passed": "已通過",
    "accident_warn": "請小心駕駛",
    "dist_500": "五百",
    "dist_300": "三百",
    "dist_100": "一百",
    "kind_fixed": "測速照相",
    "kind_interval": "區間測速",
    "kind_tech": "科技執法",
    "kind_accident": "易肇事路段",
    "num_25": "二十五",
    "num_30": "三十",
    "num_40": "四十",
    "num_50": "五十",
    "num_60": "六十",
    "num_70": "七十",
    "num_80": "八十",
    "num_90": "九十",
    "num_100": "一百",
    "num_110": "一百一十",
}


def main() -> int:
    edge_tts = shutil.which("edge-tts")
    if not edge_tts:
        print("edge-tts not found.  pip install edge-tts", file=sys.stderr)
        return 1
    for t in TARGETS:
        t.mkdir(parents=True, exist_ok=True)
    for token, text in CLIPS.items():
        out = TARGETS[0] / f"{token}.mp3"
        subprocess.run(
            [edge_tts, "--voice", VOICE, "--text", text, "--write-media", str(out)],
            check=True, capture_output=True,
        )
        for t in TARGETS[1:]:
            shutil.copy(out, t / f"{token}.mp3")
        print(f"  {token}.mp3  <- {text}")
    print(f"done: {len(CLIPS)} clips (voice={VOICE})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
