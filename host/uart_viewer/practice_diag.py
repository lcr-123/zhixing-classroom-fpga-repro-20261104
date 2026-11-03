"""Print read-only practice page-load counters from the FPGA UART status."""

import argparse
import time

import serial
from serial.tools import list_ports

from protocol import PacketDecoder, TYPE_STATUS, decode_status


EVENT_NAMES = (
    "scan", "first", "home", "exact", "zoom", "next", "auto",
    "sd_commit", "bmp_recover", "voice_recover", "scan_recover",
    "bridge_recover", "virtual_error", "video_commit",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Serial port, for example COM5")
    parser.add_argument("--seconds", type=float, default=60.0)
    args = parser.parse_args()

    if not args.port:
        for port in list_ports.comports():
            print(f"{port.device}: {port.description}")
        return

    decoder = PacketDecoder()
    previous = None
    deadline = time.monotonic() + args.seconds
    with serial.Serial(args.port, baudrate=115200, timeout=0.2) as connection:
        while time.monotonic() < deadline:
            for packet in decoder.feed(connection.read(256)):
                if packet.msg_type != TYPE_STATUS:
                    continue
                status = decode_status(packet)
                if not status.diagnostic_counts:
                    print("Old four-byte STATUS; this bitstream has no page diagnostics")
                    return
                counts = status.diagnostic_counts
                changes = (tuple((current - old) & 0xFF
                                 for current, old in zip(counts, previous))
                           if previous is not None else counts)
                names = (EVENT_NAMES[:8] + EVENT_NAMES[-1:]
                         if len(counts) == 9 else EVENT_NAMES)
                active = " ".join(f"{name}={delta}"
                                  for name, delta in zip(names, changes) if delta)
                print(f"app={status.app_state} target={status.app_target_image + 1} "
                      f"sd_state={status.state_code} events: {active or 'none'}", flush=True)
                previous = counts


if __name__ == "__main__":
    main()
