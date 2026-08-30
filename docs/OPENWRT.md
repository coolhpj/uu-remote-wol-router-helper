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
