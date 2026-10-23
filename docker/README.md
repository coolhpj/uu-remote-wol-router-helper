# Docker 实验版（不属于已验证远程开机设备）

> **最新实验状态：** GitHub Actions 已通过 x86_64 / ARM64 构建、官方 v14.10.6 下载与校验；修复可写 `/var/run/uuplugin.pid` 后，Alpine 非特权容器中的主程序、`xuplugin-guardian`（守护程序）、TCP/16000 连接、自动生成的 `.uuplugin_uuid` 和 `.sn` 均通过检测。正式 Compose 的启动、停止、重建、保留身份卷，以及身份文件刷新后保持一致也已通过 GitHub 隔离测试。**这不等于网易账号认可旧绑定，更不等于手机移动数据成功唤醒关机电脑。此版本仍是 PR #16 实验版，不是稳定发布。**

适用于安装了 Linux Docker Engine（容器引擎）的 Debian、Ubuntu、iStoreOS、飞牛 OS 等设备。x86_64 优先，ARM64 仅有自动构建证据。**不是网易官方镜像；请勿直接覆盖现有 UU 辅助设备。**

## 从零安装（四步）

**1. 检查环境。** 在准备常开的 Linux 主机上运行：

```sh
git --version
docker --version
docker compose version
```

如无法显示版本，先安装对应系统官方提供的 Git、Docker Engine 与 Compose 插件。主机与要唤醒的电脑应在允许广播的同一局域网，电脑需预先配置 WOL（网络唤醒）。本容器采用宿主网络，请先确认与已有 UU 服务没有端口冲突；不要复用路由器的旧 UUID / SN 文件。

**2. 下载实验分支并启动。** 请确保拿到的是 `feat/docker-experimental` 而非 `main`：

```sh
git clone --branch feat/docker-experimental --single-branch https://github.com/coolhpj/uu-remote-wol-router-helper.git
cd uu-remote-wol-router-helper
docker compose config
docker compose build
docker compose up -d
docker compose ps
docker compose logs --tail=80 uu-wol
```

首次启动时，项目通过现有 `scripts/stage-package.sh` 从网易官方接口下载并验证闭源插件，不会在镜像中预装它。遇到失败先运行 `docker compose stop`，只提交脱敏错误描述，不要公开原始日志、UUID、SN、令牌、IP 或 MAC。

**3. 在手机上绑定并实际远程开机。** 手机先连接家中 Wi-Fi，进入 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器**，尝试发现/添加辅助设备。之后在电脑端的 **UU远程 → 远程开机配置** 里选择正确辅助设备，完成配置。待机或关机后，**关闭手机 Wi-Fi、仅使用移动数据**测试远程唤醒。容器运行、TCP 连接、手机看到设备都不能替代真正开机的结果。如果手机无法发现，反馈“无法发现”即可，不要自行启用特权模式或修改主机防火墙。

**4. 测试重建、停止和卸载。** 首次绑定后，可以运行以下命令查看重建后是否仍然保持原绑定：

```sh
docker compose stop
docker compose up -d --force-recreate
docker compose ps
```

需要退出实验时：

```sh
docker compose down
```

`down` 会移除本项目的容器和网络，但默认**保留设备身份数据卷**。**绝对不要在尚需保留绑定时运行 `docker compose down -v`**，它会删除数据卷中的身份文件。详细的更新、备份和权限限制参见下文。愿意反馈结果可到 [Issue #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15)，只需填写“容器运行 / 手机发现与绑定 / 重建后保留 / 手机流量真实开机”四项成功与否。

> 这些步骤与路由器 SSH / ZIP 安装路线完全独立。GitHub Actions 自动测试发生在临时 Linux 环境，真实家庭网络兼容性仍需志愿者验证。

## 安全及数据

- Compose 使用宿主网络，以允许 LAN WOL 广播；**不是**端口隔离环境。运行前需审查容器将占用的监听端口，不要和宿主原有 UU 服务并行。无特权模式，去除全部 Linux capabilities（能力权限），只加回 `NET_RAW`（原始网络报文），不授予 `NET_ADMIN`（修改主机网络/防火墙）。
- UID/GID 10001 运行，根文件系统只读。`/tmp` 是临时内存空间，`/run` 是仅供 UID 10001 写入的短期 PID 空间（网易官方插件需要 `/var/run/uuplugin.pid`），均不会跨重建保留；`/var/lib/uu-wol` 才是持久化命名卷。兼容路径 `/usr/sbin/uu` 也指向此持久化运行目录，保留工作目录、`.uuplugin_uuid` 与账号状态；不把敏感文件写进镜像。不要公开共享该卷、日志或原始 UUID。**没有证据证明官方插件只依赖该文件**，仍需真实跨重建绑定验证。
- `docker compose stop` 安全停止；`docker compose up -d --build` 重建/升级开源包装器而不删除数据卷。手动升级官方闭源插件：先 `docker compose stop`，然后 `docker compose run --rm uu-wol refresh`，再 `docker compose up -d`。升级前**务必自行备份命名卷**，尤其是 UU 身份目录。实验性 refresh 不保证官方二进制内部状态向后兼容。
- 卸载运行容器：`docker compose down`，**默认保留卷**。`docker compose down -v` 会永久删除身份与绑定数据，请只在确认备份后手动使用。不要把它纳入任何自动清理。
- `docker compose run --rm uu-wol status` 只检查本地状态；`smoke`/ `persistence-check` 是离线容器测试，**不会启动网易插件**，也不代表远程开机成功。

## 验证等级

| 门槛 | 验证范围 |
|---|---|
| 1 镜像构建 | x86_64/ARM64 源码镜像能成功构建，不含 UU 闭源文件 |
| 2 容器启动 | CI（持续集成）测试独立入口可运行、卷能跨重建保留、停机清理 |
| 3 官方插件运行 | 在目标宿主实际下载校验、执行，记录 uuplugin/guardian 和云连接状态 |
| 4 远程开机 | 实际设备绑定 + 手机移动网络 WOL 唤醒关机电脑 |

CI 在隔离 Docker bridge（私有桥接网络）中额外尝试最长约 20 秒的官方插件运行与 TCP/16000 观察，不使用宿主网络，不保存真实设备身份，也不向公开日志输出插件原始内容。它比较非 root（普通用户）、root（管理员身份但无网络管理权限），以及仅在隔离网络空间内拥有 NET_ADMIN 的测试；严禁将最后一种配置直接复制到宿主网络部署。

实际插件测试是 **非阻断式诊断**：GitHub Actions 仅将镜像构建、容器 smoke、文件安全检查和虚拟持久化样本作为必过门槛。插件未建立云连接时，会在工作流摘要里明确标为 *runtime diagnostic failure（运行诊断失败）*，并产生警告；**全部必过检查绿色也不代表 UU 云连接成功**。测试 UUID 为固定虚拟样本，不是网易真实设备身份。官方包下载地址可能使用 HTTP，仓库既有 MD5 校验不能替代加密传输或强签名，正式版需单独解决供应链风险。

**真实身份持久化诊断：** GitHub Actions 现在使用全新命名卷启动官方插件，验证插件自动生成的 `.uuplugin_uuid` 和 `.sn` 均存在；停止原容器后刷新官方二进制、再创建全新容器，分别比较两个身份文件内容是否完全一致。比对值仅保存在本次运行器内存，不输出身份或摘要；测试结束删除临时数据卷。目前该测试已在 GitHub Actions 中通过，但它的成功仅代表文件级身份连续性，不代表网易账号依旧认可绑定，也不代替手机移动数据远程开机实测。另有独立 CI 脚本使用真正的 `docker compose up -d`、`stop`、`up --force-recreate` 和 `down` 验证宿主网络、非特权权限、服务启动及卷保留，**仅针对 GitHub 独有的临时项目和数据卷进行清理**，不会自动清理用户已有部署。

CI 完成门槛 1/2 不能自动升级为 3/4。受限权限导致 UU 插件不能运行时，请记录现象，不要直接启用 `privileged`（特权模式）、挂载 `docker.sock` 或修改宿主机防火墙。
