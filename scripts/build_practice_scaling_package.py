"""Build practice BMPs at three 4:3 source sizes from the retained artwork."""

from __future__ import annotations

import hashlib
import io
import json
import struct
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ZIP = ROOT / "artifacts/home_cover_final_20261020/tf_card_ready_640x480.zip"
ARTWORK = ROOT / "artifacts/english_nature_cards_v1/source_png"
OUTPUT = ROOT / "artifacts/practice_scaling_20261027"
SIZES = {**{n: (1280, 960) for n in range(4, 7)},
         **{n: (800, 600) for n in range(7, 10)},
         **{n: (320, 240) for n in range(10, 13)}}


def bmp_size(data: bytes) -> tuple[int, int]:
    assert data[:2] == b"BM" and len(data) >= 54
    assert struct.unpack_from("<I", data, 2)[0] == len(data)
    width, height = struct.unpack_from("<ii", data, 18)
    planes, depth = struct.unpack_from("<HH", data, 26)
    assert planes == 1 and depth == 24
    assert struct.unpack_from("<I", data, 30)[0] == 0
    offset = struct.unpack_from("<I", data, 10)[0]
    stride = (width * 3 + 3) & ~3
    assert width > 0 and height > 0 and offset + stride * height <= len(data)
    return width, height


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / "tf_card_practice_scaling.zip"
    manifest = {"output_size": [640, 480], "files": {}}
    with zipfile.ZipFile(SOURCE_ZIP) as source, zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as target:
        assert sorted(source.namelist()) == [f"{n:02d}.bmp" for n in range(13)]
        for number in range(13):
            name = f"{number:02d}.bmp"
            if number in SIZES:
                artwork = next(ARTWORK.glob(f"{number:02d}_*.png"))
                with Image.open(artwork) as source_image:
                    image = source_image.convert("RGB").resize(
                        SIZES[number], Image.Resampling.LANCZOS
                    )
                    buffer = io.BytesIO()
                    image.save(buffer, format="BMP")
                    data = buffer.getvalue()
            else:
                data = source.read(name)
            actual_size = bmp_size(data)
            assert actual_size == SIZES.get(number, (640, 480))
            target.writestr(name, data)
            manifest["files"][name] = {
                "source_size": list(actual_size),
                "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
    with zipfile.ZipFile(destination) as check:
        assert check.testzip() is None
        for name, info in manifest["files"].items():
            assert hashlib.sha256(check.read(name)).hexdigest() == info["sha256"]
    manifest["zip_sha256"] = hashlib.sha256(destination.read_bytes()).hexdigest()
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"PACKAGE_PASS {destination} {manifest['zip_sha256']}")


if __name__ == "__main__":
    main()
