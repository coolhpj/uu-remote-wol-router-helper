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
| ASUS | RT-AX86U | RT-AX86U | ASUSWRT / Merlin-KoolShare | AArch64 | `static-asuswrt` | Not required for official UI; required for advanced adaptation/diagnostics | ✅ | ✅ | ✅ | ✅ | **Verified** |
| iStoreOS | x86_64 VM sample | generic-openwrt-x86_64 | OpenWrt / iStoreOS 24.10.7 | x86_64 / x86/64 | `openwrt-x86_64` | Available | ✅* | ✅* | ✅ | ✅* | **Verified (this sample)**: install + reboot + mobile-data WOL + rollback + post-rollback reboot verified |
| Lenovo | Y1 / Newifi mini R6830 | lenovo-y1-mipsel-24kc | OpenWrt 22.03-SNAPSHOT / ramips/mt7620 | MT7620A / mipsel_24kc | `openwrt-mipsel` | Available | ✅ 仅 Y1 实验性持久服务；通用安装仍禁用 | ✅ 重启后服务显示运行；绑定未保持 | ✅ 临时连接；重启后旧绑定显示离线 | ✅ 临时运行实机成功 | **Experimental（持久绑定故障未解决）**：手机流量唤醒已通过；实机实验性安装和重启后服务运行已有证据，但旧设备跨重启离线、需重绑；稳定性、卸载回滚未通过 |

### Lenovo Y1 实机反馈与限制（更新至 2026-10-14）

[Issue #1 实机反馈](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1#issuecomment-6122614795)：Enderlessss 反映在实验性限时脚本运行期间，手机通过 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器** 找到并添加了 Lenovo Y1；随后在移动数据条件下通过「开始协助」流程和首页分别成功远程唤醒电脑。这是**移动数据远程唤醒功能的成功报告**，应覆盖此前测试失败的历史结论。

后续 [2026-10-13 实机回复](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1#issuecomment-6141406520) 已报告：**Lenovo Y1 专用实验性持久服务成功安装，真实重启后后台看到服务运行**。但 [2026-10-14 的新反馈](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1#issuecomment-6164268516) 进一步证实：原先添加的路由器在第二天显示「插件联网失败」，需要重新绑定辅助路由器，并重新在电脑端执行「开始协助」关联。这是**跨重启设备身份/绑定保持的真实故障**；原因尚未确定，不能直接认定重新下载插件就是身份变化根因。

因此 Y1 **不满足完整 Verified（已验证）的持续稳定运行要求**：目前仅是“临时远程唤醒成功 + 专用实验性服务安装成功 + 重启后服务出现”，并不是“重启后原设备自动恢复绑定并成功唤醒”。U 盘或内置闪存压缩包方案都还在研究，**尚未证明能够保留绑定状态**；卸载和安全回滚亦待实机验收。`platforms/openwrt/install.sh` 的**通用 MIPS 持久安装禁令**、数字菜单限制和通用临时启动限制均保持，不将结果外推至其它 MIPS/OpenWrt 设备。

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

2026-08-31 已补齐手机移动数据终验：在 AX86U-only 条件下，不重新扫码、不重新配置 PC，手机关闭 Wi-Fi、仅使用移动数据即可成功远程开机；随后双在线抓包又明确捕获到 AX86U 发出的 UDP/9 与 EtherType `0x0842` Magic Packet，目标主机随后上线。因此当前 RT-AX86U 参考样本升级为 `Remote WOL Verified`。

该 `Verified` 只对应当前 RT-AX86U / 当前固件样本，不外推到所有 ASUSWRT 设备。

## Generic OpenWrt adapter

仓库已经提供 Generic OpenWrt 的 `detect / health / preflight / stage / smoke-test / persistence` 分层能力，用于标准 OpenWrt / iStoreOS / 厂商 OpenWrt 衍生环境。

这些能力不能被理解成“所有 OpenWrt 都已支持”。只有逐台完成设备档案里的真实安装、reboot、UU云和 Remote WOL 证据，才能升级对应兼容级别。

当前第二环境样本已经用 iStoreOS 24.10.7 / x86_64 实测通过：Generic OpenWrt detect/preflight、`openwrt-x86_64 v14.6.22` 官方 API、MD5、tar、`/tmp` staging、临时 `uuplugin + guardian + :16000 ESTABLISHED` runtime smoke-test、真实 `/overlay` 持久安装，以及真实 reboot 后 procd 自动恢复。重启后 `uuplugin + guardian + :16000 ESTABLISHED` 自动恢复，OpenClash 也随后正常上线，原有上游默认路由保持不变。此前手机默认网关切到 iStoreOS 后，UU主机加速成功识别并绑定 OpenWrt；Windows 默认网关同样切到 iStoreOS 后，UU远程完成辅助设备检测，并最终在手机关闭 Wi‑Fi、仅使用移动数据时成功唤醒 Windows。

随后又实机执行了当前仓库正式 `platforms/openwrt/rollback.sh`：安装前 manifest 为 `had_install=no / had_init=no / previous_enabled=no`，rollback 返回 `ROLLBACK_OK`，项目 install/init/`S95/K10` 全部清除且 `last-rollback` 被保留。再次 reboot 后，项目 UU runtime 没有反弹，OpenClash 恢复 running，默认路由保持原上游，网易 API 连通正常。

> `Install = ✅*`、`Reboot = ✅*`、`Remote WOL = ✅*` 都只对应当前 iStoreOS x86_64 样本。这个样本已满足 `Verified` 定义，但 Generic OpenWrt 仍必须逐台完成同等级实机证据，不能因为架构相同自动继承 Verified。

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

默认不得提交：

- root 密码
- PPPoE 密码
- UU账号凭据
- SN
- Token
- 设备验证码
- 未脱敏公网 IP / MAC
