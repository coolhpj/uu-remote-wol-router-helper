# 网易 UU 远程开机助手｜路由器与 Docker（支持 NAS）

![网易 UU 远程开机助手示意图](docs/images/uu-doc-00-overview.png)

*功能示意图，不是所有型号的实测截图。非网易官方项目。*

这个项目帮助家里常开的路由器或 Linux / NAS 设备，配合网易 UU 远程唤醒已关机的电脑。**电脑本身需要先设置好 WOL（网络唤醒）。**

## 选择安装方式

- **[路由器版](#路由器版)**：OpenWrt、iStoreOS、小米 / 红米、华硕等，按设备型号选择安装包。
- **[Docker 版（支持 NAS）](#docker-版支持-nas)**：QNAP、群晖、飞牛、极空间及常开的 Linux 主机。里面可选**独立辅助设备模式**或**路由器插件模式**。

## 路由器版

[下载五平台测试包 v0.1.0-beta.2](https://github.com/coolhpj/uu-remote-wol-router-helper/releases/tag/v0.1.0-beta.2) · [查看已测试的设备](docs/COMPATIBILITY.md) · [OpenWrt / iStoreOS 教程](docs/OPENWRT.md)

| 安装包 | 适合设备 | 当前情况 |
| --- | --- | --- |
| `uu-helper-openwrt-x86_64.zip` | OpenWrt / iStoreOS x86_64 | 已验证一个 iStoreOS 实机样本 |
| `uu-helper-openwrt-aarch64.zip` | OpenWrt ARM64 | 仍需逐型号测试 |
| `uu-helper-openwrt-mipsel-y1-beta.zip` | Lenovo Y1 / Newifi mini | 实验版；重启后旧绑定可能失效 |
| `uu-helper-xiaoqiang-aarch64.zip` | 小米 / 红米固件 | 参考实测设备 Redmi AX6000 |
| `uu-helper-asuswrt.zip` | 华硕 / 梅林 | 优先使用官方集成，本项目只提供检查辅助 |

**简单安装（路由器版）：**

1. 先在电脑上完成网易 UU 远程开机与网卡 WOL 设置，确认局域网内可以唤醒。
2. 下载与设备匹配的 ZIP，解压后 Windows 用户双击 `start-windows.cmd`，按提示通过 SSH 连接路由器，进入数字菜单。**打开菜单不等于已经安装插件。**
3. 按菜单提示运行适用的 UU 插件，在手机「网易 UU 主机加速器 → 路由器加速 → 合作款路由器」中添加路由器，再到电脑的「UU远程」完成辅助设备关联。手机关闭 Wi-Fi，用**移动数据**实际唤醒关机电脑。

<details>
<summary>查看操作示意图</summary>

![GitHub 下载示意](docs/images/uu-doc-01-download.png)

![Windows 启动助手示意](docs/images/uu-doc-02-windows.png)

![OpenWrt 菜单示意](docs/images/uu-doc-03-openwrt-qemu.png)

*以上为操作示意或按虚拟机日志制作的图，不是所有设备的实机截图。*

</details>

其他系统或高级操作见[手动安装教程](docs/MANUAL-SETUP.md)。**未知型号不要强行安装；通用 MIPS 持久安装仍不开放。** 设备已经自带官方 UU 的，优先用官方功能。

## Docker 版（支持 NAS）

Docker 是安装方式，**NAS 只是其中一种设备**。目前有两种不同的网易 UU 设备身份，按需要选择一种测试，不能混用数据卷和绑定信息。

### ① 独立辅助设备模式（普通 NAS 可优先了解）

适合不充当主路由器的 NAS 或 Linux 主机。通过单独的 GPL WOL-only 客户端尝试接收唤醒指令。

[下载源码测试版 ZIP](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/66707aeb20f0021b45ac5f95d4aec243197b4c41.zip) · [安装教程](docs/NAS-WOL-ONLY-BETA.md) · [反馈测试结果 #23](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/23)

**当前状态：** x86_64 的源码构建、Docker 隔离测试和模拟局域网发包已通过；**尚未完成本版本的真实网易 UU 手机远程开机验证**。ARM64 尚未验证。没有稳定镜像。

### ② 路由器插件模式（实验版）

使用网易 UU 路由器插件身份，适用于支持 Docker 的路由器、Linux 主机及部分 NAS。普通非网关 NAS 可能遇到发现或绑定兼容性问题。

[下载源码测试版 ZIP](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/28a25816101b68e8fc269109942c2f465f0e5b72.zip) · [Docker / NAS 安装教程](docs/NAS.md) · [反馈测试结果 #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15)

**一键拉取并启动（Linux / NAS 终端）：** 先安装 Git、curl、Docker Engine 和 Docker Compose，再执行：

```sh
curl -fsSLo uu-docker-start.sh https://raw.githubusercontent.com/coolhpj/uu-remote-wol-router-helper/feat/docker-experimental/docker/quickstart.sh && sh uu-docker-start.sh
```

[查看启动脚本](https://github.com/coolhpj/uu-remote-wol-router-helper/blob/feat/docker-experimental/docker/quickstart.sh)。默认安装到 `$HOME/uu-remote-wol-docker`，拉取的是**路由器插件模式实验分支**，不是上面的固定 ZIP，也**不适用于独立辅助设备模式**。脚本会构建并启动容器，运行前请确认没有现役 UU 容器或端口冲突。

**当前状态：** Docker 镜像构建和身份卷测试通过；普通 NAS 的实际 UU 绑定与远程开机仍需用户验证。没有稳定镜像。

两种 Docker 方案都需自行在受控设备上构建，使用宿主网络（`host`），不是完全网络隔离。**手机移动数据真正唤醒关机电脑，才算测试成功。**

## 已有路由器实测

| 设备 | 远程开机结果 | 说明 |
| --- | --- | --- |
| Redmi AX6000 | 已通过 | 真实手机移动数据唤醒 |
| ASUS RT-AX86U | 已通过 | 官方 / 梅林参考方案，本项目不覆盖官方集成 |
| iStoreOS x86_64 样本 | 已通过 | 安装、重启、唤醒和回滚已验证 |
| Lenovo Y1 | 仅临时运行通过 | 重启后绑定未保持，不适合无人值守 |
| 其他型号 | 待测试 | 相同 CPU 架构不代表自动支持 |

完整证据和各设备限制见 [兼容性矩阵](docs/COMPATIBILITY.md)。**上表属于路由器实测，不代表 Docker 版已通过相同验收。**

## 常见问题

**我该选路由器版，还是 Docker 版（支持 NAS）？**

- **有 OpenWrt / iStoreOS / 小米等路由器，且型号、固件符合兼容要求**：选[路由器版](#路由器版)。下载对应 ZIP，Windows 用户双击 `start-windows.cmd`，通过 SSH 连接路由器并按菜单操作。路由器已自带官方 UU 的，直接用官方功能即可。
- **有群晖、威联通、飞牛、极空间等 NAS，或一台常开的 Linux 主机，并且支持 Docker Compose**：选[Docker 版（支持 NAS）](#docker-版支持-nas)，在设备终端按对应模式的教程构建、启动。**NAS 是设备，Docker 是安装方式，不需要再找单独的 NAS 版。**
- **设备没有 Docker，也不符合路由器版安装条件**：暂时不能直接使用这两种安装方案，不要强行套用其他设备的脚本。

**Docker 版里的两种模式怎么选？** 普通 NAS 尤其不是家庭主路由器时，可优先尝试[独立辅助设备模式](docs/NAS-WOL-ONLY-BETA.md)（需要配置电脑 MAC、NAS 网卡并扫码）；有 Docker 的路由器或 Linux 主机，也可以测试[路由器插件模式](docs/NAS.md)（首页提供一键安装命令）。**两种模式的绑定数据不能混用，均尚未通过本项目版本的手机移动数据真实远程开机验收。**

**路由器已自带 UU，还要安装吗？** 不用。优先使用官方功能。

**辅助设备已在线，为什么开不了机？** 先检查电脑自己的 WOL 设置、手机端路由器绑定、Windows「UU远程」的辅助设备关联。在线不等于成功唤醒。[详细步骤](docs/MANUAL-SETUP.md)

**未知型号或没有 SSH 怎么办？** 不要套用其它设备的安装包，也不要为了安装插件修改光猫或绕过安全限制。[SSH 说明](docs/SSH-ACCESS.md) · [提交新设备信息](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/new/choose)

**同账号有多台电脑或辅助设备怎么办？** 每台电脑单独配置 WOL；多个辅助设备同时在线的选择机制尚未确定。[实测说明](docs/MULTI-AUX-DEVICE.md)

## 安全与项目说明

- 本项目不提供提权、绕过路由器安全限制或重分发网易闭源插件的工具。下载官方插件时会校验完整性。
- 反馈请勿公开密码、二维码、UU Token、序列号、私有 IP / MAC 或完整原始日志。[安全说明](SECURITY.md)
- 项目主代码使用 [MIT 许可证](LICENSE)。**独立 WOL-only 测试模式基于 [uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) 的 GPL-3.0-or-later 客户端，相关源码及补丁保留 GPL 许可，不能当作 MIT 代码重新授权。**
- **开发说明：** 本项目部分代码、测试和文档由 **ChatGPT（OpenAI GPT-6）协助开发**，仓库维护者 `coolhpj` 审核发布。AI 辅助不代表官方认可或实机测试成功。

[技术架构](docs/ARCHITECTURE.md) · [设备兼容性](docs/COMPATIBILITY.md) · [参与贡献](CONTRIBUTING.md)

Copyright © 2026 **coolhpj and contributors**。MIT 代码再分发时须保留原版权和许可文本。
