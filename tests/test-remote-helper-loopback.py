#!/usr/bin/env python3
"""Loopback-only real socat test; never send to a LAN, gateway or public IP."""
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENCODER = ROOT / "experiments" / "remote-helper" / "magic-packet-hex.sh"
IFACE = "lo"
HOST = "127.0.0.1"
MAC = "02:aa:bb:cc:dd:ee"

def run() -> int:
    if not sys.platform.startswith("linux") or not shutil.which("socat"):
        print("REMOTE_HELPER_LOOPBACK_SKIPPED: Linux socat unavailable")
        return 0

    text = subprocess.check_output(["sh", str(ENCODER), MAC], text=True, timeout=5).strip()
    payload = bytes.fromhex(text)
    if len(payload) != 102 or payload != b"\xff" * 6 + bytes.fromhex("02AABBCCDDEE") * 16:
        raise AssertionError("Bad original Magic Packet encoder output")

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
        receiver.bind((HOST, 0))
        receiver.settimeout(0.55)
        port = receiver.getsockname()[1]
        dest = (
            f"UDP4-DATAGRAM:{HOST}:{port},so-bindtodevice={IFACE},"
            f"bind={HOST},dontroute,shut-none"
        )
        done = subprocess.run(
            ["socat", "-u", "-", dest],
            input=payload,
            capture_output=True,
            timeout=5,
            check=False,
        )
        if done.returncode != 0:
            raise AssertionError(f"socat failed on loopback: rc={done.returncode}")
        received = []
        while True:
            try:
                received.append(receiver.recvfrom(2048)[0])
            except socket.timeout:
                break

    if received != [payload]:
        raise AssertionError(
            f"Expected exactly one 102-byte datagram; got {[len(x) for x in received]}"
        )
    print("REMOTE_HELPER_LOOPBACK_REAL_UDP_PASS datagrams=1 bytes=102 dest=127.0.0.1")
    return 0

if __name__ == "__main__":
    sys.exit(run())
