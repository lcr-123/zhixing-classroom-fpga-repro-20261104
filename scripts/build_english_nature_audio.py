#!/usr/bin/env python3
"""Build the English nature lesson audio and a TF-ready asset package.

The first three 640x480 BMP files receive an ``LMV1`` trailer containing
signed 8-bit mono PCM at 16 kHz. Exercise cards remain plain BMP files.
The current FPGA image still expects the old eight-card mapping, so this
script prepares assets only; it does not claim RTL or hardware integration.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import shutil
import struct
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path

import edge_tts
import numpy as np
import soundfile as sf
from PIL import Image
from scipy.signal import resample_poly

from build_lesson_subtitle_rom import CAPTIONS, CUE_TENTHS


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ASSET_ROOT = ROOT / "artifacts" / "english_nature_cards_v1"

SAMPLE_RATE = 16_000
CODEC_PCM_S8 = 1
TRAILER_MAGIC = b"LMV1"
CHINESE_VOICE = "zh-CN-XiaoxiaoNeural"
ENGLISH_VOICE = "en-US-AvaMultilingualNeural"
MAX_TOTAL_SECONDS = 90.0


@dataclass(frozen=True)
class Segment:
    text: str
    voice: str = CHINESE_VOICE
    rate: str = "-6%"
    pitch: str = "+0Hz"
    pause_after_ms: int = 350


LESSONS: dict[int, dict[str, object]] = {
    1: {
        "title": "Nature Words",
        "segments": [
            Segment("第一部分，认识自然景物。请听五个英语单词。", pause_after_ms=350),
            Segment("forest", ENGLISH_VOICE, "-18%", pause_after_ms=500),
            Segment("river", ENGLISH_VOICE, "-18%", pause_after_ms=500),
            Segment("lake", ENGLISH_VOICE, "-18%", pause_after_ms=500),
            Segment("mountain", ENGLISH_VOICE, "-18%", pause_after_ms=500),
            Segment("hill", ENGLISH_VOICE, "-18%", pause_after_ms=650),
            Segment(
                "Forest是森林，river是河流，lake是湖泊，mountain是高山，hill是小山。观察右侧照片，找一找这些景物。",
                pause_after_ms=500,
            ),
        ],
    },
    2: {
        "title": "Describe the Park",
        "segments": [
            Segment(
                "第二部分，用There is和There are描述景物。There is接单数，There are接复数。",
                pause_after_ms=450,
            ),
            Segment(
                "There is a river in the forest.",
                ENGLISH_VOICE,
                "-16%",
                pause_after_ms=650,
            ),
            Segment("这句话表示，森林里有一条河。", pause_after_ms=350),
            Segment(
                "There are some trees near the lake.",
                ENGLISH_VOICE,
                "-16%",
                pause_after_ms=650,
            ),
            Segment(
                "这句话表示，湖边有一些树。注意，一个景物用is，多个景物用are。",
                pause_after_ms=500,
            ),
        ],
    },
    3: {
        "title": "Ask About Nature",
        "segments": [
            Segment(
                "第三部分，用Is there和Are there询问自然景物。先听两个问答。",
                pause_after_ms=450,
            ),
            Segment(
                "Is there a bridge over the river?",
                ENGLISH_VOICE,
                "-18%",
                pause_after_ms=500,
            ),
            Segment("Yes, there is.", ENGLISH_VOICE, "-18%", pause_after_ms=700),
            Segment(
                "Are there any houses near the river?",
                ENGLISH_VOICE,
                "-18%",
                pause_after_ms=500,
            ),
            Segment("Yes, there are.", ENGLISH_VOICE, "-18%", pause_after_ms=700),
            Segment(
                "Is there询问单个景物，Are there询问多个景物。听完后进入选择练习。",
                pause_after_ms=500,
            ),
        ],
    },
}


def normalized_spoken_text(text: str) -> str:
    """Keep only spoken letters and numbers for exact caption comparison."""
    return "".join(character.upper() for character in text if character.isalnum())


def validate_subtitle_coverage() -> None:
    """Reject subtitle tables that summarize, add, or omit narrated words."""
    for page_number, lesson in LESSONS.items():
        spoken = normalized_spoken_text(
            "".join(segment.text for segment in lesson["segments"])
        )
        captioned = normalized_spoken_text("".join(CAPTIONS[page_number - 1]))
        if captioned != spoken:
            raise ValueError(
                f"lesson {page_number} subtitles do not cover the full narration"
            )
        if len(CAPTIONS[page_number - 1]) != len(CUE_TENTHS[page_number - 1]):
            raise ValueError(
                f"lesson {page_number} subtitle caption/timing count mismatch"
            )


def silence(milliseconds: int) -> np.ndarray:
    sample_count = int(round(SAMPLE_RATE * milliseconds / 1000.0))
    return np.zeros(sample_count, dtype=np.float32)


def load_resampled_mono(path: Path) -> np.ndarray:
    data, source_rate = sf.read(path, dtype="float32", always_2d=True)
    mono = np.mean(data, axis=1)
    if source_rate != SAMPLE_RATE:
        divisor = int(np.gcd(source_rate, SAMPLE_RATE))
        mono = resample_poly(
            mono,
            SAMPLE_RATE // divisor,
            source_rate // divisor,
        ).astype(np.float32)
    return mono


async def synthesize_segment(segment: Segment, destination: Path) -> None:
    communication = edge_tts.Communicate(
        segment.text,
        voice=segment.voice,
        rate=segment.rate,
        pitch=segment.pitch,
    )
    await communication.save(str(destination))


async def build_lesson_audio(segments: list[Segment], temp_dir: Path) -> np.ndarray:
    parts: list[np.ndarray] = [silence(200)]
    for index, segment in enumerate(segments):
        mp3_path = temp_dir / f"segment_{index:02d}.mp3"
        await synthesize_segment(segment, mp3_path)
        parts.append(load_resampled_mono(mp3_path))
        parts.append(silence(segment.pause_after_ms))
    joined = np.concatenate(parts + [silence(250)])
    peak = float(np.max(np.abs(joined))) if joined.size else 0.0
    if peak > 0.0:
        joined = joined * (0.88 / peak)
    return np.clip(joined, -1.0, 1.0).astype(np.float32)


def float_to_pcm_s8(audio: np.ndarray) -> bytes:
    signed = np.rint(np.clip(audio, -1.0, 1.0) * 127.0).astype(np.int8)
    return signed.tobytes()


def parse_bmp(data: bytes) -> dict[str, int]:
    if len(data) < 54 or data[:2] != b"BM":
        raise ValueError("not a BMP file")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    planes = struct.unpack_from("<H", data, 26)[0]
    bit_count = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if (width, height) != (640, 480):
        raise ValueError(f"BMP must be 640x480, got {width}x{height}")
    if height <= 0 or planes != 1 or bit_count != 24 or compression != 0:
        raise ValueError("BMP must be positive-height 24-bit BI_RGB")
    row_stride = ((width * 3) + 3) & ~3
    pixel_end = pixel_offset + row_stride * height
    if pixel_end > len(data):
        raise ValueError("BMP pixel array is truncated")
    return {
        "width": width,
        "height": height,
        "bit_count": bit_count,
        "compression": compression,
        "pixel_offset": pixel_offset,
        "pixel_end": pixel_end,
    }


def make_voice_trailer(page_index: int, payload: bytes) -> bytes:
    crc32 = zlib.crc32(payload) & 0xFFFF_FFFF
    return struct.pack(
        "<4sBBHII",
        TRAILER_MAGIC,
        page_index,
        CODEC_PCM_S8,
        SAMPLE_RATE,
        len(payload),
        crc32,
    ) + payload


def embed_voice(source_bmp: Path, destination_bmp: Path, trailer: bytes | None) -> dict[str, int]:
    data = source_bmp.read_bytes()
    info = parse_bmp(data)
    output = bytearray(data[: info["pixel_end"]])
    if trailer is not None:
        output.extend(trailer)
    struct.pack_into("<I", output, 2, len(output))
    destination_bmp.parent.mkdir(parents=True, exist_ok=True)
    destination_bmp.write_bytes(output)
    return info


def build_plain_bmps(preview_dir: Path, bmp_dir: Path, card_count: int) -> None:
    bmp_dir.mkdir(parents=True, exist_ok=True)
    for page_number in range(1, card_count + 1):
        source_png = preview_dir / f"{page_number:02d}.png"
        if not source_png.is_file():
            raise FileNotFoundError(source_png)
        image = Image.open(source_png).convert("RGB")
        if image.size != (640, 480):
            raise ValueError(f"preview must be 640x480: {source_png}")
        destination = bmp_dir / f"{page_number:02d}.bmp"
        image.save(destination, format="BMP")
        parse_bmp(destination.read_bytes())


async def run(asset_root: Path, card_count: int) -> None:
    validate_subtitle_coverage()
    preview_png_dir = asset_root / "preview"
    bmp_only_dir = asset_root / "bmp_only"
    preview_wav_dir = asset_root / "preview_wav"
    payload_dir = asset_root / "voice_payload"
    tf_dir = asset_root / "tf_card_ready_with_audio"
    for directory in (preview_wav_dir, payload_dir, tf_dir):
        directory.mkdir(parents=True, exist_ok=True)

    build_plain_bmps(preview_png_dir, bmp_only_dir, card_count)

    manifest: dict[str, object] = {
        "format": "LMV1 signed PCM",
        "sample_rate": SAMPLE_RATE,
        "codec": CODEC_PCM_S8,
        "voice_cn": CHINESE_VOICE,
        "voice_en": ENGLISH_VOICE,
        "card_count": card_count,
        "learning_pages": 3,
        "exercise_pool_pages": card_count - 3,
        "waveform_display": True,
        "lessons": [],
    }

    trailers: dict[int, bytes] = {}
    total_seconds = 0.0
    with tempfile.TemporaryDirectory(prefix="english_nature_tts_") as temp_name:
        temp_root = Path(temp_name)
        for page_number, lesson in LESSONS.items():
            lesson_temp = temp_root / f"lesson_{page_number:02d}"
            lesson_temp.mkdir()
            audio = await build_lesson_audio(list(lesson["segments"]), lesson_temp)  # type: ignore[arg-type]
            payload = float_to_pcm_s8(audio)
            duration = len(payload) / SAMPLE_RATE
            if duration <= 5.0:
                raise ValueError(f"lesson {page_number} audio is unexpectedly short")
            total_seconds += duration

            trailer = make_voice_trailer(page_number - 1, payload)
            trailers[page_number] = trailer
            wav_path = preview_wav_dir / f"{page_number:02d}_{lesson['title']}.wav"
            payload_path = payload_dir / f"{page_number:02d}.lmv"
            sf.write(wav_path, audio, SAMPLE_RATE, subtype="PCM_16")
            payload_path.write_bytes(trailer)
            manifest["lessons"].append(  # type: ignore[union-attr]
                {
                    "page": page_number,
                    "title": lesson["title"],
                    "samples": len(payload),
                    "duration_seconds": round(duration, 3),
                    "payload_crc32": f"{zlib.crc32(payload) & 0xFFFF_FFFF:08X}",
                    "script": [segment.text for segment in lesson["segments"]],
                    "subtitle_captions": CAPTIONS[page_number - 1],
                    "subtitle_start_tenths": CUE_TENTHS[page_number - 1],
                }
            )

    if total_seconds > MAX_TOTAL_SECONDS:
        raise ValueError(
            f"total learning audio {total_seconds:.3f}s exceeds {MAX_TOTAL_SECONDS:.1f}s"
        )
    manifest["total_learning_seconds"] = round(total_seconds, 3)
    manifest["within_90_seconds"] = True

    for page_number in range(1, card_count + 1):
        source_bmp = bmp_only_dir / f"{page_number:02d}.bmp"
        destination_bmp = tf_dir / source_bmp.name
        info = embed_voice(source_bmp, destination_bmp, trailers.get(page_number))
        if page_number <= 3:
            lesson_entry = manifest["lessons"][page_number - 1]  # type: ignore[index]
            lesson_entry["bmp_pixel_end"] = info["pixel_end"]
            lesson_entry["embedded_bmp_bytes"] = destination_bmp.stat().st_size

    shutil.copy2(Path(__file__), asset_root / "build_english_nature_audio.py")
    (asset_root / "audio_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("BUILD_PASS english_nature_audio")
    print(f"cards={card_count} lessons=3 total_seconds={total_seconds:.3f}")
    print("format=640x480 24-bit positive-height BI_RGB; waveform_display=true")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--card-count", type=int, default=12)
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate narration/subtitle coverage without calling TTS",
    )
    args = parser.parse_args()
    if args.validate_only:
        validate_subtitle_coverage()
        print("VALIDATION_PASS english_nature_subtitle_coverage")
        return
    asyncio.run(run(args.asset_root, args.card_count))


if __name__ == "__main__":
    main()
