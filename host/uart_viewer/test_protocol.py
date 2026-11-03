import unittest

from protocol import (
    FLAG_ACK,
    Packet,
    PacketDecoder,
    ProtocolError,
    TYPE_PING,
    TYPE_STATUS,
    crc16_ccitt_false,
    decode_packet,
    decode_status,
    encode_packet,
    make_get_status,
    make_ping,
    make_set_brightness,
    make_set_contrast,
    make_set_osd,
)


class ProtocolTests(unittest.TestCase):
    def test_crc_standard_vector(self):
        self.assertEqual(crc16_ccitt_false(b"123456789"), 0x29B1)

    def test_packet_round_trip(self):
        packet = Packet(TYPE_STATUS, 0x1234, b"\x0A\x5B\x02\x01")
        self.assertEqual(decode_packet(encode_packet(packet)), packet)

    def test_command_helpers(self):
        self.assertEqual(decode_packet(make_ping(7)), Packet(TYPE_PING, 7))
        self.assertEqual(decode_packet(make_get_status(8)).msg_type, 0x81)
        self.assertEqual(
            decode_packet(make_set_brightness(9, -2)).payload, b"\xfe"
        )
        self.assertEqual(
            decode_packet(make_set_contrast(10, 3)).payload, b"\x03"
        )
        self.assertEqual(
            decode_packet(make_set_osd(11, True, False)).payload, b"\x01"
        )

        with self.assertRaises(ValueError):
            make_set_brightness(12, 3)
        with self.assertRaises(ValueError):
            make_set_contrast(13, 4)

    def test_stream_fragmentation_and_resync(self):
        ping = encode_packet(Packet(TYPE_PING, 0x1234, flags=FLAG_ACK))
        status = encode_packet(Packet(TYPE_STATUS, 9, b"\x0A\x5B\x02\x01"))
        decoder = PacketDecoder()

        self.assertEqual(decoder.feed(b"noise" + ping[:4]), [])
        self.assertEqual(decoder.feed(ping[4:] + status[:1]), [Packet(TYPE_PING, 0x1234, flags=FLAG_ACK)])
        self.assertEqual(decoder.feed(status[1:]), [Packet(TYPE_STATUS, 9, b"\x0A\x5B\x02\x01")])
        self.assertEqual(decoder.discarded_bytes, 5)

    def test_bad_crc_is_dropped_before_next_packet(self):
        bad = bytearray(make_ping(0xDEAD))
        bad[-1] ^= 1
        good = make_ping(0x1234)
        decoder = PacketDecoder()

        self.assertEqual(decoder.feed(bad + good), [Packet(TYPE_PING, 0x1234)])
        self.assertEqual(decoder.crc_errors, 1)

    def test_status_decode(self):
        status = decode_status(Packet(TYPE_STATUS, 1, b"\x0A\x5B\x02\x01"))
        self.assertEqual(status.state_code, 0xA)
        self.assertTrue(status.display_valid)
        self.assertTrue(status.sdram_init_done)
        self.assertFalse(status.sdram_refresh_active)
        self.assertTrue(status.sdram_busy)
        self.assertTrue(status.audio_pll_lock)
        self.assertFalse(status.audio_valid)
        self.assertTrue(status.axis_ready)
        self.assertEqual(status.write_buffer, 2)
        self.assertEqual(status.display_buffer, 1)
        self.assertEqual(status.diagnostic_counts, ())

        extended = decode_status(Packet(TYPE_STATUS, 2,
                                        bytes((10, 91, 2, 1, 3, 5,
                                               1, 1, 0, 2, 0, 0, 0, 3, 3))))
        self.assertEqual(extended.app_state, 3)
        self.assertEqual(extended.app_target_image, 5)
        self.assertEqual(extended.diagnostic_counts,
                         (1, 1, 0, 2, 0, 0, 0, 3, 3))

        recovery = decode_status(Packet(TYPE_STATUS, 3,
                                        bytes((10, 91, 2, 1, 3, 5,
                                               1, 1, 0, 2, 0, 0, 0, 3,
                                               4, 0, 0, 1, 2, 3))))
        self.assertEqual(recovery.diagnostic_counts,
                         (1, 1, 0, 2, 0, 0, 0, 3, 4, 0, 0, 1, 2, 3))

    def test_rejects_oversized_payload(self):
        with self.assertRaises(ProtocolError):
            encode_packet(Packet(TYPE_PING, 0, bytes(257)))


if __name__ == "__main__":
    unittest.main()
