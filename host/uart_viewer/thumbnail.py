"""Reassemble and convert RGB565 thumbnail packets."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
import zlib

from protocol import (
    Packet,
    ProtocolError,
    TYPE_IMAGE_BEGIN,
    TYPE_IMAGE_DATA,
    TYPE_IMAGE_END,
)


PIXEL_FORMAT_RGB565_LE = 1
BEGIN = struct.Struct("<HHHHI")
DATA_HEADER = struct.Struct("<HH")
END = struct.Struct("<HII")


@dataclass(frozen=True)
class ThumbnailFrame:
    width: int
    height: int
    pixel_format: int
    frame_id: int
    rgb565: bytes
    dropped_requests: int


class ThumbnailAssembler:
    """Consumes image packets and emits a frame only after end-to-end CRC."""

    def __init__(self) -> None:
        self._metadata: tuple[int, int, int, int, int] | None = None
        self._data = bytearray()
        self._next_chunk = 0

    def reset(self) -> None:
        self._metadata = None
        self._data.clear()
        self._next_chunk = 0

    def feed(self, packet: Packet) -> ThumbnailFrame | None:
        if packet.msg_type == TYPE_IMAGE_BEGIN:
            if len(packet.payload) != BEGIN.size:
                raise ProtocolError("IMAGE_BEGIN payload length mismatch")
            width, height, pixel_format, frame_id, total_length = BEGIN.unpack(packet.payload)
            if pixel_format != PIXEL_FORMAT_RGB565_LE:
                raise ProtocolError("unsupported thumbnail pixel format")
            if total_length != width * height * 2:
                raise ProtocolError("thumbnail dimensions do not match byte length")
            self._metadata = (width, height, pixel_format, frame_id, total_length)
            self._data.clear()
            self._next_chunk = 0
            return None

        if packet.msg_type == TYPE_IMAGE_DATA:
            if self._metadata is None:
                raise ProtocolError("IMAGE_DATA arrived before IMAGE_BEGIN")
            if len(packet.payload) < DATA_HEADER.size:
                raise ProtocolError("IMAGE_DATA payload is truncated")
            frame_id, chunk = DATA_HEADER.unpack_from(packet.payload)
            if frame_id != self._metadata[3] or chunk != self._next_chunk:
                self.reset()
                raise ProtocolError("thumbnail frame or chunk sequence mismatch")
            self._data.extend(packet.payload[DATA_HEADER.size:])
            if len(self._data) > self._metadata[4]:
                self.reset()
                raise ProtocolError("thumbnail data exceeds declared length")
            self._next_chunk += 1
            return None

        if packet.msg_type == TYPE_IMAGE_END:
            if self._metadata is None:
                raise ProtocolError("IMAGE_END arrived before IMAGE_BEGIN")
            if len(packet.payload) != END.size:
                raise ProtocolError("IMAGE_END payload length mismatch")
            frame_id, expected_crc, dropped_requests = END.unpack(packet.payload)
            width, height, pixel_format, active_frame_id, total_length = self._metadata
            data = bytes(self._data)
            self.reset()
            if frame_id != active_frame_id:
                raise ProtocolError("IMAGE_END frame id mismatch")
            if len(data) != total_length:
                raise ProtocolError("thumbnail data is incomplete")
            if zlib.crc32(data) != expected_crc:
                raise ProtocolError("thumbnail CRC32 mismatch")
            return ThumbnailFrame(
                width=width,
                height=height,
                pixel_format=pixel_format,
                frame_id=frame_id,
                rgb565=data,
                dropped_requests=dropped_requests,
            )

        return None


def rgb565_to_ppm(frame: ThumbnailFrame) -> bytes:
    if frame.pixel_format != PIXEL_FORMAT_RGB565_LE:
        raise ProtocolError("unsupported thumbnail pixel format")
    expected_length = frame.width * frame.height * 2
    if len(frame.rgb565) != expected_length:
        raise ProtocolError("RGB565 frame length mismatch")

    rgb888 = bytearray(frame.width * frame.height * 3)
    destination = 0
    for source in range(0, len(frame.rgb565), 2):
        pixel = frame.rgb565[source] | frame.rgb565[source + 1] << 8
        red = (pixel >> 11) & 0x1F
        green = (pixel >> 5) & 0x3F
        blue = pixel & 0x1F
        rgb888[destination] = (red << 3) | (red >> 2)
        rgb888[destination + 1] = (green << 2) | (green >> 4)
        rgb888[destination + 2] = (blue << 3) | (blue >> 2)
        destination += 3
    return f"P6\n{frame.width} {frame.height}\n255\n".encode("ascii") + rgb888


def save_ppm(frame: ThumbnailFrame, path: str | Path) -> None:
    Path(path).write_bytes(rgb565_to_ppm(frame))
