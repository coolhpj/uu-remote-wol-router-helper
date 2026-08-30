# Generic OpenWrt 适配说明

本页描述标准 OpenWrt / OpenWrt 衍生固件的**只读诊断层**。它不是“所有 OpenWrt 都已经支持 UU Remote WOL”的承诺。

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

测试后临时 UU 已停止，未写 UCI/`/overlay`；OpenClash 仍在线，`XU_*` 临时 nftables 表无残留，`ip rule`、`ip route` 与归一化后的 nft ruleset 均恢复到测试前结构。iStoreOS 因此已经证明可以运行网易官方 x86_64 UU 后端，但**持久安装、reboot、UU App 辅助设备识别和 Remote WOL 仍未验证**。

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

## 当前状态：Experimental Diagnostics

Generic OpenWrt 目前只说明：

> “我们能识别这是 OpenWrt，并能安全采集 UU 运行状态。”

它**不代表安装器已验证**。

Private Draft 已加入 `platforms/openwrt/smoke-test.sh`，但**暂时没有接入 `uu-helper.sh`**。它默认禁用、只允许 `/tmp/uu-wol-helper-*` staging、要求 root + staging/MD5/channel 全部匹配；如果设备上已经存在任何 UU runtime，直接拒绝，不尝试停止或替换。只有真实临时 runtime 同时满足 `uuplugin + guardian + :16000 ESTABLISHED`，并在停止后确认没有 UU 进程或 `XU_*` firewall 残留，才允许写入与 staging MD5 绑定的 smoke-pass 证据。

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
