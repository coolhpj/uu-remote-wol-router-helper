# UU Remote WOL Router Helper

> 非官方社区项目 / Unofficial community project. Not affiliated with NetEase.

让具备常在线能力的路由器成为 **网易 UU远程（UU Remote）Wake-on-LAN 辅助设备**，并把不同品牌、不同固件的安装与诊断过程拆成可维护的“通用核心 + 平台适配器 + 设备兼容档案”。

> 当前仓库仍处于 **Private Draft / 私有草稿阶段**。在完成代码审计、脱敏、第二设备复现与公开文档复核之前，不建议对外发布。

## 已经真实验证的起点

本项目来自一次真实的 Redmi AX6000 / RB06 排障与移植过程，最终完成了：

```text
手机移动数据
    ↓
网易 UU 云端
    ↓
Redmi AX6000 / RB06 上的 uuplugin
    ↓
局域网 Magic Packet
    ↓
关机 PC 开机
```

Redmi AX6000 / RB06 已完成真实冷启动、UU 云连接以及手机移动数据远程开机终验。

同时，ASUS RT-AX86U（Merlin-KoolShare / ASUSWRT 系）已作为第二种平台样本完成网易 UU `static-asuswrt` 通道、自启动与代理共存边界研究。它与 XiaoQiang/OpenWrt 的安装机制不同，因此本项目不会采用“每个型号复制一套脚本”的方式维护。

## 项目目标

本项目希望解决的是：

> 当某台路由器理论上具备运行网易 UU 路由插件的条件，但官方入口缺失、插件过旧、持久化机制不同，或者需要诊断 UU远程 WOL 辅助设备状态时，提供一个可验证、可回滚、可扩展的社区适配框架。

不是：

- 破解路由器获取 root；
- 绕过厂商安全机制开启 SSH；
- 分发网易闭源二进制；
- 保证所有路由器都能安装；
- 把“进程启动”当成“UU远程可用”。

## 当前安全入口

Private Draft 阶段先开放诊断与临时 staging，不提供正式安装：

```sh
sh uu-helper.sh diagnose
sh uu-helper.sh collect-info
sh uu-helper.sh check-api openwrt-aarch64
sh uu-helper.sh preflight
sh uu-helper.sh stage openwrt-aarch64
```

`diagnose / collect-info / check-api / preflight` 都是只读操作。当前 `preflight` 只针对 XiaoQiang adapter，检查平台、AArch64、非 AP 模式、必需工具、`/tmp` 可写和空间阈值。`stage` 只在 `/tmp/uu-wol-helper-*` 下下载、MD5 校验、检查 tar 路径并解压官方包；它不会停止/启动 UU 进程，也不会修改持久目录或注册自启动。

`diagnose` 会依次匹配已知平台 adapter。当前 **XiaoQiang** 与 **ASUSWRT / ASUSWRT-Merlin** 都已有只读检测/健康检查；未知平台只进入 `collect-info`，不会猜测型号或执行安装。

当前诊断退出码：

- `0`：已识别平台且当前 UU 健康检查通过；
- `1`：已识别平台，但插件未检测到或健康状态需要处理；
- `2`：尚无匹配 adapter，仅输出只读环境报告；
- `64`：命令参数无效。

当前版本**没有 `install` 命令**。

## 使用前提：SSH / Shell 权限

### 官方已经支持 UU WOL 的路由器

如果厂商固件已经通过官方入口支持网易 UU远程，请优先使用官方方法。通常**不需要为了使用 UU远程而额外开启 SSH**。

网易官方支持型号/路由器 WOL 插件说明：<https://www.uuremotepro.com/faq-article?id=wol-plugin>

### 使用本项目手动适配时

本项目的手动安装、平台检测、诊断和持久化功能通常需要：

- SSH 或等效 Shell 管理权限；
- 足够的系统权限（通常为 root）；
- 可写的持久存储区域。

本项目**不提供破解、漏洞利用或绕过设备安全限制来开启 SSH/root 的教程**。

请优先查阅：

1. 设备厂商官方文档；
2. 所使用固件项目的官方文档；
3. 本仓库 `docs/COMPATIBILITY.md` 中已验证设备的说明。

## 为什么不是“一个万能 install.sh”

不同路由器真正不同的是：

- 固件家族；
- CPU 架构；
- 网易插件下载通道；
- 持久存储位置；
- 自启动机制；
- UCI / NVRAM / procd / init / firewall 行为；
- iptables / nftables 与现有透明代理的关系。

因此项目采用：

```text
                Common Core
                    │
      ┌─────────────┼─────────────┐
      │             │             │
  XiaoQiang      ASUSWRT       OpenWrt
  Adapter         Adapter       Adapter
      │             │             │
  Device Profile Device Profile Device Profile
```

型号只是设备档案；真正决定安装流程的是平台适配器。

## 当前平台状态

| Router | Platform | UU Channel | Install | Reboot | UU Cloud | Remote WOL | Status |
|---|---|---|---:|---:|---:|---:|---|
| Redmi AX6000 / RB06 | XiaoQiang / OpenWrt-derived | `openwrt-aarch64` | ✅ | ✅ | ✅ | ✅ | **Verified** |
| ASUS RT-AX86U | ASUSWRT / Merlin-KoolShare | `static-asuswrt` | ✅ | ✅ | ✅ | ⚠️ | Platform reference |
| Generic OpenWrt | OpenWrt | TBD by architecture | 🚧 | 🚧 | 🚧 | 🚧 | Planned |
| Other vendors | Vendor firmware | Unknown | ❓ | ❓ | ❓ | ❓ | Community research |

> `Remote WOL = ✅` 只用于已经有真实远程开机证据的设备。不会因为插件能启动就标记兼容。

完整矩阵见 [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)。SSH/root 使用边界见 [`docs/SSH-ACCESS.md`](docs/SSH-ACCESS.md)。XiaoQiang 适配说明见 [`docs/XIAOQIANG.md`](docs/XIAOQIANG.md)，ASUSWRT 参考适配见 [`docs/ASUSWRT.md`](docs/ASUSWRT.md)。

## 成功标准

本项目把“成功”拆成多个层级：

1. 平台识别成功；
2. 官方插件下载与校验成功；
3. 插件可以启动；
4. 真实重启后可以自动恢复；
5. UU 云控制连接健康；
6. UU主机加速 App 能正确识别路由器；
7. UU主机加速 App 与 Windows UU远程处于正确的同账号关系；
8. 每台 PC 单独完成远程开机配置；
9. 手机关闭 Wi‑Fi、仅使用移动数据完成真实远程开机。

只有最后一层完成后，设备档案中的 `Remote WOL` 才会标记为 `Verified`。

## 本项目已经踩过的三个关键坑

### 1. 进程存在 ≠ UU 云在线

曾出现 UU 进程全部存在，但 `:16000` 没有建立控制连接。最终自启动必须验证真实云连接，而不是只看 PID。

### 2. 云在线 ≠ UU远程已经绑定辅助设备

路由器插件在线以后，UU远程仍可能提示没有辅助设备。

本次真实案例最终确认：**UU主机加速 App 与 Windows UU远程需要处于正确的同账号关系。**

### 3. 同一个 UU账号 ≠ 所有 PC 自动继承 WOL 配置

每台 PC 都必须分别完成一次自己的远程开机配置与网卡/WOL绑定。

## Redmi AX6000 / RB06 已验证实现

当前历史终验版本使用网易官方：

```text
openwrt-aarch64 v14.6.24
```

正式插件目录：

```text
/userdisk/appdata/2882303761518031252
```

持久辅助脚本：

```text
/data/uu-v14/auto.sh
```

最终使用 XiaoQiang 可持久的 UCI firewall include，而不是 `/etc/rc.local`。

> 版本号仅用于说明历史验证环境。正式安装器不应写死版本，而应运行时查询网易官方当前版本并进行官方校验。
>
> 当前网易 API 返回 `status / md5 / url / url_bak` 等字段，并不保证提供独立的 `version` 字段；项目从官方 URL 路径中提取展示版本，但下载与校验逻辑以 API 返回的 URL 与 MD5 为准。

## ASUS RT-AX86U 平台样本

RT-AX86U 样本来自 Merlin-KoolShare / ASUSWRT 系环境。

已研究：

- ASUS 固件中的网易 UU 官方入口；
- `static-asuswrt` 当前插件通道；
- `/jffs` 持久化环境；
- UU 后台/WOL 待机与 MC2 透明代理可以并存；
- 一旦对特定 PC 真正开启 UU 游戏加速，策略路由可能影响该 PC 原本依赖 MC2 的代理连接。

因此：

> **WOL-only 与 UU 游戏加速是两个不同使用场景。**

本项目 v1.0 目标优先保证 WOL 辅助设备能力，不承诺 UU 游戏加速与所有透明代理方案同时工作。

## 仓库不会包含网易闭源二进制

计划中的正式安装器只保存我们的：

- 平台检测；
- 官方下载逻辑；
- 完整性校验；
- 持久启动；
- 状态检查；
- 诊断；
- 卸载/回滚；
- 设备适配数据。

不会把网易 `uuplugin`、`xuplugin-guardian`、`xtables-nft-multi` 等闭源文件直接提交到仓库。

## 未知路由器如何加入支持

仓库已经提供第一版只读 [`scripts/collect-info.sh`](scripts/collect-info.sh)。

在已经合法取得 SSH/root Shell 的路由器上，可以先执行：

```sh
sh collect-info.sh
```

也可以先把脚本内容复制到路由器后运行。脚本只输出平台识别所需信息，不修改路由器配置，并刻意避免采集公网地址、网卡地址、设备序列信息、拨号凭据、账号与 Token 等字段。提交报告前仍建议人工复核一次。

未知设备默认只允许：

```text
Detect → Collect → Redact → Report
```

而不是：

```text
Unknown → Guess → Install
```

收集报告必须默认隐藏 WAN IP、MAC、SN、PPPoE、账号、Token、设备验证码等敏感数据。

## 计划目录

```text
uu-remote-wol-router-helper/
├── README.md
├── SECURITY.md
├── CONTRIBUTING.md
├── devices/
├── lib/
├── platforms/
├── scripts/
├── tests/
├── docs/
└── .github/
```

当前私有草稿阶段先固定架构和验证标准，再实现会修改路由器的安装器。

## 项目背景与 AI 使用说明

本项目始于一次真实设备问题排查，并大量借助 AI 辅助分析、代码生成、证据整理和文档编写。

项目维护者并非专业软件开发人员。因此我们采用一个很简单的原则：

> **Verified（已验证）必须来自真实硬件证据，不能来自 AI 推测。**

任何 AI 生成代码在进入公开安装路径前，都应经过人工审阅、静态检查、可回滚设计和真实设备测试。

## 当前状态

**Private Draft / 私有草稿。**

下一阶段：

- [x] 抽象通用项目结构
- [x] 建立已验证设备分层标准
- [x] 明确 SSH/root 安全边界
- [x] 建立首批设备兼容档案
- [x] 完成只读 collect-info 第一版
- [x] 完成网易 API 解析 + MD5 校验基础模块
- [x] 完成 XiaoQiang 只读 detect/health
- [x] 完成统一 `uu-helper.sh` 安全入口
- [x] 完成官方包下载 / MD5 / staging 链
- [x] 完成 XiaoQiang 只读 preflight
- [ ] RB06 实机复验临时 smoke-test（保护壳与自动恢复逻辑已完成）
- [ ] 重写 XiaoQiang 持久安装 adapter
- [x] 完成 ASUSWRT reference adapter 的只读 detect/health
- [ ] 设计 ASUSWRT 安装/恢复 adapter（官方集成设备优先，不默认覆盖）
- [x] 第一轮敏感信息扫描（公开前需再次扫描）
- [ ] 从原始证据中挑选并脱敏 README 图片
- [ ] 第二环境复现
- [ ] Private review
- [ ] Public release
