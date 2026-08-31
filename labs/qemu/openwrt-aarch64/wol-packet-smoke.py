#!/usr/bin/env python3

import argparse
import socket
import struct
import sys
import time
from pathlib import Path


def parse_hex(value: str, expected_len: int, label: str) -> bytes:
    try:
        raw = bytes.fromhex(value)
    except ValueError as exc:
        raise SystemExit(f"invalid {label} hex: {exc}")
    if len(raw) != expected_len:
        raise SystemExit(f"{label} must be {expected_len} bytes")
    return raw


def checksum16(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def magic_payload(target: bytes) -> bytes:
    return b"\xff" * 6 + target * 16


def build_udp_frame(source: bytes, target: bytes) -> bytes:
    payload = magic_payload(target)
    destination = b"\xff" * 6
    eth = destination + source + struct.pack("!H", 0x0800)

    src_ip = bytes.fromhex("c0000201")
    dst_ip = b"\xff" * 4
    udp = struct.pack("!HHHH", 40009, 9, 8 + len(payload), 0)

    total_len = 20 + len(udp) + len(payload)
    ip_wo_checksum = struct.pack(
        "!BBHHHBBH4s4s",
        0x45,
        0,
        total_len,
        0,
        0,
        64,
        socket.IPPROTO_UDP,
        0,
        src_ip,
        dst_ip,
    )
    ip = ip_wo_checksum[:10] + struct.pack("!H", checksum16(ip_wo_checksum)) + ip_wo_checksum[12:]
    return eth + ip + udp + payload


def build_raw_frame(source: bytes, target: bytes) -> bytes:
    destination = b"\xff" * 6
    return destination + source + struct.pack("!H", 0x0842) + magic_payload(target)


def send_frames(interface: str, source_hex: str, target_hex: str) -> None:
    source = parse_hex(source_hex, 6, "source")
    target = parse_hex(target_hex, 6, "target")
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    try:
        sock.bind((interface, 0))
        for frame in (build_udp_frame(source, target), build_raw_frame(source, target)):
            sock.send(frame)
            time.sleep(0.2)
    finally:
        sock.close()


def iter_pcap_frames(path: Path):
    data = path.read_bytes()
    if len(data) < 24:
        raise SystemExit("pcap is too short")

    magic = data[:4]
    if magic == b"\xd4\xc3\xb2\xa1":
        endian = "<"
    elif magic == b"\xa1\xb2\xc3\xd4":
        endian = ">"
    else:
        raise SystemExit("unsupported pcap magic")

    offset = 24
    while offset + 16 <= len(data):
        _, _, incl_len, _ = struct.unpack_from(endian + "IIII", data, offset)
        offset += 16
        frame = data[offset : offset + incl_len]
        if len(frame) != incl_len:
            raise SystemExit("truncated pcap frame")
        offset += incl_len
        yield frame


def valid_magic(payload: bytes, target: bytes) -> bool:
    return len(payload) == 102 and payload[:6] == b"\xff" * 6 and payload[6:] == target * 16


def verify_pcap(path: Path, source_hex: str, target_hex: str) -> None:
    source = parse_hex(source_hex, 6, "source")
    target = parse_hex(target_hex, 6, "target")
    udp_ok = False
    raw_ok = False

    for frame in iter_pcap_frames(path):
        if len(frame) < 14:
            continue
        if frame[:6] != b"\xff" * 6 or frame[6:12] != source:
            continue

        eth_type = struct.unpack("!H", frame[12:14])[0]
        if eth_type == 0x0842:
            if valid_magic(frame[14:], target):
                raw_ok = True
            continue

        if eth_type != 0x0800 or len(frame) < 14 + 20 + 8:
            continue
        ip = frame[14:]
        ihl = (ip[0] & 0x0F) * 4
        if ihl < 20 or len(ip) < ihl + 8 or ip[9] != socket.IPPROTO_UDP:
            continue
        if ip[16:20] != b"\xff" * 4:
            continue
        udp = ip[ihl:]
        dst_port = struct.unpack("!H", udp[2:4])[0]
        udp_len = struct.unpack("!H", udp[4:6])[0]
        if dst_port != 9 or udp_len < 8 or len(udp) < udp_len:
            continue
        if valid_magic(udp[8:udp_len], target):
            udp_ok = True

    if not udp_ok:
        raise SystemExit("missing valid UDP/9 Magic Packet at virtual target")
    if not raw_ok:
        raise SystemExit("missing valid EtherType 0x0842 Magic Packet at virtual target")

    print("WOL_UDP9_TARGET_CAPTURE_OK")
    print("WOL_ETHERTYPE_0842_TARGET_CAPTURE_OK")
    print("WOL_SYNTHETIC_LAN_PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    send_parser = sub.add_parser("send")
    send_parser.add_argument("--interface", required=True)
    send_parser.add_argument("--source", required=True)
    send_parser.add_argument("--target", required=True)

    verify_parser = sub.add_parser("verify")
    verify_parser.add_argument("--pcap", required=True)
    verify_parser.add_argument("--source", required=True)
    verify_parser.add_argument("--target", required=True)

    args = parser.parse_args()
    if args.command == "send":
        send_frames(args.interface, args.source, args.target)
    else:
        verify_pcap(Path(args.pcap), args.source, args.target)


if __name__ == "__main__":
    main()
