"""Binary protocol shared by the FPGA debug UART and host tools."""

from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Iterable


SYNC = b"\xA5\x5A"
VERSION = 1
HEADER = struct.Struct("<BBBHH")
CRC = struct.Struct("<H")
MAX_PAYLOAD = 256

TYPE_HELLO = 0x01
TYPE_STATUS = 0x02
TYPE_IMAGE_BEGIN = 0x10
TYPE_IMAGE_DATA = 0x11
TYPE_IMAGE_END = 0x12
TYPE_PING = 0x80
TYPE_GET_STATUS = 0x81
TYPE_SET_BRIGHTNESS = 0x84
TYPE_SET_CONTRAST = 0x85
TYPE_SET_OSD = 0x86
TYPE_GET_THUMBNAIL = 0x87
FLAG_ACK = 0x01


class ProtocolError(ValueError):
    """Raised when a complete packet is structurally invalid."""


@dataclass(frozen=True)
class Packet:
    msg_type: int
    sequence: int
    payload: bytes = b""
    flags: int = 0
    version: int = VERSION


@dataclass(frozen=True)
class Status:
    state_code: int
    display_valid: bool
    sdram_init_done: bool
    sdram_refresh_active: bool
    sdram_busy: bool
    audio_pll_lock: bool
    audio_valid: bool
    axis_ready: bool
    write_buffer: int
    display_buffer: int
    app_state: int | None = None
    app_target_image: int | None = None
    diagnostic_counts: tuple[int, ...] = ()


def crc16_ccitt_false(data: bytes, initial: int = 0xFFFF) -> int:
    crc = initial
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def encode_packet(packet: Packet) -> bytes:
    payload = bytes(packet.payload)
    if len(payload) > MAX_PAYLOAD:
        raise ProtocolError(f"payload exceeds {MAX_PAYLOAD} bytes")
    if not 0 <= packet.msg_type <= 0xFF:
        raise ProtocolError("message type must fit in one byte")
    if not 0 <= packet.flags <= 0xFF:
        raise ProtocolError("flags must fit in one byte")
    if not 0 <= packet.sequence <= 0xFFFF:
        raise ProtocolError("sequence must fit in two bytes")
    if not 0 <= packet.version <= 0xFF:
        raise ProtocolError("version must fit in one byte")

    body = HEADER.pack(
        packet.version,
        packet.msg_type,
        packet.flags,
        packet.sequence,
        len(payload),
    ) + payload
    return SYNC + body + CRC.pack(crc16_ccitt_false(body))


def decode_packet(frame: bytes) -> Packet:
    minimum_length = len(SYNC) + HEADER.size + CRC.size
    if len(frame) < minimum_length:
        raise ProtocolError("truncated packet")
    if frame[:2] != SYNC:
        raise ProtocolError("sync mismatch")

    version, msg_type, flags, sequence, length = HEADER.unpack_from(frame, len(SYNC))
    expected_length = minimum_length + length
    if length > MAX_PAYLOAD:
        raise ProtocolError(f"payload exceeds {MAX_PAYLOAD} bytes")
    if len(frame) != expected_length:
        raise ProtocolError("packet length mismatch")

    body_end = len(SYNC) + HEADER.size + length
    expected_crc = CRC.unpack_from(frame, body_end)[0]
    actual_crc = crc16_ccitt_false(frame[len(SYNC):body_end])
    if actual_crc != expected_crc:
        raise ProtocolError("CRC mismatch")

    return Packet(
        msg_type=msg_type,
        sequence=sequence,
        payload=frame[len(SYNC) + HEADER.size:body_end],
        flags=flags,
        version=version,
    )


class PacketDecoder:
    """Incrementally decodes packets and resynchronizes after malformed input."""

    def __init__(self, max_payload: int = MAX_PAYLOAD) -> None:
        self.max_payload = max_payload
        self._buffer = bytearray()
        self.discarded_bytes = 0
        self.crc_errors = 0

    def feed(self, data: bytes | bytearray | memoryview) -> list[Packet]:
        self._buffer.extend(data)
        packets: list[Packet] = []
        minimum_length = len(SYNC) + HEADER.size + CRC.size

        while True:
            sync_index = self._buffer.find(SYNC)
            if sync_index < 0:
                keep = 1 if self._buffer.endswith(SYNC[:1]) else 0
                discard = len(self._buffer) - keep
                self.discarded_bytes += discard
                if discard:
                    del self._buffer[:discard]
                break
            if sync_index:
                self.discarded_bytes += sync_index
                del self._buffer[:sync_index]
            if len(self._buffer) < minimum_length:
                break

            _, _, _, _, length = HEADER.unpack_from(self._buffer, len(SYNC))
            if length > self.max_payload:
                self.discarded_bytes += 1
                del self._buffer[0]
                continue

            frame_length = minimum_length + length
            if len(self._buffer) < frame_length:
                break

            frame = bytes(self._buffer[:frame_length])
            try:
                packets.append(decode_packet(frame))
                del self._buffer[:frame_length]
            except ProtocolError as exc:
                if str(exc) == "CRC mismatch":
                    self.crc_errors += 1
                self.discarded_bytes += 1
                del self._buffer[0]

        return packets


def make_ping(sequence: int) -> bytes:
    return encode_packet(Packet(msg_type=TYPE_PING, sequence=sequence))


def make_get_status(sequence: int) -> bytes:
    return encode_packet(Packet(msg_type=TYPE_GET_STATUS, sequence=sequence))


def make_set_brightness(sequence: int, level: int) -> bytes:
    if level not in range(-2, 3):
        raise ValueError("brightness level must be between -2 and 2")
    return encode_packet(
        Packet(TYPE_SET_BRIGHTNESS, sequence, struct.pack("<b", level))
    )


def make_set_contrast(sequence: int, level: int) -> bytes:
    if level not in range(4):
        raise ValueError("contrast level must be between 0 and 3")
    return encode_packet(Packet(TYPE_SET_CONTRAST, sequence, bytes((level,))))


def make_set_osd(
    sequence: int, enabled: bool, subtitle_enabled: bool
) -> bytes:
    flags = int(bool(enabled)) | (int(bool(subtitle_enabled)) << 1)
    return encode_packet(Packet(TYPE_SET_OSD, sequence, bytes((flags,))))


def make_get_thumbnail(sequence: int) -> bytes:
    return encode_packet(Packet(msg_type=TYPE_GET_THUMBNAIL, sequence=sequence))


def decode_status(packet: Packet) -> Status:
    if packet.msg_type != TYPE_STATUS:
        raise ProtocolError("packet is not STATUS")
    if len(packet.payload) not in (4, 15, 20):
        raise ProtocolError("STATUS payload must contain four, fifteen, or twenty bytes")

    state, flags, write_buffer, display_buffer = packet.payload[:4]
    return Status(
        state_code=state & 0x0F,
        display_valid=bool(flags & (1 << 0)),
        sdram_init_done=bool(flags & (1 << 1)),
        sdram_refresh_active=bool(flags & (1 << 2)),
        sdram_busy=bool(flags & (1 << 3)),
        audio_pll_lock=bool(flags & (1 << 4)),
        audio_valid=bool(flags & (1 << 5)),
        axis_ready=bool(flags & (1 << 6)),
        write_buffer=write_buffer & 0x03,
        display_buffer=display_buffer & 0x03,
        app_state=packet.payload[4] & 0x0F if len(packet.payload) >= 15 else None,
        app_target_image=packet.payload[5] & 0x0F if len(packet.payload) >= 15 else None,
        diagnostic_counts=tuple(packet.payload[6:]) if len(packet.payload) >= 15 else (),
    )


def encode_many(packets: Iterable[Packet]) -> bytes:
    return b"".join(encode_packet(packet) for packet in packets)
