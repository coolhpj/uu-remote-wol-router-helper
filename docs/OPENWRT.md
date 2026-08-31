# Generic OpenWrt 适配说明

本页描述标准 OpenWrt / OpenWrt 衍生固件的分层 adapter。它已经包含只读诊断、临时 smoke-test 和受控 persistence 代码，但这仍然不是“所有 OpenWrt 都已经支持 UU Remote WOL”的承诺。

## 为什么单独做 Generic OpenWrt adapter

项目已经有：

- XiaoQiang adapter：小米/Redmi 特有持久化与 UCI 行为；
- ASUSWRT adapter：`/jffs` + ASUS/KoolShare 集成；
- Generic OpenWrt adapter：用于其它标准 OpenWrt / iStoreOS / 厂商 OpenWrt 衍生环境的安全识别和诊断。

匹配顺序是：

```text
XiaoQiang
   ↓ 未匹配
ASUSWRT
   ↓ 未匹配
Generic OpenWrt
   ↓ 未匹配
Unknown → collect-info only
```

因此 XiaoQiang 即使带有 `/etc/openwrt_release`，也不会被 Generic OpenWrt 抢走。

## 官方 x86_64 通道与 iStoreOS 第二环境

2026-08-30 已通过网易官方 API 确认存在 `openwrt-x86_64` 通道，当前返回 **v14.6.22**。项目已经在真实 iStoreOS 24.10.7 / x86_64 上完成 API、MD5、tar、`/tmp` staging 和临时 runtime smoke-test：`uuplugin + xuplugin-guardian + :16000 ESTABLISHED` 在约 2 秒内同时通过。

随后完成了完整功能链实验：手机默认网关切到 iStoreOS 后，UU主机加速将其识别并绑定为 OpenWrt；Windows 默认网关同样指向 iStoreOS，暂停同账号下 AX86U 的 UU runtime 后，UU远程辅助设备页面从“华硕路由器”切换为通用“路由器”，继续配置后最终在手机关闭 Wi‑Fi、仅使用移动数据时成功唤醒 Windows。

上述最初的临时 runtime 阶段结束后，UU 被停止并清理，OpenClash、`ip rule`、`ip route` 与归一化后的 nft ruleset 均恢复到测试前结构。之后项目又继续完成了真实 `/overlay` 持久安装、真实 reboot 后 procd 自动恢复、多辅助设备 A/B/C 对照，以及正式 rollback + rollback 后再次 reboot 的恢复验收。

## 平台预检与官方通道自动选择

```sh
sh uu-helper.sh preflight
```

Generic OpenWrt 当前只对已经真实确认过网易官方 API 的架构做自动映射：

- `aarch64` / `arm64` → `openwrt-aarch64`
- `x86_64` / `amd64` → `openwrt-x86_64`

其它架构 fail closed，不猜测通道名。ASUSWRT 也不会被通用 `stage auto` 接管，因为它属于官方/model-specific 集成路径。

2026-08-30 已在真实 iStoreOS 24.10.7 / x86_64 上运行预检，自动解析为 `openwrt-x86_64` 并通过工具、root、`/tmp` 空间检查，全程无持久修改。

## 当前只读检测

```sh
sh platforms/openwrt/detect.sh
```

读取：

- `/etc/openwrt_release`；
- CPU 架构；
- `/tmp/sysinfo/model` / `board_name`；
- `uci / ubus / opkg` 是否可用；
- `/overlay` 是否存在。

不会写 UCI、不会执行 `opkg install`、不会改 firewall。

## 当前健康检查

```sh
sh platforms/openwrt/health.sh
```

会尝试识别常见 UU 目录，并分别报告：

- `uuplugin`；
- `xuplugin-guardian`；
- monitor（仅信息项）；
- `:16000` 云控制连接；
- iptables / nftables 后端。

Generic OpenWrt **不强制 monitor 必须存在**，因为标准 OpenWrt 设备未来可能用 procd/init 管理服务，而不是 XiaoQiang 的 monitor wrapper。

## 当前状态：Generic Adapter + Verified iStoreOS Sample

Generic OpenWrt 已经不再只是只读诊断：真实 iStoreOS x86_64 已完成 detect / preflight / stage / 临时 runtime / UU 云连接 / UU账号绑定 / 手机移动数据 Remote WOL 功能终验、真实 `/overlay` 持久安装、真实 reboot 后 procd 自动恢复、正式 rollback，以及 rollback 后再次 reboot 的恢复验收。因此**当前 iStoreOS x86_64 样本可标为 Verified**；但 Generic OpenWrt adapter 本身仍然是逐设备验证模型，不能把该结果外推到所有 OpenWrt。

Private Draft 已加入 `platforms/openwrt/smoke-test.sh`，但**暂时没有接入 `uu-helper.sh`**。它默认禁用、只允许 `/tmp/uu-wol-helper-*` staging、要求 root + staging/MD5/channel 全部匹配；如果设备上已经存在任何 UU runtime，直接拒绝，不尝试停止或替换。只有真实临时 runtime 同时满足 `uuplugin + guardian + :16000 ESTABLISHED`，并在停止后确认没有 UU 进程或 `XU_*` firewall 残留，才允许写入与 staging MD5 绑定的 smoke-pass 证据。

### 持久化 adapter 草稿

当前 Private Draft 已加入：

- `platforms/openwrt/install.sh`
- `platforms/openwrt/rollback.sh`
- `platforms/openwrt/uninstall.sh`
- `platforms/openwrt/runtime/uu-wol-helper.init`
- `platforms/openwrt/runtime/run.sh`

设计采用标准 OpenWrt 持久层，而不是复制 XiaoQiang 的 `/data + firewall include`：

```text
/usr/lib/uu-wol-helper/      官方 staged runtime + install.meta
/etc/init.d/uu-wol-helper    procd 服务
/etc/uu-wol-helper/backups/  安装前备份与回滚状态
```

真实写入前必须同时满足：OpenWrt preflight、官方 package MD5/结构复核、架构与 channel 匹配、以及同一 staging MD5 对应的 `smoke-pass`。安装脚本默认禁用；服务 `enable/start/health` 任一步失败会尝试自动 rollback。卸载脚本只删除带本项目 ownership marker 的文件，避免误删其它 UU 实现。

2026-08-30 已在 fake-root 环境完成旧目录/旧 init 备份、安装、rollback 恢复、陌生文件拒删、fresh install + uninstall 的自动回归。随后又把同一套脚本原样送入真实 iStoreOS 24.10.7 的 BusyBox 用户态，仅在 `/tmp` fake-root 中复验，结果同样全部通过并已清理。真实 iStoreOS 也确认：`/usr/lib` 与 `/etc/init.d` 都由 `/overlay` 持久化，`rc.common/procd/rc.d` 可用，约 1.6 GiB 可用空间，三个目标路径安装前无冲突。

随后已完成真实持久安装：`/usr/lib/uu-wol-helper`、`/etc/init.d/uu-wol-helper` 与 `/etc/uu-wol-helper` 已写入，procd `S95/K10` 已 enable；官方 `openwrt-x86_64 v14.6.22` 在安装后约 2 秒达到 `uuplugin + guardian + :16000 ESTABLISHED`，OpenClash 同时保持在线。安装前备份 manifest 记录 `had_install=no / had_init=no / previous_enabled=no`。之后执行真实 reboot，iStoreOS 在 `up 0 min` 时已确认重新上线，UU 服务自动恢复为 `uuplugin + guardian + :16000 ESTABLISHED`，OpenClash 核心随后正常恢复，原有上游默认路由保持不变。

随后实机执行当前仓库正式 `rollback.sh`，返回 `ROLLBACK_OK`：`/usr/lib/uu-wol-helper`、`/etc/init.d/uu-wol-helper` 与 `S95/K10` 均被清除，`last-backup` 消失并写入 `last-rollback`。再次 reboot 后，项目 UU runtime 没有反弹，OpenClash 恢复 running，默认路由保持原上游，网易 API 连通正常。当前样本保留在 rollback 后干净状态。

### 多个同账号 UU 路由器同时在线的实测现象

本样本同时存在 AX86U 与 iStoreOS 两个已绑定同一 UU 账号的路由器 runtime。实测中，即使手机和 Windows 默认网关都已指向 iStoreOS，只要 AX86U UU 仍在线，UU远程辅助设备页面仍显示“华硕路由器”；临时暂停 AX86U UU 后，页面切换为通用“路由器”，随后 iStoreOS 完成了移动数据 Remote WOL 终验。

A/B/C 对照现已全部完成：A=iStoreOS-only 成功，B=AX86U-only 且不重新配置 PC 也成功；C 在两者同时在线时进行 LAN 抓包，明确捕获到 AX86U 发出的 UDP/9 Magic Packet 与 EtherType `0x0842` 原生 Magic Packet，目标主机随后上线；同一窗口未观察到 iStoreOS 发出对应 WOL 广播。

这只记录当前样本行为，不把它写成网易官方的固定优先级规则。多路由器环境排障时，应把“同账号下其它 UU 路由器是否同时在线”列为一个重要变量。

在给某台 Generic OpenWrt 开放安装前，仍要确认：

1. 精确架构与网易官方 channel；
2. 官方包结构；
3. 持久目录；
4. init/procd 自启动；
5. firewall backend；
6. 回滚方式；
7. 真实 reboot；
8. UU App / 账号绑定；
9. 手机移动数据 Remote WOL 实测。

未知型号不能因为“同样是 AArch64 OpenWrt”就自动套用 RB06 的 `/data + firewall include` 方案。
