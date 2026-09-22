#!/usr/bin/env python3
"""Generate Android launcher icons (mipmap-*) from the iOS 1024 icon."""
from pathlib import Path
from PIL import Image, ImageDraw

ANDROID = Path(__file__).resolve().parent.parent          # android/
SRC = ANDROID.parent / "ios" / "SpeedAlert" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024@1.png"

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def main() -> None:
    base = Image.open(SRC).convert("RGBA")
    for dens, px in DENSITIES.items():
        out = ANDROID / "app" / "src" / "main" / "res" / f"mipmap-{dens}"
        out.mkdir(parents=True, exist_ok=True)

        square = base.resize((px, px), Image.LANCZOS)
        square.save(out / "ic_launcher.png")

        mask = Image.new("L", (px, px), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, px - 1, px - 1], fill=255)
        round_icon = square.copy()
        round_icon.putalpha(mask)
        round_icon.save(out / "ic_launcher_round.png")
    print(f"wrote {len(DENSITIES)} densities (ic_launcher + ic_launcher_round)")


if __name__ == "__main__":
    main()
