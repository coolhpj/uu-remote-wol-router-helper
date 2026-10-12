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
- `mipsel_24kc`（需 `uname -m` 为 `mips/mipsel`、OpenWrt `DISTRIB_ARCH` 与 `opkg print-architecture` 一致）→ `openwrt-mipsel`，**仅实验性支持；Lenovo Y1 已有临时远程唤醒成功证据，不代表所有同架构设备可永久安装**

MIPS 当前不接受泛化的 `mips` / `mipseb` 自动推断；真实设备持久安装仍被拦截。[Issue #1](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1) 的 Lenovo Y1 / MT7620A 已通过预检、官方包校验与临时启动。2026-10-12 测试者在手机网易 UU 主机加速器中找到并绑定「合作款路由器」后，已报告手机移动数据远程唤醒电脑成功；之前未绑定时的失败不再代表当前功能状态。**持久安装、重启自启动和回滚仍未验证，不标记完整 Verified。**

2026-10-09：NAS 侧官方 `openwrt-mipsel v14.9.4` 归档已通过 API MD5、tar 解压；三个可执行文件均为 ELF32（32 位）/ little-endian（小端）/ MIPS32r2，无动态加载器或外部共享库依赖。新增 `lib/elf.sh`：在下载解压后的 MIPS staging 与临时运行前再次验证 3 个 ELF 文件格式，防止误执行其它架构或 ISA 的包。**上述仅证明格式/依赖可接受，不代表真机启动、内核/防火墙兼容、云连接或 Remote WOL 验证通过。**

2026-10-10：Lenovo Y1 用户首次在设备上尝试 staging，网易 API、MD5、归档与解压均通过，但预检显示 `missing_tools: od`，旧版 ELF 检查将“读取工具缺失”误报为 `MIPS ELF format/ISA mismatch`。现已修改为支持 `od`、`hexdump` 或 BusyBox 的 `hexdump` applet；均不可用时，在 staging 下载前清楚拒绝而不是误报二进制不兼容。需先确认该固件具备至少一个读取工具，才能继续核验；绝不因此直接运行或安装插件。

2026-10-11：Lenovo Y1 已在真机通过 `preflight` 与 `stage auto`，包括 `md5_check`、`archive_check`、`extract_check`、`mips_elf_check` 和 `STAGE_READY`。下一门为**只读运行环境审查**，不是已经可执行 UU 插件。通用 `smoke-test.sh` 对 `mipsel_24kc` 明确拒绝启动（退出码 67），因为旧清理代码按进程名结束，且不能完整保存/恢复防火墙状态；设备继续执行 `sh platforms/openwrt/mips-runtime-readiness.sh` 仅获取防火墙/进程/网络工具和 staged 文件验证摘要，无插件启动及持久修改。

### Lenovo Y1：自愿试用的持久启动方案（尚待真机验收）

2026-10-12 测试者反馈 `/overlay` 剩余 **7900 KB**，已不足以稳妥保存解压后约 7.8 MB 的全部官方插件。新版实验性方案只在闪存中保存少量开源启动/校验脚本及 `procd`（服务管理器）入口；每次开机联网后重新从网易官方获取并校验插件，解压到 `/tmp` 内存运行。联网失败或官方包校验不通过时不会启动插件，路由器基本联网功能不依赖它。

**这是 Lenovo Y1 / ramips/mt7620 限定的自愿试用，不等于已完成实机重启及稳定性验收。** 通用 MIPS 安装禁令不变。执行前必须有本地恢复能力、已备份设置、确认临时测试清理完毕；本方案可能在终止时调用 `fw4 reload` 重新加载防火墙，短暂中断网络。不要在有其他网易 UU 插件进程的路由器上直接接管。

先在最新代码已传至路由器且临时实验已结束时验证官方暂存文件：

```sh
sh uu-helper.sh preflight && sh uu-helper.sh stage auto
```

出现 `STAGE_READY` 后，**只有明确接受实验风险的 Lenovo Y1 测试者**可执行以下独立安装命令：

```sh
UU_MIPS_BETA_INSTALL_CONFIRM=I_ACCEPT_LENOVO_Y1_EXPERIMENTAL_PERSISTENCE sh platforms/openwrt/mips-experimental-install.sh
```

脚本核对准确路由器型号、MIPS 架构、官方包完整性及至少 2048 KB 闪存空闲空间；拒绝覆盖已有同名服务，闪存内不保存官方闭源插件可执行文件。安装只表示启用了实验服务，**必须真实重启并通过手机移动数据再次唤醒电脑**才算实际验证成功。若官方 API/下载源不可用，重启后可能无法远程唤醒。

明确的卸载命令（仅删除本项目专用文件；进程及防火墙清理不成功时拒绝卸载）：

```sh
UU_MIPS_BETA_UNINSTALL_CONFIRM=REMOVE_LENOVO_Y1_BETA_SERVICE sh platforms/openwrt/mips-experimental-uninstall.sh
```

此试用服务只支持自愿参与测试，不向其他 MIPS 机型自动开放；不要公开原始插件日志、完整防火墙规则、账号或设备标识。

### Lenovo Y1：永久安装前的只读容量检查

Lenovo Y1 真实临时远程唤醒已成功，但**当前尚不提供 MIPS 永久安装**。该机的板载闪存很小，`/tmp` 中能够解压运行不代表 `/overlay` 的可写空间足以存放插件，也不代表可以安全地备份和回滚。在现有 `/tmp` 官方暂存包仍在的情况下，可运行只读检查：

```sh
sh platforms/openwrt/mips-persist-capacity.sh
```

脚本仅查询 `/overlay` 剩余空间和暂存文件大小，输出 `direct_install_budget: capacity_only_enough / insufficient / unknown`，并**始终输出 `decision: do_not_install`**；数字只作容量初筛，不授权安装。如 `/tmp` 暂存已因路由器每日重启清空，无需专门重新下载插件，现阶段仅执行 `df -k /overlay` 查看空闲空间即可。不得公开粘贴完整防火墙、账号或设备标识。

持久运行的开机自启动、服务停止进程归属、重启恢复与备份回滚尚未完成 MIPS 实机验收，因此不能用容量检查通过来绕过 `install.sh` 安全门。下一步须根据实机可用存储容量选定直接持久保存或其它方案，并在隔离环境和 Y1 真机分别验证。

### Lenovo Y1 / MIPS：单轮临时运行测试（实验阶段）

2026-10-11 真机只读反馈：使用 `fw4` + `nft`，`netstat` 可用，未发现已有 UU 进程或 XU_ 防火墙表。设备每天自动重启会清空 `/tmp` 临时包，这是正常现象。

本次新增专用 `platforms/openwrt/mips-runtime-smoke.sh`。原通用 `smoke-test.sh` 仍对 MIPS 强制禁止，真实 MIPS 的 `install.sh` 也仍然禁止持久安装。新脚本不是无风险的：会真实运行网易官方闭源二进制；如果检测到防火墙规则变化，退出时可能执行 `fw4 reload`（重新加载防火墙），造成短暂断网或影响动态规则。**仅限能够直接接触路由器、已备份配置且能本地恢复网络的自愿测试者。**

在最新仓库根目录先执行 `sh uu-helper.sh preflight && sh uu-helper.sh stage auto`，必须出现 `STAGE_READY`。之后仅在具备上述恢复条件时执行：

```sh
UU_MIPS_RUNTIME_CONFIRM=ONE_TIME_MIPS_TEST_WITH_LOCAL_RECOVERY UU_MIPS_RUNTIME_SECONDS=300 sh platforms/openwrt/mips-runtime-smoke.sh
```

进程和网易云连接同时就绪后，使用手机移动网络尝试唤醒待机电脑。测试窗口到时自动停止。Lenovo Y1 首次运行前遇到 `Runtime safety prerequisite missing: nohup`，说明此 OpenWrt 固件没有独立 `nohup`（终端断开后继续运行命令的工具）；脚本已改用 POSIX `sh`（标准命令解释器）自带的忽略挂断信号机制，关闭标准输入并将输出写到独立日志，**无需安装任何额外软件**。启动前会确认看守程序已运行，才允许启动官方插件；新增模拟 SSH 挂断后看守继续执行清理的回归测试。清理仅按本次临时目录下的具体可执行文件识别进程，不使用 `killall`（按进程名批量结束）。若仍有其他 UU 进程或防火墙无法确认恢复，明确打印 `CLEANUP_INCOMPLETE`，保留锁和快照以便本地恢复。断电、内核异常、强制结束整个进程组等仍不能保证自动恢复。

**退出码或云连接成功不等于实际远程唤醒通过。** 回传可公开的标准输出、手机移动数据是否唤醒成功即可；禁止公开贴出 `firewall.before` / `firewall.after`（含隐私的完整防火墙配置）。清理失败不得删除 `mips-smoke.lock`、不得重新执行 stage、不得持久安装。真实设备风险（断电、内核异常、网络中断）不能由脚本完全消除。

2026-10-12 Lenovo Y1 此前第三轮反馈（历史排障）：主脚本累计 268/290/280 秒时分别提示启动进程退出，且手机端尚未确认出现 Y1 路由器辅助设备。这不能证明闭源插件崩溃；审计发现主循环仅累计 `sleep 2`，漏掉每次扫描 `netstat` 和 `/proc` 的真实耗时，看守也独立计时，因此可能是看守先到期清理。新版主测试和看守统一按 `/proc/uptime` 的同一起点计算经过时间，主测试结束重新探测云端和守护进程；单测模拟扫描耗时、时钟异常以及看守到期即时清理。该项是**测试工具可靠性修复**，不是 Lenovo Y1 设备注册/远程唤醒已解决的证据。当时尚未确认手机路由器绑定；无需优先恢复 IPv6/DNS 或改校园网设置。该诊断仅是历史阶段，不能覆盖后续成功报告。

2026-10-12 新反馈：测试者在限时脚本运行时，通过连接 Y1 Wi-Fi 的手机进入 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器**，成功发现并添加 Y1；随后在手机移动网络下，经「开始协助」和首页两条入口成功远程开机（[原始评论](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1#issuecomment-6122614795)）。测试者表示运行日志与先前相似，**不能据此判定新版脚本完整运行窗口和安全清理验收已通过**。不得以远程唤醒成功为由绕过 MIPS 持久安装安全门；下一阶段需要独立验证安装、重启自启、异常回滚和不影响原防火墙配置。

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

当前实现已加入 `platforms/openwrt/smoke-test.sh`，但**暂时没有接入 `uu-helper.sh`**。它默认禁用、只允许 `/tmp/uu-wol-helper-*` staging、要求 root + staging/MD5/channel 全部匹配；如果设备上已经存在任何 UU runtime，直接拒绝，不尝试停止或替换。只有真实临时 runtime 同时满足 `uuplugin + guardian + :16000 ESTABLISHED`，并在停止后确认没有 UU 进程或 `XU_*` firewall 残留，才允许写入与 staging MD5 绑定的 smoke-pass 证据。

### 持久化 adapter 草稿

当前实现已加入：

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
