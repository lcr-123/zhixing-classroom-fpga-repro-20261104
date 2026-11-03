#!/usr/bin/env python3
"""Validate the generated English nature image/audio asset package."""

from __future__ import annotations

import json
import struct
import zlib
from collections import Counter
from pathlib import Path

import soundfile as sf


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "artifacts" / "english_nature_cards_v1"
CARD_COUNT = 12
LEARNING_COUNT = 3
EXPECTED_PIXEL_END = 921_654


def parse_bmp(path: Path) -> tuple[bytes, int]:
    data = path.read_bytes()
    if len(data) < 54 or data[:2] != b"BM":
        raise AssertionError(f"not BMP: {path}")
    declared_size = struct.unpack_from("<I", data, 2)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    planes, bit_count = struct.unpack_from("<HH", data, 26)
    compression = struct.unpack_from("<I", data, 30)[0]
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    row_stride = ((width * 3) + 3) & ~3
    pixel_end = pixel_offset + row_stride * height
    assert declared_size == len(data), (path, declared_size, len(data))
    assert (width, height) == (640, 480), (path, width, height)
    assert planes == 1 and bit_count == 24 and compression == 0, path
    assert height > 0 and pixel_end == EXPECTED_PIXEL_END, (path, pixel_end)
    return data, pixel_end


def validate_audio_bmp(path: Path, expected_page_index: int) -> int:
    data, pixel_end = parse_bmp(path)
    assert len(data) >= pixel_end + 16, path
    magic, page_index, codec, sample_rate, payload_length, crc32 = struct.unpack_from(
        "<4sBBHII", data, pixel_end
    )
    payload = data[pixel_end + 16 :]
    assert magic == b"LMV1", path
    assert page_index == expected_page_index, (path, page_index)
    assert codec == 1 and sample_rate == 16_000, path
    assert payload_length == len(payload), (path, payload_length, len(payload))
    assert zlib.crc32(payload) & 0xFFFF_FFFF == crc32, path
    return payload_length


def main() -> None:
    tf_dir = ASSET_ROOT / "tf_card_ready_with_audio"
    bmp_only_dir = ASSET_ROOT / "bmp_only"
    wav_dir = ASSET_ROOT / "preview_wav"

    tf_files = sorted(tf_dir.glob("[0-9][0-9].bmp"))
    plain_files = sorted(bmp_only_dir.glob("[0-9][0-9].bmp"))
    wav_files = sorted(wav_dir.glob("*.wav"))
    assert len(tf_files) == CARD_COUNT, len(tf_files)
    assert len(plain_files) == CARD_COUNT, len(plain_files)
    assert len(wav_files) == LEARNING_COUNT, len(wav_files)

    payload_lengths = []
    for page_number, path in enumerate(tf_files, start=1):
        if page_number <= LEARNING_COUNT:
            payload_lengths.append(validate_audio_bmp(path, page_number - 1))
        else:
            data, pixel_end = parse_bmp(path)
            assert len(data) == pixel_end, path

    for path in plain_files:
        data, pixel_end = parse_bmp(path)
        assert len(data) == pixel_end, path

    total_wav_seconds = 0.0
    for path in wav_files:
        info = sf.info(path)
        assert info.samplerate == 16_000 and info.channels == 1, path
        assert info.subtype == "PCM_16", (path, info.subtype)
        total_wav_seconds += info.frames / info.samplerate

    audio_manifest = json.loads((ASSET_ROOT / "audio_manifest.json").read_text(encoding="utf-8"))
    assert audio_manifest["waveform_display"] is True
    assert audio_manifest["within_90_seconds"] is True
    assert abs(audio_manifest["total_learning_seconds"] - total_wav_seconds) < 0.01
    assert total_wav_seconds <= 90.0

    card_manifest = json.loads((ASSET_ROOT / "cards_and_sources.json").read_text(encoding="utf-8"))
    cards = card_manifest["cards"]
    exercises = [card for card in cards if card["kind"] == "练习"]
    assert len(cards) == CARD_COUNT and len(exercises) == 9
    groups = Counter(card["pool_group"] for card in exercises)
    answers = Counter(card["answer"] for card in exercises)
    assert groups == Counter({"vocabulary": 3, "sentence": 3, "question": 3})
    assert set(answers) == set("ABCD")

    print("VALIDATION_PASS english_nature_package")
    print(
        f"cards={CARD_COUNT} learning={LEARNING_COUNT} exercises=9 "
        f"groups={dict(groups)} answers={dict(sorted(answers.items()))}"
    )
    print(
        f"audio_total_seconds={total_wav_seconds:.3f} "
        f"payload_bytes={payload_lengths} waveform_display=true"
    )


if __name__ == "__main__":
    main()
