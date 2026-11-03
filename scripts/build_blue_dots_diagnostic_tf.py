"""Build a first-question size A/B TF package for the HDMI blue-dot issue."""

from __future__ import annotations

import hashlib
import io
import json
import zipfile
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ZIP = ROOT / "artifacts/home_cover_pdf_20261028/tf_card_home_practice_scaling.zip"
SOURCE_MANIFEST = ROOT / "artifacts/home_cover_pdf_20261028/manifest.json"
SMALL_BMPS = ROOT / "artifacts/english_nature_cards_v1/bmp_only"
OUTPUT = ROOT / "artifacts/blue_dots_diagnostic_20261028"
REPLACED = {"04.bmp", "05.bmp", "06.bmp"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def main() -> None:
    source_manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    source_bytes = SOURCE_ZIP.read_bytes()
    assert sha256(source_bytes) == source_manifest["zip_sha256"]

    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / "tf_card_first_question_640_diagnostic.zip"
    files = {}
    with zipfile.ZipFile(io.BytesIO(source_bytes)) as source, zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as target:
        expected_names = [f"{number:02d}.bmp" for number in range(13)]
        assert sorted(source.namelist()) == expected_names
        for name in expected_names:
            original = source.read(name)
            assert sha256(original) == source_manifest["files"][name]["sha256"]
            data = original
            if name in REPLACED:
                data = (SMALL_BMPS / name).read_bytes()
                with Image.open(io.BytesIO(original)) as large, Image.open(
                    io.BytesIO(data)
                ) as small:
                    assert large.size == (1280, 960)
                    assert small.size == (640, 480)
                    expected = large.convert("RGB").resize(
                        (640, 480), Image.Resampling.LANCZOS
                    )
                    assert ImageChops.difference(expected, small.convert("RGB")).getbbox() is None
            entry = zipfile.ZipInfo(name, date_time=(2026, 10, 28, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(entry, data, compresslevel=6)
            files[name] = {
                "bytes": len(data),
                "sha256": sha256(data),
                "replaced": name in REPLACED,
            }

    with zipfile.ZipFile(destination) as check:
        assert check.testzip() is None
        assert sorted(check.namelist()) == expected_names
        for name, info in files.items():
            assert sha256(check.read(name)) == info["sha256"]

    manifest = {
        "purpose": "Diagnostic only: compare 1280x960 first-question input against pixel-equivalent 640x480 input with the same bitstream.",
        "source_zip_sha256": sha256(source_bytes),
        "diagnostic_zip_sha256": sha256(destination.read_bytes()),
        "first_question_replaced": sorted(REPLACED),
        "other_files_unchanged": True,
        "files": files,
        "hardware_result": "NOT_RUN",
    }
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("DIAGNOSTIC_PACKAGE_PASS", destination, manifest["diagnostic_zip_sha256"])


if __name__ == "__main__":
    main()
