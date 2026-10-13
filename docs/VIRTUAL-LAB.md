# 虚拟设备实验室 / Virtual Router Lab

## 目标与边界

本项目不采购所有品牌路由器。自动测试由三层组成：

1. **每次提交必跑**：Shell（命令脚本）、安全门、平台识别、资源边界和九品牌档案的模拟数据回归。
2. **独立 QEMU（硬件模拟器）任务**：官方 OpenWrt x86_64 和 MIPS Malta 小端镜像的 SHA256 校验、启动及架构/系统识别。独立暂存测试由 GitHub 宿主机查询网易官方 API、下载及初次 MD5 校验，然后经**宿主机仅本地开放的文件服务**传输到模拟的 OpenWrt 客户机；客户机独立再次校验 MD5、解压、清理。此步骤**不启动网易插件，也不安装到闪存，不验证虚拟机对外访问网易服务器**。原有 ARM64 七阶段实验室独立保留。
3. **用户自愿实机测试**：真实硬件上的 SSH、持久安装、重启恢复、网易账号绑定和手机移动数据 WOL（网络唤醒）。只有这一层完成相应终验才能升级设备兼容状态。

QEMU Malta **不是** Lenovo Y1/MT7620，也不是 TP-Link、网件等具体路由器；x86 虚拟机亦不等于全部 iStoreOS 设备。九品牌 TSV 只是访问途径/证据等级模拟，**不运行任何厂商闭源固件**。

## 当前工作流

- `.github/workflows/ci.yml`：常规回归，含 `tests/test-resource-advice.sh` 及 `tests/test-brand-fixtures.sh`。
- `.github/workflows/qemu-cross-arch.yml`：x86_64、MIPS Malta little-endian 官方镜像的独立启动门与**两阶段网易原包暂存门**。为避免耗费资源，只在相关路径变更、对应 PR（合并请求）或人工运行时触发。宿主机运行 `prepare-official-stage.sh`：通过官方 API 获取当前版本，原 HTTP（明文）下载地址仅升级为**同一主机、相同路径**的 HTTPS（加密），校验 MD5 及归档结构。再在宿主机回环地址启动短期只读文件服务，虚拟机从 QEMU 网关访问本地文件；再次核验 MD5、解压和清理。这个内网中转不是第三方镜像，也不能证明客户机直连网易服务器。任何下载或校验失败都不允许通过。**MD5 是完整性比对，不等于独立数字签名。**
- `.github/workflows/qemu-arm64.yml`：保留现有完整 ARM64 实验室，不改变其安全边界。

跨架构镜像锁定 OpenWrt **25.12.5**，下载前后验证下列官方 SHA256，版本变更必须同时更新镜像名称与可信校验值：

- x86_64 `generic-ext4-combined.img.gz`: `23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461`
- MIPS Malta little-endian `vmlinux-initramfs.elf`: `a2aec5d5bd31d411511fd799f936ea0c3d9a878dbc4b2729c600d3f3953931ca`

镜像来源：`https://downloads.openwrt.org/releases/25.12.5/targets/` 下的 `x86/64`、`malta/le` 目录。

## 资源预算的保守计算

`lib/resource-advice.sh` 只对输入的 **KiB 容量快照**给出候选策略，不负责采集真机数据，不连接路由器，也不允许安装：

- 检查 `/tmp` 最低估算：原压缩包 + 解压大小 + 8 MiB 临时预留。
- 检查闪存双版本更新预算：两份原包或两份解压文件 + 4 MiB 系统预留。
- 额外内存消耗（UU进程堆、内核、网络等）无法仅从文件体积估算，输出明确为 `runtime_ram_verified: no`。
- 容量不足、数据缺失或格式错误时拒绝乐观判断，**任何情况下 `install_authorized: no`**。

例如 Lenovo Y1（报告剩余 flash 7900 KiB、临时空间 50304 KiB，官方压缩包约 2726 KiB、解压约 7591 KiB）的结果是 `ram_download_candidate`：仅容量层建议优先内存下载运行，绝非实机运行认证。

## 九品牌筛选档案

`labs/device-fixtures/brands.tsv` 只列研究优先级、可进入系统的途径和证据等级。明确排除华为主动适配。未知或研究中的品牌 **必须**为 `collect_only`（只读收集）；不能由厂商名称直接推断支持 SSH（安全远程登录）、root 权限或网易插件安装。

模拟测试通过时请标记为 **Virtual only（仅虚拟环境通过）**；新 x86/MIPS 暂存门通过仅说明 GitHub 宿主机取得官方原包、虚拟机通过本地中转取得并校验解压该包，**不代表虚拟机拥有稳定外网、二进制已启动或能够云绑定**。只有设备独立完成重启、回滚、真实云绑定及移动数据远程唤醒的实机证据，才允许按 `docs/COMPATIBILITY.md` 的规则更改状态。

## 社区贡献

优先使用仓库 `New Router Support`（新设备支持）问题模板提交具体型号、固件版本、只读脱敏报告；不要上传 SSH 密码、WAN IP（公网地址）、MAC、序列号、令牌或完整防火墙配置。涉及安装或重启须由持有人在本地逐步确认，项目不远程接管陌生用户设备。
