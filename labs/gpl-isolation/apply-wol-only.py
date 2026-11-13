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
/// WOL-only is a separate runtime, not merely a WebRTC event filter.
/// The policy must run before any desktop, audio, input or assist setup.
fn wol_only_startup_policy(arg_count: usize, enabled: bool, remote_assist: &str,
    port_mapping: &str, allowed_mac: Option<&str>, lan_iface: Option<&str>) -> bool {
    let iface_ok = lan_iface.is_some_and(|name|
        !name.is_empty() && name.len() <= 15 && name != "lo" &&
        name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.'));
    arg_count == 1 && enabled && remote_assist == "0" && port_mapping == "0" &&
        allowed_mac.and_then(wol::parse_mac).is_some() && iface_ok
}

/// The distinct host never constructs InputInjector, ScreenCapture, Assist,
/// WebRtcSession, terminal, file transfer or a port mapping listener.
async fn wol_only_host() -> Result<(), Box<dyn std::error::Error>> {
    let credentials = config::file().and_then(Credentials::load)?;
    let auth = Arc::new(UUAuthClient::new(credentials));
    let mut stop = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    loop {
        let room = tokio::select! {
            answer = auth.create_room() => answer,
            _ = stop.recv() => return Ok(()),
            _ = tokio::signal::ctrl_c() => return Ok(()),
        }.map_err(|_| std::io::Error::other("WOL-only room authorization denied"))?;
        let (events_tx, mut events_rx) = mpsc::channel::<SignalingEvent>(32);
        let connection = tokio::select! {
            answer = SignalingClient::connect(&room.signaling_server, &room.token, events_tx) => answer,
            _ = stop.recv() => return Ok(()),
            _ = tokio::signal::ctrl_c() => return Ok(()),
        };
        let _connection = match connection {
            Ok(connection) => connection,
            Err(_) => {
                log::warn!("WOL-only signaling connection rejected; retrying");
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                continue;
            }
        };
        let renewal = tokio::time::sleep(std::time::Duration::from_secs(900));
        tokio::pin!(renewal);
        loop {
            let event = tokio::select! {
                event = events_rx.recv() => event,
                _ = &mut renewal => Some(SignalingEvent::Disconnected),
                _ = stop.recv() => return Ok(()),
                _ = tokio::signal::ctrl_c() => return Ok(()),
            };
            match event {
                Some(SignalingEvent::Connected) => {
                    // A failed LAN preflight must never register a bogus helper.
                    if wol::lan_info().is_none() {
                        return Err("WOL-only LAN interface invalid".into());
                    }
                    wol::report(&auth).await;
                }
                Some(SignalingEvent::RoomInfoAck(_)) => {}
                Some(SignalingEvent::DeviceInfoChanged(ref value))
                    if value.get("type").and_then(serde_json::Value::as_str) == Some("wake_on_lan") => {
                    let data = value.get("data").unwrap_or(value);
                    match wol::handle_push(data) {
                        Ok(1) => log::info!("WOL-only one authorized magic packet sent"),
                        _ => log::warn!("WOL-only denied or failed a wake request"),
                    }
                }
                Some(SignalingEvent::Disconnected) | None => break,
                Some(SignalingEvent::Stop) => return Ok(()),
                // All remote desktop, terminal, file and other events are inert.
                _ => log::warn!("WOL-only rejected non-wake signaling event"),
            }
        }
    }
}

#[cfg(test)]
mod wol_only_startup_tests {
    use super::*;
    #[test]
    fn refuses_assist_commands_missing_guards_and_wrong_interface() {
        let valid = wol_only_startup_policy(1,true,"0","0",
            Some("02:11:22:33:44:55"),Some("br-lan"));
        assert!(valid);
        for args in [2usize,3,5] {
            assert!(!wol_only_startup_policy(args,true,"0","0",Some("02:11:22:33:44:55"),Some("br-lan")));
        }
        for iface in [None,Some("lo"),Some("eth/0"),Some(""),Some("too_long_interface")] {
            assert!(!wol_only_startup_policy(1,true,"0","0",Some("02:11:22:33:44:55"),iface));
        }
        assert!(!wol_only_startup_policy(1,false,"0","0",Some("02:11:22:33:44:55"),Some("br-lan")));
        assert!(!wol_only_startup_policy(1,true,"1","0",Some("02:11:22:33:44:55"),Some("br-lan")));
        assert!(!wol_only_startup_policy(1,true,"0","1",Some("02:11:22:33:44:55"),Some("br-lan")));
        assert!(!wol_only_startup_policy(1,true,"0","0",None,Some("br-lan")));
    }
}

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
    startup = '''    // This early return precedes desktop, input, audio and assist initialization.
    // Login is a separate interactive command with UU_WOL_ONLY unset.
    if std::env::var("UU_WOL_ONLY").ok().as_deref() == Some("1") {
        let allowed = std::env::var("UU_WOL_ALLOWED_MAC").ok();
        let iface = std::env::var("UU_WOL_LAN_IFACE").ok();
        if !wol_only_startup_policy(std::env::args().len(), wol::enabled(),
            &std::env::var("UU_REMOTE_ASSIST").unwrap_or_default(),
            &std::env::var("UU_PORT_MAPPING").unwrap_or_default(),
            allowed.as_deref(), iface.as_deref()) {
            return Err("WOL_ONLY_STARTUP_DENIED: mode and LAN allowlist required".into());
        }
        env_logger::Builder::new().filter_level(log::LevelFilter::Off)
            .filter_module("uuremote_server", log::LevelFilter::Info).init();
        return wol_only_host().await;
    }
'''
    main_rs = replace_once(main_rs, "async fn main() -> Result<(), Box<dyn std::error::Error>> {",
        "async fn main() -> Result<(), Box<dyn std::error::Error>> {\n" + startup, "src/main.rs")
    # The ordinary host remains unchanged: UU_WOL_ONLY returns from main()
    # before calling serve(), so its feature-rich event dispatcher is unreachable.

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
    bind_helper = r'''
/// A WOL-only route must name the intended LAN adapter, never choose the default route.
fn wol_only_interface_name_ok(name: &str) -> bool {
    !name.is_empty() && name != "lo" && name.len() <= 15 &&
        name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
}

#[cfg(target_os = "linux")]
fn wol_only_bind_interface(socket: &UdpSocket, iface: &str) -> Result<(), String> {
    use std::os::fd::AsRawFd;
    if !wol_only_interface_name_ok(iface) {
        return Err("WOL-only interface refused".into());
    }
    let name = std::ffi::CString::new(iface)
        .map_err(|_| "WOL-only interface invalid")?;
    let result = unsafe {
        libc::setsockopt(socket.as_raw_fd(), libc::SOL_SOCKET, libc::SO_BINDTODEVICE,
            name.as_ptr().cast(), name.as_bytes_with_nul().len() as libc::socklen_t)
    };
    if result != 0 { return Err("WOL-only SO_BINDTODEVICE refused".into()); }
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn wol_only_bind_interface(_: &UdpSocket, _: &str) -> Result<(), String> {
    Err("WOL-only requires Linux".into())
}

'''
    wol_rs = replace_once(wol_rs,
        "/// Handles a `wake_on_lan` push payload; returns how many datagrams were sent.",
        bind_helper + "/// Handles a `wake_on_lan` push payload; returns how many datagrams were sent.",
        "src/wol.rs",
    )
    wol_rs = replace_once(
        wol_rs,
        "/// Handles a `wake_on_lan` push payload; returns how many datagrams were sent.",
        wol_plan + "/// Handles a `wake_on_lan` push payload; returns how many datagrams were sent.",
        "src/wol.rs",
    )
    # Only opt-in WOL-only mode may override upstream default-route detection.
    # The ordinary upstream program continues to behave as before.
    wol_rs = replace_once(
        wol_rs,
        '''    let iface = routes.lines().skip(1).map(|l| l.split_whitespace().collect::<Vec<_>>())
        .find(|f| f.len() > 2 && f[1] == "00000000")?.first()?.to_string();''',
        '''    let iface = if std::env::var("UU_WOL_ONLY").ok().as_deref() == Some("1") {
        let name = std::env::var("UU_WOL_LAN_IFACE").ok()?;
        if !wol_only_interface_name_ok(&name) { return None; }
        name
    } else {
        routes.lines().skip(1).map(|l| l.split_whitespace().collect::<Vec<_>>())
            .find(|f| f.len() > 2 && f[1] == "00000000")?.first()?.to_string()
    };''', "src/wol.rs",
    )
    wol_rs = replace_once(
        wol_rs,
        '''    let packet = magic_packet(mac);
    let socket = UdpSocket::bind("0.0.0.0:0")''',
        '''    if std::env::var("UU_WOL_ONLY").ok().as_deref() == Some("1") {
        let allowed = std::env::var("UU_WOL_ALLOWED_MAC")
            .map_err(|_| "WOL-only allowlist is required")?;
        let iface = std::env::var("UU_WOL_LAN_IFACE")
            .map_err(|_| "WOL-only LAN interface is required")?;
        if !wol_only_interface_name_ok(&iface) {
            return Err("WOL-only LAN interface unsafe".into());
        }
        let (_, lan_ip, lan_mask) = lan_info()
            .ok_or("WOL-only LAN identity unavailable")?;
        let destination = wol_only_destination(data, &allowed, &lan_ip, &lan_mask)?;
        let packet = magic_packet(mac);
        let source_ip: Ipv4Addr = lan_ip.parse()
            .map_err(|_| "WOL-only source address invalid")?;
        let socket = UdpSocket::bind(SocketAddrV4::new(source_ip, 0))
            .map_err(|e| format!("WOL-only source bind: {}", e.kind()))?;
        wol_only_bind_interface(&socket, &iface)?;
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
    fn wol_only_ci_isolated_packet_sender() {
        // Not run on a normal developer host or a real LAN.
        // The CI caller must create a throwaway private network namespace.
        if std::env::var("UU_WOL_ISOLATED_CI").ok().as_deref() != Some("1") {
            return;
        }
        let payload = serde_json::json!({"target_device": {
            "mac": "02:11:22:33:44:55", "ip": "198.51.100.40",
            "subnet_mask": "255.255.255.0"
        }});
        assert_eq!(handle_push(&payload).unwrap(), 1);
    }

    #[test]
    fn wol_only_rejects_missing_or_dangerous_lan_interface_names() {
        assert!(wol_only_interface_name_ok("br-lan"));
        assert!(wol_only_interface_name_ok("enp2s0"));
        for bad in ["", "lo", "../wan", "a/b", "invalid-too-long-device", "bad space"] {
            assert!(!wol_only_interface_name_ok(bad));
        }
    }

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
