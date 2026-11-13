# NAS 独立辅助设备版｜GPL WOL-only Docker 源码预览

> **Experimental Beta / 自愿测试，非稳定版，不是网易官方产品。** 此页介绍让常开 NAS 以**独立辅助设备身份**接收网易 UU 远程开机指令的实验路线。已通过 GitHub 的离线安全测试与 Docker 构建，**尚未验证本候选在网易真实云端持续在线、手机移动数据实机唤醒及 NAS 重启后绑定保持**。请在本人有权管理、可回滚的测试环境中使用。

## 先确认选对方案

| 方案 | 身份及实现 | 当前状态 |
| --- | --- | --- |
| [路由器原生版](../README.md#按平台下载预览测试版尚非稳定版) | OpenWrt / iStoreOS 等设备上的路由器插件 | 按设备兼容矩阵选择 |
| [Docker 路由器身份版](NAS.md) | PR #16，容器运行网易官方路由器 `uuplugin` | 已提供源码测试包；普通非网关 NAS 的实际唤醒仍有兼容性风险 |
| **本页：NAS 独立 WOL-only 版** | 单独的 GPL-3.0-or-later Linux 客户端经过 WOL-only 限制补丁，以辅助设备身份工作 | **固定源码公开预览**；x86_64 实验环境 Docker 离线 CI 通过，真实 UU 唤醒待志愿者验证 |

这是**两套不同设备身份的 Docker 方案**。它们不能共用注册身份、数据卷、二维码授权状态或卸载步骤。另有 [PR #19](https://github.com/coolhpj/uu-remote-wol-router-helper/pull/19) 是独立的 MIT 协议研究草稿，并**不是**本页 GPL 构建。

## 源码下载和实际验证

- **[下载已验证固定提交的 GPL WOL-only 源码快照 ZIP](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/66707aeb20f0021b45ac5f95d4aec243197b4c41.zip)**。
- [Docker 文件与候选使用说明](https://github.com/coolhpj/uu-remote-wol-router-helper/blob/66707aeb20f0021b45ac5f95d4aec243197b4c41/labs/gpl-isolation/docker/README.md)；安装文件位于 `labs/gpl-isolation/docker/`。
- [GitHub Actions #43452562641](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/runs/43452562641)：固定提交 `66707aeb` 的 **2/2 Job SUCCESS**。包括 Rust（代码语言）单测、独立虚拟局域网内发送一个 UDP/9 的 102 字节唤醒包、非 WOL 命令提前拒绝、真正 Docker 构建、断网容器拒绝启动完整远控及非 root 身份卷跨容器重建保留。
- 无预编译 Docker 镜像、无正式稳定 Release。源码构建阶段会从 [VallierDev/uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) 下载固定的 GPL-3.0-or-later 上游 `v0.2.58` / `0e1e935fb41c2aac2bdd5eebdd4b38a7476d14bc`，在临时工作区应用 [WOL-only 补丁](https://github.com/coolhpj/uu-remote-wol-router-helper/blob/66707aeb20f0021b45ac5f95d4aec243197b4c41/labs/gpl-isolation/apply-wol-only.py)。该补丁与生成的二进制按 GPL-3.0-or-later 处理，**不得当作主仓库 MIT 软件重新授权**。

## 自愿试装前提

优先限定 Linux **x86_64** 的自有隔离测试机、支持 Docker Engine / Compose 的 NAS；ARM64 此独立 GPL 版本尚无对应镜像和真实功能验收。目标 PC 事先完成主板、网卡和系统的 WOL 设置，NAS 与 PC 需要处在可发送定向局域网广播的网络。试装会让**非网易官方的第三方客户端**以用户授权的设备身份向网易云端建立连接；请先理解这项账号绑定及隐私风险。不要在承担关键业务的生产 NAS 上直接启用，也不要与现有 UU 容器混装。

此候选采用 `network_mode: host`（共享宿主网络栈），虽然限制了权限、只读根文件系统、非 root 用户以及只加入 `NET_RAW`，**仍然不是完全网络隔离**，也没有证明在所有 NAS 内核上都适用。必须确认正确的局域网接口和唯一获准被唤醒的 PC MAC，不能填写 WAN、Docker 桥或环回接口。

## 在自己的隔离 Linux / NAS 上复验（实验操作）

先解压固定源码 ZIP，进入其仓库根目录；下列命令**均在该测试环境的 Linux 终端运行**，不得在 ChatGPT 云端或 QNAP 生产容器里直接照搬。

**1. 准备私有配置：**

```sh
cd labs/gpl-isolation/docker
cp .env.example .env
chmod 600 .env
```

使用本机编辑器修改 `.env` 两个占位值：`UU_WOL_ALLOWED_MAC` 是**本人明确批准唤醒**的 PC 网卡 MAC，`UU_WOL_LAN_IFACE` 是此 Linux 主机实际承载相同局域网的接口名称。不要公开这份文件。别复制现有路由器 UUID/SN、别导入其他 UU 容器身份卷。

**2. 先审核配置、再构建容器：**

```sh
docker compose --profile service config --quiet
docker compose --profile service build
```

出现任何 `WOL_ONLY_STARTUP_DENIED`、网卡绑定拒绝或构建错误时应停止排查；不要用 `privileged`、映射 Docker socket 或关闭安全策略代替修复。

**3. 在本人自有测试环境扫码授权：**

```sh
docker compose run --rm -it uu-wol-only login --no-gui
```

仅在你理解第三方客户端登录风险并愿意参与测试时执行；终端显示的二维码仅供本人用网易 UU 远程 App 扫码，不要截图公开。成功凭据在独立命名卷持久化保存。扫码成功本身不代表云端 WOL 已被验证。

**4. 启动、观察并尝试真实唤醒：**

```sh
docker compose --profile service up -d --no-build
docker compose --profile service ps
docker compose --profile service logs --tail=60 uu-wol-only
```

请先**在自己可回滚的测试环境**检查服务是否在线、有无非预期监听端口以及远程桌面、终端、文件、WebRTC 和端口映射功能是否仍被拒绝。由本人确认目标 MAC 后，才可以在本人手机**关闭 Wi-Fi、只开移动数据**的情况下尝试唤醒自己已经关机的 PC。还要验证容器重建、NAS 完整重启后的同一设备身份是否保留。

**5. 退出实验：**

```sh
docker compose --profile service stop
docker compose --profile service down
```

`down` 默认保留独立身份卷。**不要运行 `down -v`**，否则可能丢失已绑定身份；退出前确认没有其他共享同一卷的容器。不要公开原始日志、二维码、Token、MAC/IP 或 NAS 管理资料。

## 反馈与下一阶段

**[在 Issue #23 报告 NAS WOL-only 自愿测试结果](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/23)**：只需机器型号/系统和 CPU 架构、Docker/Compose 版本、固定提交 `66707aeb`、扫码/在线/接收唤醒/实际开机/容器重建/NAS 重启各项成功或失败。失败记录应只包含**脱敏错误分类**，不上传完整日志或个人设备标识。

**完成稳定版的必要条件**：真实网易房间认证与长期在线、真实手机推送唤醒、联网状态下非唤醒功能运行时不可达、NAS 重启持久性及 GPL 对应源码和发行物校验。以上未全部完成时，只能称为**公开源码预览（Experimental Beta）**。

## AI 协作及授权说明

本实验版部分源码、测试、文档由 **ChatGPT（OpenAI GPT-6）协助开发、排查与整理**，由仓库维护者 `coolhpj` 审核并决定发布范围。自动化测试成功只证明列明的受测部分；**ChatGPT 参与不代表网易官方授权、产品安全保证或任何真实远程唤醒承诺**。第三方 GPL 上游及补丁的许可边界继续适用。
