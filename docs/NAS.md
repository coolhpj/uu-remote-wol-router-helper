# NAS 独立安装指南｜网易 UU 远程开机 Docker 测试版

> **这是 PR #16 的 Docker 路由器插件身份实验版，不是 PR #19 的独立 WOL-only 辅助设备。**
> NAS 和 PC 的真实 UU 云端绑定、手机移动网络唤醒仍需志愿者实测。不要因 GitHub CI 绿色而当作已经验证成功的正式版。非网易官方项目。

## 下载测试版

**[下载 NAS / Linux Docker 测试版固定源码 ZIP](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/28a25816101b68e8fc269109942c2f465f0e5b72.zip)**

- 固定源代码提交：`28a25816101b68e8fc269109942c2f465f0e5b72`（PR #16 Docker 路由器身份实验分支）。
- ZIP 含 `compose.yaml`、`Dockerfile`、`docker/entrypoint.sh`、`scripts/nas-preflight.sh` 和开源启动代码。**ZIP 是可构建源码，并非预编译镜像**，也不包含网易闭源插件。
- Docker 构建需要拉取基础镜像，首次启动会根据仓库校验规则从网易官方服务下载插件；必须保持外网可达。
- [当前 Docker 实验源码和验收记录](https://github.com/coolhpj/uu-remote-wol-router-helper/pull/16)。
- [已有五平台路由器 ZIP 发布页](https://github.com/coolhpj/uu-remote-wol-router-helper/releases/tag/v0.1.0-beta.2) **不包含 NAS Docker 镜像**。

## NAS 支持说明

以下系统均需自行确认支持 Linux Docker Engine 和 `docker compose`：

| NAS 系统 | 候选架构 | 目前实际验证等级 |
| --- | --- | --- |
| 威联通 QNAP Container Station | x86_64 / ARM64 | 通用 Linux Docker 候选；尚无本模式真机唤醒报告 |
| 群晖 Synology Container Manager | x86_64 / ARM64 | 通用 Linux Docker 候选；需要确认 Compose CLI |
| 飞牛 OS / 极空间 | x86_64 / ARM64 | 通用 Docker 候选；此版本仍未通过 UU 真机绑定 |
| Debian / Ubuntu / iStoreOS 常开机器 | x86_64 / ARM64 | x86_64 GitHub 构建与容器级测试通过；ARM64 仅候选 |

NAS 图形界面不一定支持从 `build:` 配置直接构建镜像。下面优先使用 NAS **SSH/终端内的 Docker Compose**；如没有 Compose CLI，不建议未经验证直接粘贴 YAML 到图形界面，更不要开启特权模式来绕过问题。

## 步骤一：安装前检查

请先保证 NAS 和要唤醒的 PC 处于能传递 WOL 广播的局域网。PC 自身 WOL 应已设置。选择**不会被自动清理**的 NAS 共享目录保存源码，不要覆盖已有 UU 容器、路由器设备 UUID、SN 或数据卷。

将下载的 ZIP 解压到 NAS 共享目录，**在解压所得的仓库根目录**运行：

~~~sh
sh scripts/nas-preflight.sh
docker compose config --quiet
~~~

出现 `NAS_PREFLIGHT_OK` 仅表示基本 Docker 安装条件符合，不证明网易云端或局域网 WOL 已正常。出现 FAIL 时应停止部署，不要用 `sudo`、`privileged`、开放公网端口或改动光猫/VLAN 代替正常排障。

## 步骤二：构建并运行测试容器

~~~sh
docker compose build
docker compose up -d --no-build
docker compose ps
~~~

容器使用 `network_mode: host` 便于尝试 LAN 广播，**不是完全隔离的桥接网络**。配置为 UID/GID 10001、只读根文件系统、`no-new-privileges`、丢弃所有 Linux capabilities 后仅加回 `NET_RAW`，不要求 `NET_ADMIN`、`privileged` 或 `docker.sock` 挂载。请先核对 NAS 现有 UU 服务和端口是否冲突，不要让两个不同 UU 身份共用数据。

该测试版使用自己的 Docker 命名数据卷存储身份文件；不复制、重用其他辅助设备的 UUID/SN，也不要公布卷内容。

## 步骤三：UU 绑定与真实远程开机

1. 在自己的网易 UU 手机 App 上按对应**路由器插件身份**绑定入口尝试发现、添加辅助设备；在 PC UU 远程客户端完成开机辅助设备关联。
2. 让目标 PC 进入测试所需的关机状态；手机关闭 Wi-Fi，仅用移动网络发起远程开机。
3. **只有 PC 真正开机才记为成功**。Docker 进程在线、UUID 已生成、成功下载插件、TCP 建立或手机上看见图标，都不是最终成功证据。
4. 绑定成功后，还需要分别验证容器重建及 NAS 重启，确认原设备身份仍被网易认可。

## 步骤四：检查、暂停与卸载

在原部署目录执行：

~~~sh
docker compose logs --tail=60 uu-wol
docker compose stop
docker compose up -d --no-build
docker compose down
~~~

`docker compose down` 默认保留项目命名身份卷，**不要运行 `docker compose down -v`**，否则会删除测试设备身份文件、影响原绑定。升级前应停止容器并离线备份相关命名卷，不要自动拉取未经验证的分支。此版不会自动修改路由器或光猫设置。

## 社区测试反馈

请在 [GitHub Issue #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15) 只提交脱敏结果：

| 检查项 | 记录 |
| --- | --- |
| NAS 型号、系统版本及 CPU 架构 | 型号/版本即可 |
| Docker / Compose 构建与容器启动 | 成功 / 失败 |
| UU App 发现并绑定 | 成功 / 失败 |
| 手机移动数据真实唤醒 | 成功 / 失败 |
| 容器重建后仍能唤醒 | 成功 / 失败 |
| NAS 完全重启后仍能唤醒 | 成功 / 失败 |

**禁止公开**扫码凭据、UU Token、UUID、SN、完整原始日志、私有 IP/MAC、NAS 管理账号或身份数据卷。

## NAS 还有另一种安装方式

如果 NAS 不是主路由器，可以查看 [NAS 独立辅助设备 WOL-only 源码测试版](NAS-WOL-ONLY-BETA.md)。

- **本页**：Docker 路由器插件身份，下载入口在上面。
- **独立辅助设备版**：单独的 GPL 客户端，使用不同的身份和数据卷，适合普通 NAS 参与测试。
- 两个版本都需要在自己的设备上验证手机移动数据唤醒。独立版目前只有源码测试包，没有稳定镜像。

[独立版下载与安装](NAS-WOL-ONLY-BETA.md) · [实机测试反馈 Issue #23](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/23)

**开发说明：** 本项目部分代码、测试和文档由 **ChatGPT（OpenAI GPT-6）协助开发**，维护者审核发布。非网易官方项目。
