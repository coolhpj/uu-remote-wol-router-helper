# Compatibility Matrix / 兼容性矩阵

本文件只记录可验证状态，不把理论兼容性写成已支持。

## 状态定义

- **Verified**：真实设备完成安装、真实重启、UU 云连接、辅助设备识别与手机移动数据远程开机终验。
- **Platform reference**：平台安装/启动/云连接等关键能力已经研究，但缺少完整 Remote WOL 终验证据，或证据未纳入当前交接包。
- **Experimental**：有明确技术依据，但尚未完成完整实机验证。
- **Unknown**：尚未测试。
- **Unsupported**：已知缺少必要能力，或当前项目明确不支持。

## 当前设备

| Vendor | Model | Device ID | Firmware family | CPU/Arch | UU channel | SSH/Shell | Install | Reboot | Cloud | Remote WOL | Status |
|---|---|---|---|---|---|---|---:|---:|---:|---:|---|
| Redmi | AX6000 | RB06 | XiaoQiang / OpenWrt-derived | MT7986 / AArch64 | `openwrt-aarch64` | Required for manual adaptation | ✅ | ✅ | ✅ | ✅ | **Verified** |
| ASUS | RT-AX86U | RT-AX86U | ASUSWRT / Merlin-KoolShare | AArch64 | `static-asuswrt` | Not required for official UI; required for advanced adaptation/diagnostics | ✅ | ✅ | ✅ | ⚠️ | Platform reference |

## Redmi AX6000 / RB06

### 已验证

- 板载 PC S5 WOL 正常；
- 网易官方 `openwrt-aarch64` 插件可运行；
- 历史终验版本 `v14.6.24`；
- `/data` 持久区有效；
- `/etc/rc.local` 在真实 reboot 后不可靠；
- UCI firewall include 可作为持久入口；
- 冷启动后 UU 三类核心进程自动恢复；
- 网易 `:16000` 控制连接可自动进入 ESTABLISHED；
- UU主机加速 App 可识别 `OpenWrt`；
- 同账号关系修正并重新配置 PC 后，手机移动数据远程开机成功。

### 不应误解

- `公网 UDP 40009 → LAN PC:9` 是另一个独立 Wake-on-WAN 备用链，不属于网易 UU远程内部机制。
- 历史公网 IP、网易控制服务器 IP 都是动态信息，不应写死。

## ASUS RT-AX86U

### 已验证/研究

- ASUSWRT 系存在网易 UU 官方集成入口；
- 当前样本为 Merlin-KoolShare 改版环境；
- 网易下发通道研究到 `static-asuswrt`；
- 历史研究版本为 `v14.6.24`；
- `/jffs` 可作为持久区域；
- UU 后台/WOL 待机与 MC2 透明代理可以共存；
- 真正对某 PC 开启 UU 游戏加速后，UU 策略路由可能影响该 PC 原本依赖 MC2 的代理访问。

### 当前标记原则

在当前交接证据中，不把 RT-AX86U 标成 `Remote WOL Verified`，除非后续补入明确的手机移动数据终验记录。

## 新设备进入兼容矩阵的流程

1. 确认设备品牌、型号、固件、架构；
2. 优先确认官方是否已经支持 UU远程；
3. 若官方已支持，优先记录官方路径，不要求用户为了本项目开启 SSH；
4. 若需要社区适配，确认 SSH/root Shell、持久存储与回滚能力；
5. 运行只读环境采集；
6. 匹配已有平台 adapter；
7. 若不匹配，创建新的平台研究分支；
8. 完成安装与 smoke test；
9. **必须真实 reboot**；
10. 验证 UU 云连接；
11. 验证 App/账号/辅助设备关系；
12. 手机关闭 Wi‑Fi、仅使用移动数据完成 WOL；
13. 才能升级为 `Verified`。

## 贡献者提交新设备时需要的信息

未来 Issue Template 会要求：

- Brand / 品牌
- Model / 型号
- Firmware / 固件
- CPU architecture / 架构
- SSH/root 是否可用
- 持久存储路径
- UCI / NVRAM / procd / init 信息
- iptables / nftables
- 当前是否存在 UU 官方入口
- 只读 collect-info 报告
- 是否愿意测试 Experimental adapter

默认不得提交敏感凭据、设备验证码或未脱敏的网络身份信息。
