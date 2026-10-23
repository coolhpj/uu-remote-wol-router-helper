# 网易 UU 远程开机路由器助手｜OpenWrt 安装、UU 辅助开机

![网易 UU 远程开机路由器助手：设计概览图](docs/images/uu-doc-00-overview.png)

*项目功能概览（设计示意图，不代表任何型号已经通过实际远程唤醒验收）。*

想用**网易 UU 远程开机**，让家里的路由器充当**UU 辅助开机 / 网易 UU 远程辅助设备**，但找不到适合自己固件的**路由器插件**或 **OpenWrt 安装**方法？本项目提供开源的检测、官方插件下载校验和分平台安装引导，帮助你判断路由器是否适合辅助唤醒关机电脑。**不是网易官方插件，也不保证所有路由器可安装或长期在线。**

## 选择适合你的安装方式

| 你打算安装在哪儿？ | 从哪里开始 | 实际验证状态 |
| --- | --- | --- |
| **OpenWrt / iStoreOS 路由器**、小米 / 红米、华硕等 | [五平台路由器测试包](https://github.com/coolhpj/uu-remote-wol-router-helper/releases/tag/v0.1.0-beta.2) · [设备兼容清单](docs/COMPATIBILITY.md) | 按具体设备和固件查看结果，不保证同架构通用 |
| **Debian / Ubuntu / iStoreOS / 飞牛 OS 的 Docker 主机** | [下方 Docker 独立安装步骤](#docker-容器安装实验版) · [详细说明](docker/README.md) | 镜像、插件进程、连接、身份文件及容器重建已在自动测试环境通过；**真实手机流量唤醒待志愿者验证** |

> 本项目不隶属于网易。**路由器原生安装与 Docker 容器安装是两条独立路径，不要混用安装步骤。** 只有手机关闭 Wi-Fi、使用移动数据真正唤醒关机电脑，才算远程开机验证成功。

## 按平台下载（预览测试版，尚非稳定版）

**[点击这里下载 v0.1.0-beta.2 五平台测试版（GitHub Releases 版本发布页）](https://github.com/coolhpj/uu-remote-wol-router-helper/releases/tag/v0.1.0-beta.2)**。已提供五个独立的 ZIP（压缩包）及 SHA256（文件校验清单），无需进入自动构建记录中寻找附件。此版包含通用 OpenWrt 服务停止时防止误停其他 UU 守护进程的安全修复。**当前仍为预览测试版，不要把同架构所有型号当成已验证兼容；MIPS 通用永久安装依然禁止。**

| 包名 | 适用环境 | 安装验证范围 |
| --- | --- | --- |
| `uu-helper-openwrt-x86_64.zip` | OpenWrt / iStoreOS x86_64 | 已验证的仅为当前 iStoreOS x86_64 实机样本 |
| `uu-helper-openwrt-aarch64.zip` | OpenWrt ARM64 | 候选测试包，不保证任意型号可安装 |
| `uu-helper-openwrt-mipsel-y1-beta.zip` | Lenovo Y1 / Newifi mini R6830 | **仅限 Y1 的实验版**；实机已安装并观察到重启后服务运行，但发现旧设备绑定跨重启失效，**暂不适合无人值守使用** |
| `uu-helper-xiaoqiang-aarch64.zip` | 小米 / 红米 XiaoQiang ARM64 固件 | 已验证参考型号为 Redmi AX6000；其他型号仍需验证 |
| `uu-helper-asuswrt.zip` | 华硕 ASUSWRT / 梅林 | **官方集成优先，只提供检测辅助，不覆盖原厂 UU** |

解压后 Windows 用户可使用 `start-windows.cmd` 上传助手，其他用户可按手动教程上传并运行 `sh uu-helper.sh start`。压缩包带有设备平台与处理器限制，选错包会拒绝安装相关操作；全部只包含项目开源脚本，**不附带网易闭源插件**，使用时才通过官方接口下载并校验。

开发者可运行 `python3 scripts/build-platform-packages.py --output dist` 在本地生成五个确定性 ZIP 和 `SHA256SUMS.txt`（校验清单）；[自动打包记录](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/workflows/platform-packages.yml) 仅供排障和开发者核对。**正式稳定版**仍须等待对应设备完成实机验收。

## Docker 容器安装（实验版）

**一条命令部署（实验版）**：已经安装 Git、Docker Engine 和 Docker Compose 的 Linux 主机，复制下面这一整行到终端即可。启动器会检查 CPU、Docker 权限、现有安装目录，下载独立 Docker 实验分支，再构建并启动容器；不需要管理员特权，也不会修改宿主机防火墙或删除身份卷。

```sh
curl -fsSLo uu-docker-start.sh https://raw.githubusercontent.com/coolhpj/uu-remote-wol-router-helper/feat/docker-experimental/docker/quickstart.sh && sh uu-docker-start.sh
```

> 运行前可先[查看一键部署脚本源码](docker/quickstart.sh)，确认只从本仓库下载实验分支。脚本默认安装到 `$HOME/uu-remote-wol-docker`；首次运行要求已有 Git、Docker 和 Compose，**不会自动安装 Docker 或覆盖别人的现有目录**。命令执行完仍须完成下方手机 UU 绑定和移动数据真实开机测试。原有安装可重复执行但**不会自动拉取更新**，升级方法见[完整说明](docker/README.md)。

**手动安装与排障（四步）**：不愿运行快速启动器，或要核对每条命令时，按下面步骤逐项操作。

**适合谁：** 在 Debian 13、Ubuntu、iStoreOS、飞牛 OS 等支持 Linux Docker Engine（容器引擎）的设备上，运行网易 UU 辅助设备。当前优先 x86_64，ARM64 仍是候选。**不需要路由器 SSH，也不需要下载上面的路由器 ZIP 包。**

**目前只开放 [PR #16 实验分支](https://github.com/coolhpj/uu-remote-wol-router-helper/pull/16)**；正式 `main` 和 Releases（版本发布页）还没有 Docker 稳定版。安装前确保主机与待唤醒的电脑在同一个允许局域网广播的网络里、电脑已配置有线网络 WOL（网络唤醒），并检查宿主机没有正在运行的另一份 UU 辅助服务。容器采用宿主网络，可能和已有服务占用相同端口；**不要与现有路由器辅助设备复用身份目录**。

**第 1 步｜检查 Docker（容器环境）。** 在要作为辅助设备的 Linux 主机终端运行：

```sh
git --version
docker --version
docker compose version
```

以上命令都应正常显示版本。缺少 Git、Docker Engine 或 Compose 插件时，先按操作系统官方教程安装；本项目不负责更改宿主机网络、防火墙或安装 Docker 服务。

**第 2 步｜获取实验代码并启动。** 下列命令会获取 `feat/docker-experimental` 分支（不是 `main`），由本机自行构建开源镜像，首次启动时才下载并校验网易官方插件：

```sh
git clone --branch feat/docker-experimental --single-branch https://github.com/coolhpj/uu-remote-wol-router-helper.git
cd uu-remote-wol-router-helper
docker compose config
docker compose build
docker compose up -d
docker compose ps
docker compose logs --tail=80 uu-wol
```

`docker compose ps` 中服务应显示运行中。如果查看日志遇到报错，先停止容器并参照[详细排障与安全说明](docker/README.md)；**切勿公开原始日志、设备 UUID / SN、账号令牌、IP 或 MAC 地址**。

**第 3 步｜绑定、手机流量实测。** 先让手机连接家里的 Wi-Fi，在 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器** 尝试发现和绑定新增的辅助设备；再在电脑的 **UU远程 → 远程开机配置** 中选择相应辅助设备并完成配置。然后**关闭手机 Wi-Fi，仅用移动数据，真实尝试唤醒已关机的电脑**。如果应用没有发现 Docker 辅助设备，记录“无法发现”即可，不要自行开启特权容器或修改防火墙。

**第 4 步｜检查重建与安全卸载。** 只有首次绑定和唤醒尝试完成后，再测试停止及重建，确认原辅助设备是否仍被手机认可：

```sh
docker compose stop
docker compose up -d --force-recreate
docker compose ps
```

停止并卸载测试容器，但**保留设备身份数据卷**：

```sh
docker compose down
```

**禁止误用 `docker compose down -v`**，它会删除设备身份和绑定数据。需要升级或清除身份时先备份数据卷，并参阅[Docker 完整安装、升级和清理教程](docker/README.md)。目前 GitHub Actions（自动测试）已验证程序启动、守护进程、TCP/16000 连接、身份文件刷新与重建保留及完整 Compose 启停，但**不代表网易账号已承认旧绑定，也不能替代家庭网络中的实际远程唤醒**。测试反馈可发至 [Issue #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15)。

## 路由器原生安装：新手快速开始（3 步）

**第 1 步｜设置电脑唤醒。** 打开 Windows **UU远程 → 远程开机配置**，按提示开启主板和网卡的 WOL（网络唤醒）。建议电脑使用网线，并先确认局域网内能唤醒。

**第 2 步｜启动路由器助手。** 路由器需要已开启 SSH（远程登录），并能用管理员账号登录。优先从上面的 **Releases（版本发布页）** 下载与你的路由器系统、架构匹配的 ZIP（压缩包），解压后双击 **`start-windows.cmd`**，输入路由器地址。助手会自动上传文件，打开数字菜单。开发者仍可用 GitHub 的 **Code → Download ZIP（下载完整源码）** 获取全部源文件。

首次连接请核对 SSH 指纹；可能需要输入几次路由器密码。**这一步只启动助手，不会自动安装插件。**

<details>
<summary>看图操作：下载与 Windows 启动</summary>

![GitHub 下载步骤示意图（非真实网页截图）](docs/images/uu-doc-01-download.png)

![Windows 连接助手示意图（非真实设备截图）](docs/images/uu-doc-02-windows.png)

*两张均为操作示意图；图中的 `router.example.invalid` 是测试地址。*

</details>

**第 3 步｜先运行插件，再绑定和远程开机。** 按数字菜单的设备提示完成适用的运行步骤；**只有路由器上的 UU 插件正在运行时**，才用连接该路由器 Wi-Fi 的手机打开 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器**，查找并添加路由器。在电脑 **UU远程** 中刷新、选择该辅助设备并完成本机配置，确认账号对应。最后关闭手机 Wi-Fi，使用**移动数据**尝试唤醒电脑。仅下载插件或出现云连接，不等于完成了手机绑定。

**只有电脑真正被远程唤醒才算成功**，插件在线不代表远程开机成功。

### 其他使用方式与注意事项

非 Windows 用户或快速启动失败，可按 [手动上传教程](docs/MANUAL-SETUP.md) 上传文件后运行：

```sh
cd /tmp/uu-remote-wol-router-helper
sh uu-helper.sh start
```

助手自动识别设备并显示可用菜单；是否能安装仍取决于型号和固件。**网易 UU 已原生支持的路由器优先使用官方方案。** Lenovo Y1 已在临时运行阶段完成手机移动数据唤醒，专用实验性服务也已成功安装并在真实重启后显示运行；**但 2026-10-14 测试者确认旧设备绑定跨重启失效、需要重新绑定，因此当前不适合长期无人值守使用**，仍需安全修复与实机复测。**通用 MIPS（处理器架构）持久安装依然禁止**；更多请查看 [Lenovo Y1 实验版说明](docs/OPENWRT.md#lenovo-y1自愿试用的持久启动方案尚待真机验收) 和 [实机反馈与故障跟踪](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1)。

<details>
<summary>查看路由器菜单示例</summary>

![OpenWrt ARM64 菜单：根据真实 QEMU 日志排版，不是直接截图](docs/images/uu-doc-03-openwrt-qemu.png)

*根据 [QEMU ARM64 虚拟机测试日志](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/runs/38160517622) 排版，并非真实屏幕截图；其他设备菜单可能不同。*

</details>

更多信息：[高级操作教程](docs/MANUAL-SETUP.md) · [设备兼容矩阵](docs/COMPATIBILITY.md)。

---

## 你应该看到什么？

完整链路应该是：

```text
手机移动数据
    ↓
网易 UU 云端
    ↓
家里常在线的辅助设备
    ↓
局域网 Magic Packet
    ↓
关机 PC 开机
```

只满足下面这些情况都还不能算最终成功：

- `uuplugin` 进程存在；
- 路由器能联网；
- UU主机加速能看到路由器；
- 局域网里手工 WOL 能开机。

最终验收必须是：**手机关闭 Wi‑Fi，仅使用移动数据，把真正关机的 PC 唤醒。**

## 实机验证结果与设备状态

| Router / Environment | Platform | Remote WOL | 说明 |
|---|---|---:|---|
| Redmi AX6000 / RB06 | XiaoQiang / OpenWrt-derived | ✅ | 已完成真实冷启动、UU 云连接、移动数据 Remote WOL |
| ASUS RT-AX86U | ASUSWRT / Merlin-KoolShare | ✅ | 官方/model-specific 路径；本项目默认不覆盖官方集成 |
| iStoreOS x86_64 样本 | Generic OpenWrt | ✅ | 已完成持久安装、reboot、自启动、Remote WOL、rollback 与再次 reboot |
| Lenovo Y1 / Newifi mini R6830 | OpenWrt / MIPS | ✅（仅临时运行） | 2026-10-12 实机手机流量唤醒成功；专用实验版安装并重启后服务运行已观察，但**跨重启旧绑定失效**；正式稳定安装未开放 |
| 其它 Generic OpenWrt | OpenWrt | 待逐台验证 | 架构相同不等于自动兼容 |

> `✅` 仅表示该设备/样本已有真实移动数据远程开机证据。**临时运行成功不等于已完成永久安装或重启回滚验收**；Lenovo Y1 仍是实验性设备，不标记为完整 Verified（已验证）。

完整兼容矩阵：[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)

下图是实测环境中 UU主机加速识别 ASUS RT-AX86U 与 OpenWrt 辅助设备的脱敏截图：

![UU主机加速识别 ASUS RT-AX86U 与 OpenWrt 辅助设备](docs/images/uu-openwrt-device.webp)

## 最常见的几个问题

### 网易 UU 远程开机一定要装路由器插件吗？

不一定。路由器已提供网易 UU 官方远程开机功能时，优先用官方入口；如果没有，先看[兼容设备清单](docs/COMPATIBILITY.md)，不要因为使用 OpenWrt 就直接安装其他型号的包。电脑仍需事先配置 WOL（网络唤醒），在手机移动数据下完成真实开机测试。

### UU 辅助开机和网易 UU 远程控制有什么区别？

**UU 辅助开机**由局域网里持续在线的辅助设备发送网络唤醒信号，让关机电脑开机；**网易 UU 远程控制**负责电脑开机后的连接和操作。本项目只帮助兼容路由器承担前一种辅助角色，并不替代网易 UU 远程客户端。

### OpenWrt 安装网易 UU 路由器插件后，还需要绑定吗？

需要。先确认路由器上的官方 UU 插件正常运行，再进入**网易 UU 主机加速器 → 路由器加速 → 合作款路由器**添加辅助设备，并在电脑端的 UU 远程开机设置完成关联。**安装成功或看到进程，并不等于手机远程开机已经成功。**

### Lenovo Y1 重启后需要重新绑定 UU 辅助设备怎么办？

这已是[社区实机报告的未修复问题](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1#issuecomment-6164268516)：当前实验版可能在路由器重启后使原设备显示离线。**不要把反复重新绑定当成稳定解决方法**，也不要自行把整个插件写进空间有限的闪存；我们正在评估内置压缩包或 U 盘持久存储方案，**两者都尚未证明能够保存原绑定身份**。

### 路由器后台像运营商光猫，没有插件市场，也没有 SSH/root

这类设备通常**不适合直接使用本项目**。不要为了 UU远程去动 TR069、VLAN、运营商 WAN 等配置。

优先使用 Android / 常开电脑作为 UU 辅助设备，或者在光猫后面增加一台真正支持 UU/OpenWrt 的路由器。

### 路由器已经被 UU主机加速识别，但 UU远程仍提示没有辅助设备

先检查：

- UU主机加速与 UU远程是否处于正确的同账号关系；
- 当前 PC 是否单独完成过一次远程开机配置；
- 是否先在 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器** 添加了**正在运行 UU 插件**的路由器；
- 路由器上的 UU 是否真正建立云连接，而不是只有进程存在。

### 同一个账号下有多台 PC，为什么只有一台能开？

每台 PC 都要分别完成自己的 WOL / 远程开机配置，不会因为同账号自动继承。

### `diagnose` 显示 `platform: unknown`

不要拿其它型号脚本硬套。运行：

```sh
sh uu-helper.sh collect-info
```

提交脱敏报告后再适配。

## 安全边界

本项目：

- **不提供**破解、漏洞利用或绕过设备安全限制取得 SSH/root 的教程；
- **不提交**网易 `uuplugin`、`xuplugin-guardian`、`xtables-nft-multi` 等闭源二进制；
- 运行时只从网易官方通道获取插件，并进行完整性校验；
- 未知设备默认只允许 `Detect → Collect → Redact → Report`，不会自动猜型号安装；
- Generic OpenWrt 的一个样本通过，不代表所有 OpenWrt 自动兼容。

安全说明：[`SECURITY.md`](SECURITY.md)

SSH/root 边界：[`docs/SSH-ACCESS.md`](docs/SSH-ACCESS.md)

## 想看技术细节？

README 只保留普通用户真正需要看的内容。实现、实验和平台差异放在下面：

- 完整设备矩阵：[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)
- Generic OpenWrt / iStoreOS：[`docs/OPENWRT.md`](docs/OPENWRT.md)
- XiaoQiang / Redmi AX6000：[`docs/XIAOQIANG.md`](docs/XIAOQIANG.md)
- ASUSWRT：[`docs/ASUSWRT.md`](docs/ASUSWRT.md)
- 多辅助设备行为：[`docs/MULTI-AUX-DEVICE.md`](docs/MULTI-AUX-DEVICE.md)
- 贡献新设备：[`CONTRIBUTING.md`](CONTRIBUTING.md)

## 项目原则

本项目来自真实设备排障，并大量使用 AI 辅助分析和代码生成。因此维护规则很简单：

> **Verified（已验证）必须来自真实硬件证据，不能来自 AI 推测。**

任何 AI 生成代码进入可写入路由器的路径前，都必须有明确安全门、回滚设计、自动测试和真实设备证据。

## License / 许可证与署名

本项目使用 [MIT License](LICENSE)。

Copyright (c) 2026 **coolhpj and contributors**.

MIT 许可证允许使用、复制、修改、合并、发布、分发、再许可和商业使用；但在重新发布本项目代码或其 substantial portions（主要部分）时，**必须保留原版权声明和 MIT 许可文本**。

如果你基于本项目制作衍生版本，欢迎同时注明原始项目来源，方便用户找到上游更新与兼容性说明：

<https://github.com/coolhpj/uu-remote-wol-router-helper>

> 注：回链到原仓库是推荐做法；MIT 许可证的强制要求是保留版权声明和许可文本，不额外增加限制。

