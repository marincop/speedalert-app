#!/usr/bin/env python3
"""Generate the SpeedAlert AppIcon asset catalog (all iOS sizes) with PIL."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SET = ROOT / "SpeedAlert" / "Assets.xcassets" / "AppIcon.appiconset"
SET.mkdir(parents=True, exist_ok=True)

S = 1024
BG_TOP = (0x12, 0x1A, 0x2B)
BG_BOT = (0x04, 0x06, 0x0D)
RED = (0xE0, 0x2B, 0x2B)
WHITE = (0xFA, 0xFA, 0xFB)
CAM = (0x14, 0x16, 0x1D)
LENS_R = (0x2A, 0x2E, 0x3A)
LENS_G = (0xE8, 0xEA, 0xEF)
LENS_C = (0x1A, 0x1C, 0x24)


def base_icon() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    # vertical gradient
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)],
               fill=tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3)))
    cx = cy = S // 2
    # speed-limit sign: red ring + white face
    r_out, ring = 336, 84
    d.ellipse([cx - r_out, cy - r_out, cx + r_out, cy + r_out], fill=RED)
    r_in = r_out - ring
    d.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=WHITE)
    # camera body (dark) + lens
    bw, bh = 300, 196
    d.rounded_rectangle([cx - bw // 2, cy - bh // 2 + 14, cx + bw // 2, cy + bh // 2 + 14],
                        radius=40, fill=CAM)
    # top bump (viewfinder)
    d.rounded_rectangle([cx - 74, cy - bh // 2 - 34, cx + 30, cy - bh // 2 + 22],
                        radius=16, fill=CAM)
    # lens
    d.ellipse([cx - 92, cy - 92 + 14, cx + 92, cy + 92 + 14], fill=LENS_R)
    d.ellipse([cx - 64, cy - 64 + 14, cx + 64, cy + 64 + 14], fill=LENS_G)
    d.ellipse([cx - 38, cy - 38 + 14, cx + 38, cy + 38 + 14], fill=LENS_C)
    d.ellipse([cx - 16, cy - 46 + 14, cx - 2, cy - 32 + 14], fill=(255, 255, 255))
    # flash dot
    d.ellipse([cx + 88, cy - bh // 2 - 6, cx + 116, cy - bh // 2 + 22], fill=(255, 214, 102))
    return img


SIZES = {
    "icon-20@1.png": 20, "icon-20@2.png": 40, "icon-20@3.png": 60,
    "icon-29@1.png": 29, "icon-29@2.png": 58, "icon-29@3.png": 87,
    "icon-40@1.png": 40, "icon-40@2.png": 80, "icon-40@3.png": 120,
    "icon-60@2.png": 120, "icon-60@3.png": 180,
    "icon-76@1.png": 76, "icon-76@2.png": 152,
    "icon-83.5@2.png": 167, "icon-1024@1.png": 1024,
}

ENTRIES = [
    ("20x20", "2x", "icon-20@2.png"), ("20x20", "3x", "icon-20@3.png"),
    ("29x29", "2x", "icon-29@2.png"), ("29x29", "3x", "icon-29@3.png"),
    ("40x40", "2x", "icon-40@2.png"), ("40x40", "3x", "icon-40@3.png"),
    ("60x60", "2x", "icon-60@2.png"), ("60x60", "3x", "icon-60@3.png"),
    ("20x20", "1x", "icon-20@1.png"), ("29x29", "1x", "icon-29@1.png"),
    ("40x40", "1x", "icon-40@1.png"), ("76x76", "1x", "icon-76@1.png"),
    ("76x76", "2x", "icon-76@2.png"), ("83.5x83.5", "2x", "icon-83.5@2.png"),
    ("1024x1024", "1x", "icon-1024@1.png"),
]

IPAD_ENTRIES = {"icon-20@1.png", "icon-20@2.png", "icon-29@1.png", "icon-29@2.png",
                "icon-40@1.png", "icon-40@2.png", "icon-76@1.png", "icon-76@2.png",
                "icon-83.5@2.png"}


def write_contents() -> None:
    import json
    images = []
    for size, scale, fn in ENTRIES:
        img = {"size": size, "scale": scale, "filename": fn}
        if fn in IPAD_ENTRIES:
            images.append({"idiom": "ipad", **img})
            if fn in ("icon-20@2.png", "icon-29@2.png", "icon-40@2.png"):
                images.append({"idiom": "iphone", **img})
            if fn in ("icon-40@1.png", "icon-20@1.png", "icon-29@1.png"):
                pass
        else:
            images.append({"idiom": "iphone", **img})
    # App Store
    images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x",
                   "filename": "icon-1024@1.png"})
    (SET / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}},
                   indent=2), encoding="utf-8")


def main() -> None:
    icon = base_icon()
    for fn, px in SIZES.items():
        icon.resize((px, px), Image.LANCZOS).save(SET / fn)
    write_contents()

    # AccentColor + catalog root
    ac = ROOT / "SpeedAlert" / "Assets.xcassets" / "AccentColor.colorset"
    ac.mkdir(parents=True, exist_ok=True)
    (ac / "Contents.json").write_text(
        '{"colors":[{"color":{"color-space":"srgb","components":'
        '{"alpha":"1.000","blue":"0.960","green":"0.700","red":"0.180"}},'
        '"idiom":"universal"}],"info":{"author":"xcode","version":1}}', encoding="utf-8")
    (ROOT / "SpeedAlert" / "Assets.xcassets" / "Contents.json").write_text(
        '{"info":{"author":"xcode","version":1}}', encoding="utf-8")
    print(f"wrote {len(SIZES)} icons + Contents.json -> {SET}")


if __name__ == "__main__":
    main()
