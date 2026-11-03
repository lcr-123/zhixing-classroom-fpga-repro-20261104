"""Recompose the supplied cover at VGA resolution and package optional 00.bmp.

Uses original pixels for the logo/title, with no generative image processing.
The input must be the supplied 16:9 Anlogic English learning machine cover.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

from PIL import Image


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def build(source, output, course):
    output.mkdir(parents=True, exist_ok=False)
    original = output / "source_original.png"
    shutil.copy2(source, original)
    image = Image.open(original).convert("RGB")
    if image.width * 9 != image.height * 16:
        raise ValueError("expected the supplied 16:9 cover")
    image = image.resize((2048, 1152), Image.Resampling.LANCZOS)
    # Remove the copyright line using the same untouched patterned background.
    clean = image.copy()
    clean.paste(image.crop((0, 1016, 520, 1068)), (0, 1100))
    clean.save(output / "cover_clean_16x9.png")
    # Clear the two foreground blocks, then scale only the background to 4:3.
    background = clean.copy()
    background.paste(image.crop((180, 269, 545, 369)), (180, 65))
    background.paste(image.crop((470, 175, 1280, 435)), (470, 460))
    canvas = background.resize((640, 480), Image.Resampling.LANCZOS)
    # Original aspect ratios and lettering are retained in these two crops.
    logo = image.crop((180, 65, 545, 165))
    title = image.crop((470, 465, 1280, 735))
    for block, size, position in ((logo, (146, 40), (52, 28)),
                                  (title, (360, 120), (92, 188))):
        # Mask out the crop's paper texture so the new background is continuous.
        mask = block.convert("L").point(lambda value: 255 if value < 200 else 0)
        block = block.resize(size, Image.Resampling.LANCZOS)
        mask = mask.resize(size, Image.Resampling.LANCZOS)
        canvas.paste(block, position, mask)
    canvas.save(output / "home_640x480.png")
    ready = output / "tf_card_ready"
    ready.mkdir()
    canvas.save(ready / "00.bmp")
    for number in range(1, 13):
        path = course / f"{number:02}.bmp"
        if not path.is_file():
            raise FileNotFoundError(path)
        target = ready / path.name
        shutil.copy2(path, target)
        if digest(path) != digest(target):
            raise ValueError(f"course copy mismatch: {path.name}")
    header = (ready / "00.bmp").read_bytes()
    assert len(header) == 921654 and header[:2] == b"BM"
    assert struct.unpack_from("<IiiHHI", header, 14) == (40, 640, 480, 1, 24, 0)
    assert struct.unpack_from("<I", header, 10)[0] == 54
    with Image.open(ready / "00.bmp") as decoded:
        assert decoded.tobytes() == canvas.tobytes()
    manifest = {
        "format": "640x480, RGB24, bottom-up BI_RGB BMP",
        "home": "00.bmp (internal slot 12)",
        "course": str(course.resolve()),
        "course_files_unchanged": True,
        "hardware_validation": "NOT_RUN",
        "files": {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)}
                  for p in sorted(ready.glob("*.bmp"))},
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text("".join(
        f"{info['sha256']}  tf_card_ready/{name}\n"
        for name, info in manifest["files"].items()), encoding="ascii")
    (output / "README.txt").write_text(
        "首页版素材：将 tf_card_ready 内的 00.bmp～12.bmp 复制到 FAT32 TF 根目录。\n"
        "00.bmp 是独立首页，必须搭配支持独立首页的新位流；旧位流会忽略它。\n"
        "01～12.bmp 与现行保音调 LMV2 素材逐字节一致，切勿改名或覆盖音频尾包。\n"
        "首页缺失/坏图时新版回退原第一张学习图。HDMI/上板验证尚未运行。\n",
        encoding="utf-8")
    print(f"VALIDATION_PASS home_cover: 640x480 RGB24, 13 files; {output}")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=root / "artifacts/home_cover_20261020")
    parser.add_argument("--course", type=Path, default=root / "artifacts/english_nature_pitch_preserving_audio_v2/tf_card_ready_pitch_preserving")
    args = parser.parse_args()
    build(args.source, args.output, args.course)
