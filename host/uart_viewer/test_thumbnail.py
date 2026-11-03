import struct
import unittest
import zlib

from protocol import (
    Packet,
    ProtocolError,
    TYPE_IMAGE_BEGIN,
    TYPE_IMAGE_DATA,
    TYPE_IMAGE_END,
    TYPE_GET_THUMBNAIL,
    decode_packet,
    make_get_thumbnail,
)
from thumbnail import ThumbnailAssembler, rgb565_to_ppm


class ThumbnailTests(unittest.TestCase):
    def make_packets(self):
        data = struct.pack("<HHHH", 0xF800, 0x07E0, 0x001F, 0xFFFF)
        frame_id = 7
        return (
            Packet(TYPE_IMAGE_BEGIN, 1, struct.pack("<HHHHI", 2, 2, 1, frame_id, len(data))),
            Packet(TYPE_IMAGE_DATA, 2, struct.pack("<HH", frame_id, 0) + data[:4]),
            Packet(TYPE_IMAGE_DATA, 3, struct.pack("<HH", frame_id, 1) + data[4:]),
            Packet(TYPE_IMAGE_END, 4, struct.pack("<HII", frame_id, zlib.crc32(data), 3)),
        )

    def test_command_helper(self):
        packet = decode_packet(make_get_thumbnail(0x1234))
        self.assertEqual(packet.msg_type, TYPE_GET_THUMBNAIL)
        self.assertEqual(packet.sequence, 0x1234)

    def test_reassembles_and_converts_rgb565(self):
        assembler = ThumbnailAssembler()
        frame = None
        for packet in self.make_packets():
            frame = assembler.feed(packet) or frame
        self.assertIsNotNone(frame)
        self.assertEqual((frame.width, frame.height, frame.frame_id), (2, 2, 7))
        self.assertEqual(frame.dropped_requests, 3)
        self.assertEqual(
            rgb565_to_ppm(frame),
            b"P6\n2 2\n255\n" + bytes((255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255)),
        )

    def test_rejects_out_of_order_chunk(self):
        begin, _, second, _ = self.make_packets()
        assembler = ThumbnailAssembler()
        assembler.feed(begin)
        with self.assertRaisesRegex(ProtocolError, "sequence"):
            assembler.feed(second)

    def test_rejects_frame_crc(self):
        packets = list(self.make_packets())
        packets[-1] = Packet(TYPE_IMAGE_END, 4, struct.pack("<HII", 7, 0, 0))
        assembler = ThumbnailAssembler()
        with self.assertRaisesRegex(ProtocolError, "CRC32"):
            for packet in packets:
                assembler.feed(packet)


if __name__ == "__main__":
    unittest.main()
