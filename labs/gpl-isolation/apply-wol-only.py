#!/usr/bin/env python3
"""GPL-3.0-or-later, test-only patch for pinned VallierDev/uu-remote-linux v0.2.58.

Applies to a throwaway upstream clone in GitHub Actions. This is NOT the
MIT project's implementation, not a production image, and never runs a
cloud-connected executable. Fail closed on every unknown source change.
"""
from pathlib import Path
import subprocess
import sys

PINNED_UPSTREAM = "0e1e935fb41c2aac2bdd5eebdd4b38a7476d14bc"


def replace_once(text: str, old: str, new: str, filename: str) -> str:
    found = text.count(old)
    if found != 1:
        raise SystemExit(f"GPL_WOL_ONLY_PATCH_CONTEXT_MISMATCH {filename} count={found}")
    return text.replace(old, new, 1)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply-wol-only.py UPSTREAM_GPL_CLONE")
    source = Path(sys.argv[1]).resolve()
    actual = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=source, text=True
    ).strip()
    if actual != PINNED_UPSTREAM:
        raise SystemExit("GPL_WOL_ONLY_UPSTREAM_PIN_MISMATCH")

    path = source / "src/main.rs"
    main_rs = path.read_text(encoding="utf-8")
    guard_and_tests = r'''
/// A test-only WOL-first ingress gate for the separate GPL upstream host.
/// No remote desktop, terminal, file-transfer, WebRTC or port-map signaling
/// is allowed through its event dispatcher in UU_WOL_ONLY=1.
fn wol_only_event_allowed(event: &SignalingEvent) -> bool {
    match event {
        SignalingEvent::Stop | SignalingEvent::Connected |
        SignalingEvent::RoomInfoAck(_) | SignalingEvent::Disconnected => true,
        SignalingEvent::DeviceInfoChanged(value) => {
            value.get("type").and_then(serde_json::Value::as_str) == Some("wake_on_lan")
        }
        _ => false,
    }
}

#[cfg(test)]
mod wol_only_isolation_tests {
    use super::*;

    #[test]
    fn only_room_lifecycle_and_wol_push_are_accepted() {
        assert!(wol_only_event_allowed(&SignalingEvent::Connected));
        assert!(wol_only_event_allowed(&SignalingEvent::Disconnected));
        assert!(wol_only_event_allowed(&SignalingEvent::Stop));
        assert!(wol_only_event_allowed(&SignalingEvent::RoomInfoAck(serde_json::json!({}))));
        assert!(wol_only_event_allowed(&SignalingEvent::DeviceInfoChanged(
            serde_json::json!({"type": "wake_on_lan", "data": {}}))));
        assert!(!wol_only_event_allowed(&SignalingEvent::DeviceInfoChanged(
            serde_json::json!({"type": "remote_control"}))));
        assert!(!wol_only_event_allowed(&SignalingEvent::DeviceInfoChanged(
            serde_json::json!({"type": "get_control_mode"}))));
    }

    #[test]
    fn rtc_and_remote_tools_cannot_enter_the_wol_only_dispatcher() {
        assert!(!wol_only_event_allowed(&SignalingEvent::BeControlled(
            serde_json::json!({}))));
        assert!(!wol_only_event_allowed(&SignalingEvent::DesktopRequested(
            "fixture-peer".to_owned())));
        assert!(!wol_only_event_allowed(&SignalingEvent::Released(
            serde_json::json!({}))));
        assert!(!wol_only_event_allowed(&SignalingEvent::Left(
            serde_json::json!({}))));
    }
}

'''
    main_rs = replace_once(
        main_rs, "#[cfg(test)]\nmod peer_release_tests {",
        guard_and_tests + "#[cfg(test)]\nmod peer_release_tests {", "src/main.rs",
    )
    marker = '''    let portal_desktop = (capture.backend == desktop_backend::DesktopBackend::Portal && !desktop_backend::headless())'''
    startup = '''    // Opt-in only: a missing or inconsistent protection setting is fatal.
    let wol_only_mode = std::env::var("UU_WOL_ONLY").ok().as_deref() == Some("1");
    if wol_only_mode && (!wol::enabled() ||
        std::env::var("UU_REMOTE_ASSIST").ok().as_deref() != Some("0") ||
        std::env::var("UU_PORT_MAPPING").ok().as_deref() != Some("0") ||
        std::env::var("UU_WOL_ALLOWED_MAC").ok()
          .and_then(|v| wol::parse_mac(&v)).is_none()) {
        return Err("WOL-only environment policy incomplete".into());
    }
'''
    main_rs = replace_once(main_rs, marker, startup + marker, "src/main.rs")
    main_rs = replace_once(
        main_rs,
        '''            match evt {
''',
        '''            if wol_only_mode && !wol_only_event_allowed(&evt) {
                // Do not construct any WebRTC session or remote-tool peer.
                log::warn!("WOL-only mode denied a non-WOL signaling event");
                continue;
            }
            match evt {
''', "src/main.rs",
    )

    wolpath = source / "src/wol.rs"
    wol_rs = wolpath.read_text(encoding="utf-8")
    wol_plan = r'''
/// Offline, testable egress gate for a SINGLE directed-broadcast UDP/9.
/// The cloud-provided target cannot select an arbitrary MAC or out-of-subnet
/// destination, and the default-route LAN identity must match the target.
fn wol_only_destination(
    data: &serde_json::Value, allowed_mac: &str,
    lan_ip: &str, lan_mask: &str,
) -> Result<SocketAddrV4, String> {
    let target = data.get("target_device")
        .or_else(|| data.get("data").and_then(|v| v.get("target_device")))
        .ok_or("missing target_device")?;
    let value = |name: &str| target.get(name)
        .and_then(serde_json::Value::as_str).unwrap_or("");
    let target_mac = parse_mac(value("mac")).ok_or("invalid target MAC")?;
    let approved = parse_mac(allowed_mac).ok_or("invalid allowlisted MAC")?;
    if target_mac != approved { return Err("target MAC not allowlisted".into()); }
    let target_ip: Ipv4Addr = value("ip").parse().map_err(|_| "invalid target IP")?;
    let target_mask: Ipv4Addr = value("subnet_mask")
        .parse().map_err(|_| "invalid target mask")?;
    let local_ip: Ipv4Addr = lan_ip.parse().map_err(|_| "invalid LAN IP")?;
    let local_mask: Ipv4Addr = lan_mask.parse().map_err(|_| "invalid LAN mask")?;
    let mask = u32::from(local_mask);
    if target_mask != local_mask || mask.leading_ones() < 8 ||
        mask.leading_ones() > 30 || mask.leading_ones() +
        mask.trailing_zeros() != 32 {
        return Err("LAN prefix mismatch or unsupported mask".into());
    }
    if (u32::from(target_ip) & mask) != (u32::from(local_ip) & mask) ||
        target_ip == local_ip {
        return Err("target outside approved LAN".into());
    }
    let broadcast = subnet_broadcast(&lan_ip.to_string(), lan_mask)
        .ok_or("invalid LAN broadcast")?;
    if target_ip == broadcast || broadcast == Ipv4Addr::BROADCAST {
        return Err("unsafe broadcast target".into());
    }
    Ok(SocketAddrV4::new(broadcast, 9))
}

'''
    wol_rs = replace_once(
        wol_rs,
        "/// Handles a `wake_on_lan` push payload; returns how many datagrams were sent.",
        wol_plan + "/// Handles a `wake_on_lan` push payload; returns how many datagrams were sent.",
        "src/wol.rs",
    )
    wol_rs = replace_once(
        wol_rs,
        '''    let packet = magic_packet(mac);
    let socket = UdpSocket::bind("0.0.0.0:0")''',
        '''    if std::env::var("UU_WOL_ONLY").ok().as_deref() == Some("1") {
        let allowed = std::env::var("UU_WOL_ALLOWED_MAC")
            .map_err(|_| "WOL-only allowlist is required")?;
        let (_, lan_ip, lan_mask) = lan_info()
            .ok_or("WOL-only LAN identity unavailable")?;
        let destination = wol_only_destination(data, &allowed, &lan_ip, &lan_mask)?;
        let packet = magic_packet(mac);
        let socket = UdpSocket::bind("0.0.0.0:0")
            .map_err(|e| format!("WOL-only bind: {}", e.kind()))?;
        socket.set_broadcast(true)
            .map_err(|e| format!("WOL-only broadcast: {}", e.kind()))?;
        if socket.send_to(&packet, destination).ok() != Some(packet.len()) {
            return Err("WOL-only directed packet not sent".into());
        }
        return Ok(1);
    }
    let packet = magic_packet(mac);
    let socket = UdpSocket::bind("0.0.0.0:0")''',
        "src/wol.rs",
    )
    new_tests = r'''
    #[test]
    fn wol_only_egress_is_one_approved_mac_and_one_directed_udp9_address() {
        let payload = serde_json::json!({"target_device": {
            "mac": "02:11:22:33:44:55", "ip": "198.51.100.40",
            "subnet_mask": "255.255.255.0"
        }});
        let destination = wol_only_destination(
            &payload, "02:11:22:33:44:55", "198.51.100.1", "255.255.255.0"
        ).unwrap();
        assert_eq!(*destination.ip(), Ipv4Addr::new(198, 51, 100, 255));
        assert_eq!(destination.port(), 9);
        assert!(wol_only_destination(
            &payload, "02:11:22:33:44:56", "198.51.100.1", "255.255.255.0"
        ).is_err());
        assert!(wol_only_destination(
            &payload, "02:11:22:33:44:55", "203.0.113.1", "255.255.255.0"
        ).is_err());
        assert!(wol_only_destination(
            &payload, "02:11:22:33:44:55", "198.51.100.1", "255.255.0.0"
        ).is_err());
    }
'''
    wol_rs = replace_once(
        wol_rs, "    #[test]\n    fn push_without_target_is_rejected() {",
        new_tests + "    #[test]\n    fn push_without_target_is_rejected() {",
        "src/wol.rs",
    )
    path.write_text(main_rs, encoding="utf-8")
    wolpath.write_text(wol_rs, encoding="utf-8")
    print("GPL_WOL_ONLY_PATCH_PASS: pinned clone, explicit-mode ingress gate,")
    print("directed UDP9 egress/allowlist gate and synthetic Rust tests")
    print("NOT_INSTALLABLE: Rust compilation/tests and independent audit still required")


if __name__ == "__main__":
    main()
