#!/usr/bin/env python3
"""Build aligned, pitch-preserving LMV2 narration tracks from local WAVs.

Each 64 ms source block stores the 0.75x, 1x and 1.25x output in that
order. The FPGA selects one complete track per block without seeking or
restarting the lesson. All lengths and the body CRC are checked here.
"""

from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path

import numpy as np
import soundfile as sf
from audiotsm import wsola as make_wsola
from audiotsm.io.array import ArrayReader, ArrayWriter

RATE = 16000
BLOCK = 1024
SPEEDS = (0.75, 1.0, 1.25)
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/english_nature_cards_v1"
DEST = ROOT / "artifacts/english_nature_pitch_preserving_audio_v2"


def parse_bmp_pixel_end(data: bytes) -> int:
    if len(data) < 54 or data[:2] != b"BM":
        raise ValueError("not a BMP")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    planes, depth = struct.unpack_from("<HH", data, 26)
    compression = struct.unpack_from("<I", data, 30)[0]
    if (width, height, planes, depth, compression) != (640, 480, 1, 24, 0):
        raise ValueError("expected 640x480 RGB24 bottom-up BMP")
    pixel_end = pixel_offset + ((width * 3 + 3) & ~3) * height
    if pixel_end > len(data):
        raise ValueError("truncated BMP pixels")
    return pixel_end


def wsola(source: np.ndarray, speed: float) -> np.ndarray:
    """Stretch a complete clip with the tested AudioTSM WSOLA engine."""
    if speed == 1.0:
        return source.copy()
    target = round(len(source) / speed)
    reader = ArrayReader(np.pad(source.astype(np.float32),
                                (0, 2048))[None, :])
    writer = ArrayWriter(1)
    make_wsola(1, speed, frame_length=640, synthesis_hop=160,
               tolerance=160).run(reader, writer)
    aligned = writer.data[0][256:256 + target]
    if len(aligned) < target:
        aligned = np.pad(aligned, (0, target - len(aligned)))
    return np.clip(aligned, -1.0, 1.0)


def pcm8(samples: np.ndarray) -> bytes:
    return np.rint(np.clip(samples, -1, 1) * 127).astype(np.int8).tobytes()


def build_one(page: int, wav: Path, bmp: Path, destination: Path) -> dict:
    source, sample_rate = sf.read(wav, dtype="float32", always_2d=True)
    if sample_rate != RATE:
        raise ValueError(f"{wav}: expected {RATE} Hz")
    mono = source.mean(axis=1)
    if not 0 < len(mono) <= 4_000_000:
        raise ValueError(f"{wav}: unsupported length")
    tracks = [wsola(mono, speed) for speed in SPEEDS]
    body = bytearray()
    counts = [0, 0, 0]
    preview_payloads = [bytearray() for _ in SPEEDS]
    for first in range(0, len(mono), BLOCK):
        last = min(first + BLOCK, len(mono))
        pieces = []
        for track, speed in zip(tracks, SPEEDS):
            piece = track[round(first / speed):round(last / speed)].copy()
            if speed != 1.0:
                anchor = min(32, len(piece) // 3, last - first)
                ramp = (0.5 + 0.5 * np.cos(
                    np.linspace(0.0, np.pi, anchor, dtype=np.float32)))
                piece[:anchor] = (piece[:anchor] * (1.0 - ramp) +
                                  mono[first:first + anchor] * ramp)
                piece[-anchor:] = (piece[-anchor:] * (1.0 - ramp[::-1]) +
                                   mono[last - anchor:last] * ramp[::-1])
            pieces.append(pcm8(piece))
        lengths = [len(piece) for piece in pieces]
        if any(not 0 < length <= 1366 for length in lengths):
            raise ValueError(f"{wav}: invalid block lengths {lengths}")
        body.extend(struct.pack("<4H", last - first, *lengths))
        for index, piece in enumerate(pieces):
            body.extend(piece)
            counts[index] += len(piece)
            preview_payloads[index].extend(piece)
    crc = zlib.crc32(body) & 0xffffffff
    trailer = struct.pack("<4sBBHII", b"LMV2", page - 1, 2,
                          RATE, len(mono), crc) + body
    original = bmp.read_bytes()
    pixel_end = parse_bmp_pixel_end(original)
    packed = bytearray(original[:pixel_end] + trailer)
    struct.pack_into("<I", packed, 2, len(packed))
    destination.write_bytes(packed)
    verify_one(destination, page)
    preview_dir = destination.parent.parent / "preview_wav"
    preview_dir.mkdir(parents=True, exist_ok=True)
    for speed, payload in zip(SPEEDS, preview_payloads):
        samples = np.frombuffer(payload, dtype=np.int8).astype(np.float32) / 128.0
        sf.write(preview_dir / f"{page:02d}_{speed:.2f}x.wav",
                 samples, RATE, subtype="PCM_16")
    return {"page": page, "source_samples": len(mono),
            "track_samples": counts, "crc32": f"{crc:08X}",
            "bmp_sha256": __import__("hashlib").sha256(packed).hexdigest()}


def verify_one(path: Path, page: int) -> None:
    data = path.read_bytes()
    offset = parse_bmp_pixel_end(data)
    magic, index, codec, rate, total, crc = struct.unpack_from("<4sBBHII", data, offset)
    if (magic, index, codec, rate) != (b"LMV2", page - 1, 2, RATE):
        raise ValueError(f"{path}: invalid LMV2 header")
    body = data[offset + 16:]
    if zlib.crc32(body) & 0xffffffff != crc:
        raise ValueError(f"{path}: body CRC mismatch")
    cursor = 0
    source_count = 0
    while cursor < len(body):
        if cursor + 8 > len(body):
            raise ValueError(f"{path}: truncated block header")
        span, slow, normal, fast = struct.unpack_from("<4H", body, cursor)
        cursor += 8
        if not 0 < span <= BLOCK or not all(0 < n <= 1366 for n in (slow, normal, fast)):
            raise ValueError(f"{path}: invalid block lengths")
        pieces = []
        for length in (slow, normal, fast):
            pieces.append(body[cursor:cursor + length])
            cursor += length
        if any(piece[0] != pieces[1][0] or piece[-1] != pieces[1][-1]
               for piece in pieces):
            raise ValueError(f"{path}: unaligned track boundary")
        source_count += span
        if cursor > len(body):
            raise ValueError(f"{path}: truncated track")
    if source_count != total or cursor != len(body):
        raise ValueError(f"{path}: source timeline mismatch")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=DEST)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    folder = args.output / "tf_card_ready_pitch_preserving"
    if args.verify_only:
        for page in range(1, 4):
            verify_one(folder / f"{page:02d}.bmp", page)
        for page in range(4, 13):
            original = args.source / "tf_card_ready_with_audio" / f"{page:02d}.bmp"
            if (folder / original.name).read_bytes() != original.read_bytes():
                raise ValueError(f"{original.name}: exercise card changed")
        print("VALIDATION_PASS LMV2 three lessons and nine exercise cards")
        return
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    for page in range(1, 4):
        matches = list((args.source / "preview_wav").glob(f"{page:02d}_*.wav"))
        if len(matches) != 1:
            raise ValueError(f"lesson {page}: expected one local WAV")
        records.append(build_one(page, matches[0],
                                 args.source / "tf_card_ready_with_audio" / f"{page:02d}.bmp",
                                 folder / f"{page:02d}.bmp"))
    for page in range(4, 13):
        source = args.source / "tf_card_ready_with_audio" / f"{page:02d}.bmp"
        (folder / source.name).write_bytes(source.read_bytes())
    (args.output / "manifest.json").write_text(
        json.dumps({"format": "LMV2", "generator": "audiotsm-wsola-0.1.2",
                    "source_hz": RATE,
                    "block_source_samples": BLOCK, "speed": SPEEDS,
                    "lessons": records}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    print("VALIDATION_PASS LMV2 three lessons and nine exercise cards")


if __name__ == "__main__":
    main()
