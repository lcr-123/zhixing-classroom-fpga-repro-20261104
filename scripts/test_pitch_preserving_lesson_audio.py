"""Numerical and package checks for the LMV2 offline WSOLA material."""

import json
import struct
import unittest
import numpy as np
import soundfile as sf

from build_pitch_preserving_lesson_audio import (
    DEST, RATE, SPEEDS, parse_bmp_pixel_end, verify_one, wsola,
)


class PitchPreservingAudioTest(unittest.TestCase):
    def test_tone_keeps_frequency_and_changes_duration(self):
        time = np.arange(2 * RATE, dtype=np.float32) / RATE
        source = 0.7 * np.sin(2 * np.pi * 440 * time)
        for speed in SPEEDS:
            result = wsola(source, speed)
            self.assertEqual(len(result), round(len(source) / speed))
            segment = result[len(result) // 3:len(result) // 3 + RATE // 2]
            spectrum = np.abs(np.fft.rfft(segment * np.hanning(len(segment))))
            peak = np.fft.rfftfreq(len(segment), 1 / RATE)[np.argmax(spectrum)]
            self.assertLess(abs(peak - 440), 6, speed)

    def test_all_embedded_lessons(self):
        folder = DEST / "tf_card_ready_pitch_preserving"
        manifest = json.loads((DEST / "manifest.json").read_text(encoding="utf-8"))
        for page in range(1, 4):
            path = folder / f"{page:02d}.bmp"
            verify_one(path, page)
            data = path.read_bytes()
            self.assertEqual(struct.unpack_from("<I", data, 2)[0], len(data))
            self.assertEqual(data[parse_bmp_pixel_end(data):][:4], b"LMV2")
            lesson = manifest["lessons"][page - 1]
            for speed, samples in zip(SPEEDS, lesson["track_samples"]):
                self.assertLess(abs(samples * speed - lesson["source_samples"]), 2)
                preview = DEST / "preview_wav" / f"{page:02d}_{speed:.2f}x.wav"
                info = sf.info(preview)
                self.assertEqual((info.frames, info.samplerate), (samples, RATE))


if __name__ == "__main__":
    unittest.main()
