#!/usr/bin/env python3
"""Generate neural lesson narration and embed it after four learning BMPs.

The FPGA-facing payload is deliberately simple: signed 8-bit mono PCM at
16 kHz.  A 16-byte ``LMV1`` trailer header follows the last padded BMP pixel
row.  Normal BMP viewers ignore this legal trailing data, while the FPGA can
stream it from TF without storing an entire speech clip in on-chip RAM.
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
from scipy.signal import resample_poly

from build_lesson_subtitle_rom import CAPTIONS, CUE_TENTHS


SAMPLE_RATE = 16_000
CODEC_PCM_S8 = 1
TRAILER_MAGIC = b"LMV1"
CHINESE_VOICE = "zh-CN-XiaoxiaoNeural"
ENGLISH_VOICE = "en-US-AvaMultilingualNeural"


@dataclass(frozen=True)
class Segment:
    text: str
    voice: str = CHINESE_VOICE
    rate: str = "-8%"
    pitch: str = "+0Hz"
    pause_after_ms: int = 450


LESSONS: dict[int, dict[str, object]] = {
    1: {
        "subject": "语文",
        "title": "《暮江吟》讲解与带读",
        "segments": [
            Segment(
                "同学们，我们来学习唐代诗人白居易的《暮江吟》。这首诗先写傍晚的江面，再写秋夜的露珠和弯月。残阳，是快要落山的太阳；瑟瑟，在这里写江水碧绿的颜色。诗人把露珠比作珍珠，把弯月比作弓，描绘出宁静又美丽的秋夜。"
            ),
            Segment(
                "现在请跟我读。暮江吟，唐，白居易。",
                rate="-12%",
                pause_after_ms=650,
            ),
            Segment("一道残阳铺水中。", rate="-18%", pause_after_ms=900),
            Segment("半江瑟瑟半江红。", rate="-18%", pause_after_ms=900),
            Segment("可怜九月初三夜。", rate="-18%", pause_after_ms=900),
            Segment("露似真珠月似弓。", rate="-18%", pause_after_ms=900),
            Segment("请你看着画面，再完整朗读一遍。", pause_after_ms=800),
        ],
    },
    2: {
        "subject": "数学",
        "title": "角的度量讲解与带读",
        "segments": [
            Segment(
                "同学们，我们来学习角的度量。量角器上有中心、零刻度线，还有内圈和外圈刻度。量角时要完成三次重合。第一，量角器的中心和角的顶点重合。第二，零刻度线和角的一条边重合。第三，看角的另一条边所对的刻度。读数时，要从零刻度线所在的一侧开始，不能把内圈和外圈看反。"
            ),
            Segment(
                "现在请跟我读量角口诀。",
                rate="-12%",
                pause_after_ms=650,
            ),
            Segment("中心对顶点。", rate="-18%", pause_after_ms=850),
            Segment("零线对一边。", rate="-18%", pause_after_ms=850),
            Segment("另一边读刻度。", rate="-18%", pause_after_ms=850),
            Segment("最后再检查，刻度是不是从零开始。", pause_after_ms=800),
        ],
    },
    3: {
        "subject": "英语",
        "title": "My classroom 讲解与带读",
        "segments": [
            Segment(
                "同学们，我们来学习人教版英语四年级上册第一单元，My classroom。先认识教室里的物品，再练习询问物品在哪里。请听英语发音，然后跟读。"
            ),
            Segment("classroom.", ENGLISH_VOICE, "-22%", pause_after_ms=900),
            Segment("window.", ENGLISH_VOICE, "-22%", pause_after_ms=900),
            Segment("blackboard.", ENGLISH_VOICE, "-22%", pause_after_ms=900),
            Segment("desk.", ENGLISH_VOICE, "-22%", pause_after_ms=900),
            Segment("chair.", ENGLISH_VOICE, "-22%", pause_after_ms=1000),
            Segment(
                "下面练习重点句型。先听问题，再听回答。",
                rate="-12%",
                pause_after_ms=600,
            ),
            Segment(
                "Where is the schoolbag?",
                ENGLISH_VOICE,
                "-24%",
                pause_after_ms=1100,
            ),
            Segment(
                "It's under the desk.",
                ENGLISH_VOICE,
                "-24%",
                pause_after_ms=1200,
            ),
            Segment("请你看着图片，再跟读一遍。", pause_after_ms=800),
        ],
    },
    4: {
        "subject": "音乐",
        "title": "《小螺号》讲解与跟唱提示",
        "segments": [
            Segment(
                "同学们，我们来学习歌曲《小螺号》。这首歌是四二拍，情绪欢快活泼。演唱时要注意短促、有弹性的节奏，也要听清旋律的高低变化。画面上的低、中、高可以调节八度；方波、三角波和正弦波可以改变音色；强弱按键可以改变力度。"
            ),
            Segment(
                "讲解结束后，系统会从头播放教学旋律。请先听一遍，再跟着节拍轻声哼唱。准备，一、二，开始。",
                rate="-12%",
                pause_after_ms=900,
            ),
        ],
    },
}


def normalized_spoken_text(text: str) -> str:
    """Keep only spoken letters/numbers so caption coverage is testable."""
    return "".join(character.upper() for character in text if character.isalnum())


def validate_subtitle_coverage() -> None:
    """Reject subtitle tables that summarize or omit any narrated phrase."""
    for page_number, lesson in LESSONS.items():
        spoken = normalized_spoken_text(
            "".join(segment.text for segment in lesson["segments"])
        )
        captioned = normalized_spoken_text(
            "".join(CAPTIONS[page_number - 1])
        )
        if captioned != spoken:
            raise ValueError(
                f"lesson {page_number} subtitles do not cover the full narration"
            )


def silence(milliseconds: int) -> np.ndarray:
    count = int(round(SAMPLE_RATE * milliseconds / 1000.0))
    return np.zeros(count, dtype=np.float32)


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
    communicate = edge_tts.Communicate(
        segment.text,
        voice=segment.voice,
        rate=segment.rate,
        pitch=segment.pitch,
    )
    await communicate.save(str(destination))


async def build_lesson_audio(segments: list[Segment], temp_dir: Path) -> np.ndarray:
    parts: list[np.ndarray] = [silence(250)]
    for index, segment in enumerate(segments):
        mp3_path = temp_dir / f"segment_{index:02d}.mp3"
        await synthesize_segment(segment, mp3_path)
        parts.append(load_resampled_mono(mp3_path))
        parts.append(silence(segment.pause_after_ms))

    joined = np.concatenate(parts + [silence(300)])
    peak = float(np.max(np.abs(joined))) if joined.size else 0.0
    if peak > 0.0:
        joined = joined * (0.88 / peak)
    return np.clip(joined, -1.0, 1.0).astype(np.float32)


def float_to_pcm_s8(audio: np.ndarray) -> bytes:
    signed = np.rint(np.clip(audio, -1.0, 1.0) * 127.0).astype(np.int8)
    return signed.tobytes()


def parse_bmp_pixel_end(data: bytes) -> int:
    if len(data) < 54 or data[0:2] != b"BM":
        raise ValueError("not a supported BMP")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    planes = struct.unpack_from("<H", data, 26)[0]
    bit_count = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if width <= 0 or height <= 0 or planes != 1 or bit_count != 24 or compression != 0:
        raise ValueError("BMP must be positive-height 24-bit BI_RGB")
    row_stride = ((width * 3) + 3) & ~3
    pixel_end = pixel_offset + row_stride * height
    if pixel_end > len(data):
        raise ValueError("BMP pixel array is truncated")
    return pixel_end


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


def embed_voice(source_bmp: Path, destination_bmp: Path, trailer: bytes | None) -> int:
    data = source_bmp.read_bytes()
    pixel_end = parse_bmp_pixel_end(data)
    output = bytearray(data[:pixel_end])
    if trailer is not None:
        output.extend(trailer)
    struct.pack_into("<I", output, 2, len(output))
    destination_bmp.parent.mkdir(parents=True, exist_ok=True)
    destination_bmp.write_bytes(output)
    return pixel_end


async def run(source_dir: Path, output_dir: Path) -> None:
    validate_subtitle_coverage()
    preview_dir = output_dir / "preview_wav"
    payload_dir = output_dir / "voice_payload"
    tf_dir = output_dir / "tf_card_ready_ai_audio"
    preview_dir.mkdir(parents=True, exist_ok=True)
    payload_dir.mkdir(parents=True, exist_ok=True)
    tf_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, object] = {
        "format": "LMV1 signed PCM",
        "sample_rate": SAMPLE_RATE,
        "codec": CODEC_PCM_S8,
        "voice_cn": CHINESE_VOICE,
        "voice_en": ENGLISH_VOICE,
        "lessons": [],
    }

    trailers: dict[int, bytes] = {}
    with tempfile.TemporaryDirectory(prefix="lesson_tts_") as temp_name:
        temp_root = Path(temp_name)
        for page_number, lesson in LESSONS.items():
            lesson_temp = temp_root / f"lesson_{page_number:02d}"
            lesson_temp.mkdir()
            audio = await build_lesson_audio(
                list(lesson["segments"]),  # type: ignore[arg-type]
                lesson_temp,
            )
            payload = float_to_pcm_s8(audio)
            trailer = make_voice_trailer(page_number - 1, payload)
            trailers[page_number] = trailer

            wav_path = preview_dir / f"{page_number:02d}_{lesson['subject']}.wav"
            payload_path = payload_dir / f"{page_number:02d}.lmv"
            sf.write(wav_path, audio, SAMPLE_RATE, subtype="PCM_16")
            payload_path.write_bytes(trailer)

            manifest["lessons"].append(  # type: ignore[union-attr]
                {
                    "page": page_number,
                    "subject": lesson["subject"],
                    "title": lesson["title"],
                    "samples": len(payload),
                    "duration_seconds": round(len(payload) / SAMPLE_RATE, 3),
                    "payload_crc32": f"{zlib.crc32(payload) & 0xFFFF_FFFF:08X}",
                    "script": [segment.text for segment in lesson["segments"]],
                    "subtitle_captions": CAPTIONS[page_number - 1],
                    "subtitle_start_tenths": CUE_TENTHS[page_number - 1],
                }
            )

    for page_number in range(1, 9):
        source_bmp = source_dir / f"{page_number:02d}.bmp"
        if not source_bmp.is_file():
            raise FileNotFoundError(source_bmp)
        destination_bmp = tf_dir / source_bmp.name
        pixel_end = embed_voice(
            source_bmp,
            destination_bmp,
            trailers.get(page_number),
        )
        if page_number <= 4:
            lesson_entry = manifest["lessons"][page_number - 1]  # type: ignore[index]
            lesson_entry["bmp_pixel_end"] = pixel_end
            lesson_entry["embedded_bmp_bytes"] = destination_bmp.stat().st_size

    shutil.copy2(Path(__file__), output_dir / "build_ai_lesson_audio.py")
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("artifacts/chinese_textbook_real_cards/tf_card_ready"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("artifacts/chinese_textbook_ai_audio"),
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="check that subtitles cover every narrated word without TTS/network access",
    )
    args = parser.parse_args()
    if args.validate_only:
        validate_subtitle_coverage()
        print("VALIDATION_PASS full narration is captioned")
        return
    asyncio.run(run(args.source_dir, args.output_dir))


if __name__ == "__main__":
    main()
