# ASUSWRT / ASUSWRT-Merlin 适配说明

本页描述 ASUSWRT / ASUSWRT-Merlin 平台的社区诊断边界。当前真实参考样本是 **ASUS RT-AX86U / Merlin-KoolShare 388.11**。

## 当前参考样本

- Device: ASUS RT-AX86U
- Firmware family: ASUSWRT-Merlin / KoolShare modified build
- Architecture: AArch64
- Official UU channel observed: `static-asuswrt`
- Historical verified backend version: `v14.6.24`
- Persistent UU directory: `/jffs/uu`
- Runtime directory: `/tmp/uu`
- Monitor: `/jffs/uu/uuplugin_monitor.sh`

> `v14.6.24` 是 2026-08-29/30 实机验证时的历史版本。项目代码必须通过网易官方 API 获取当前包，不应把历史版本写死成安装目标。

## “华硕自带 UU”与实际 uuplugin 的关系

RT-AX86U 固件里的「网易 UU 加速器」页面属于 ASUSWRT 的集成入口。页面本身不是实际运行二进制；真正的 `uuplugin` 由网易官方后端动态下发。

因此：

```text
ASUSWRT UU 管理入口
        ↓
网易官方服务
        ↓
当前平台插件包
        ↓
/jffs/uu 持久组件
        ↓
/tmp/uu 运行组件
```

不能仅凭前端页面年代判断实际插件版本。

## 当前只读工具

### 平台检测

```sh
sh platforms/asuswrt/detect.sh
```

检测内容包括：

- `nvram` 与 `productid`；
- CPU 架构；
- firmware/build 标识；
- `sw_mode`；
- `/jffs`；
- KoolShare 环境；
- `/jffs/uu` 和 `/tmp/uu` 是否存在。

不会修改 NVRAM、JFFS、进程或防火墙。

### UU 健康检查

```sh
sh platforms/asuswrt/health.sh
```

检查：

- monitor；
- `uuplugin`；
- `xuplugin-guardian`；
- 网易 `:16000` 控制连接；
- 当前版本；
- MC2/Clash 是否同时在线（仅作参考，不作为 UU 健康判据）。

## RT-AX86U 已验证的 WOL-only 共存事实

在当前参考样本中，网易 UU 后端在线但**没有给任何设备开启 UU 游戏加速**时，已实测：

- `uuplugin` 在线；
- `xuplugin-guardian` 在线；
- `:16000` ESTABLISHED；
- MC2 的 Clash 进程继续在线；
- MC2 的既有 TCP/UDP 透明代理核心状态未被 UU 待机模式破坏。

因此当前项目把这两种场景严格分开：

```text
WOL-only / idle
  → 已有真实共存参考样本

UU game acceleration + MC2
  → 可能争用 TProxy / NAT / fwmark / policy routing
  → 不属于当前兼容承诺
```

## 为什么 ASUSWRT 不直接复用 XiaoQiang installer

两者的持久化模型明显不同：

```text
XiaoQiang / RB06
  /userdisk/appdata + /data + UCI firewall include

ASUSWRT / RT-AX86U
  /jffs/uu + /tmp/uu + ASUS/KoolShare startup integration
```

所以设备型号只进入 profile，真正安装逻辑必须由不同 platform adapter 实现。

## 安装/恢复策略

ASUSWRT 的设计已经明确：**官方集成优先，不提供 Generic ASUSWRT 覆盖式 installer。**

默认行为是：

1. 检测厂商/固件是否已有网易 UU 官方入口；
2. 已有官方入口时，只提供 `detect / health`、版本/云连接诊断和故障信息采集；
3. 不因为能访问 `/jffs` 就覆盖官方 `/jffs/uu`；
4. 不用 Generic OpenWrt 或 XiaoQiang 的安装方式替换 ASUSWRT 自带生命周期管理；
5. 只有未来出现“某个明确型号的官方组件损坏、且已有可回滚实机证据”时，才单独增加 model-specific recovery adapter。

这不是功能缺失，而是项目安全边界：对于本来就受官方支持的设备，最稳妥的实现就是尽量不接管厂商已经维护的安装/升级路径。

## 当前状态

ASUSWRT 当前开放只读 `detect / health`，并把“官方集成优先、默认不覆盖”作为正式平台策略。

RT-AX86U 现在已经补齐手机移动数据 Remote WOL 实测证据：在 iStoreOS UU 停止、AX86U UU 单独在线时，不重新扫码、不重新配置 PC，手机关闭 Wi-Fi、仅使用移动数据即可成功远程开机。随后在 AX86U 与 iStoreOS UU 同时在线的 C 实验中，LAN 抓包又明确捕获到由 AX86U 发出的 UDP/9 Magic Packet 与 EtherType `0x0842` 原生 Magic Packet，目标主机随后上线。

因此 RT-AX86U 在当前样本中可以升级为 **Remote WOL Verified**。但该结论仍只覆盖当前参考型号/固件样本，不代表所有 ASUSWRT/ASUSWRT-Merlin 设备自动获得 Verified。
