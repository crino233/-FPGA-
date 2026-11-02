import hashlib
import json
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-rtl", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    card = root / "sim" / "tf_card"
    output = root / "sim" / "work" / "image_scale_demo"
    previews = root / "sim" / "work" / "image_scale_preview"
    output.mkdir(parents=True, exist_ok=True)
    previews.mkdir(parents=True, exist_ok=True)
    font_path = Path("C:/Windows/Fonts/consola.ttf")
    font = ImageFont.truetype(str(font_path), 24)
    small_font = ImageFont.truetype(str(font_path), 18)
    cases = {
        2: (1000, 1000),
        3: (960, 540),
        4: (600, 1000),
        5: (320, 240),
        6: (641, 479),
        7: (1920, 1080),
    }
    records = []
    tiles = []
    for index in range(1, 11):
        source = card / f"PIC{index}.BMP"
        if index not in cases:
            (output / source.name).write_bytes(source.read_bytes())
            continue
        width, height = cases[index]
        image = Image.new("RGB", (width, height), (30, 42, 48))
        draw = ImageDraw.Draw(image)
        k = min(width // 4, height // 3)
        crop_width, crop_height = k * 4, k * 3
        left, top = (width - crop_width) // 2, (height - crop_height) // 2
        right, bottom = left + crop_width - 1, top + crop_height - 1
        for x in range(0, width, 50):
            draw.line((x, 0, x, height - 1), fill=(67, 88, 97))
        for y in range(0, height, 50):
            draw.line((0, y, width - 1, y), fill=(67, 88, 97))
        draw.rectangle((left, top, right, bottom), fill=(40, 71, 82), outline=(255, 211, 70), width=4)
        margin = max(12, crop_width // 24)
        draw.text((left + margin, top + margin), f"PIC{index}  {width}x{height}", font=font, fill="white")
        draw.text((left + margin, top + margin + 34), "CENTER CROP 4:3", font=small_font, fill=(255, 211, 70))
        radius = min(crop_width, crop_height) // 5
        cx, cy = width // 2, height // 2
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                     fill=(38, 164, 143), outline="white", width=4)
        draw.line((cx - radius, cy, cx + radius, cy), fill="white", width=2)
        draw.line((cx, cy - radius, cx, cy + radius), fill="white", width=2)
        for n, (x, y) in enumerate(((left + margin, top + crop_height // 3),
                                    (right - margin - 40, top + crop_height // 3),
                                    (left + margin, bottom - margin - 40),
                                    (right - margin - 40, bottom - margin - 40)), 1):
            draw.text((x, y), str(n), font=font, fill="white")
        target = output / source.name
        image.save(target, format="BMP")
        xs = left + ((2 * np.arange(640) + 1) * crop_width) // 1280
        ys = top + ((2 * np.arange(480) + 1) * crop_height) // 960
        expected = Image.fromarray(np.asarray(image)[ys[:, None], xs])
        preview_path = previews / f"pic{index}_expected.png"
        expected.save(preview_path)
        (previews / f"pic{index}_expected.rgb").write_bytes(expected.tobytes())
        if args.verify_rtl:
            actual = (previews / f"pic{index}_rtl.rgb").read_bytes()
            if actual != expected.tobytes():
                raise RuntimeError(f"PIC{index} RTL output differs from the independent oracle")
            Image.frombytes("RGB", (640, 480), actual).save(previews / f"pic{index}_rtl.png")
        tile = Image.new("RGB", (640, 512), "white")
        tile.paste(expected, (0, 32))
        ImageDraw.Draw(tile).text((8, 6), f"PIC{index}: {width}x{height} -> 640x480", font=small_font, fill="black")
        tiles.append(tile)
        records.append({
            "file": str(target), "width": width, "height": height,
            "crop": [left, top, crop_width, crop_height],
            "bytes": target.stat().st_size,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest().upper(),
            "expected_preview": str(preview_path),
        })
    for name in ("BGM.WAV",):
        source = card / name
        if source.exists():
            (output / name).write_bytes(source.read_bytes())
    for name in ("NOTICE.TXT", "TEACHER.TXT"):
        source = root / "sim" / "fixtures" / "card_a" / name
        (output / name).write_bytes(source.read_bytes())
    contact = Image.new("RGB", (1280, 1536), "white")
    for index, tile in enumerate(tiles):
        contact.paste(tile, ((index % 2) * 640, (index // 2) * 512))
    contact.save(previews / "expected_contact_sheet.png")
    manifest = {"type": "software_expected_preview", "output": [640, 480],
                "minimum_recommended_cluster_bytes": 4096, "cases": records}
    (previews / "demo_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Demo card: {output}")
    print(f"Software expected previews: {previews}")
    if args.verify_rtl:
        print("PASS six actual BMP files match all 1,843,200 RTL output pixels")


if __name__ == "__main__":
    main()
