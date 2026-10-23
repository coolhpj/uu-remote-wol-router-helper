# Docker 实验版（不属于已验证远程开机设备）

> **当前阻塞：** 官方插件 v14.10.6 已在 GitHub Actions 下载校验成功，但 Alpine 容器按正式数据卷启动时仍退出码 255，未建立云连接。请勿把这一分支当作可用产品部署到真实家庭网络。另有独立 OpenWrt 根文件系统候选，仅作隔离兼容性对照，不修改默认 Compose，也不会改变宿主机防火墙。

适用于支持 Linux 容器和 `network_mode: host` 的 Debian、Ubuntu、iStoreOS、飞牛 OS 等系统。x86_64 优先；ARM64 为候选。**仅实验用途**，不是网易官方镜像，不承诺对应系统已能完成 UU 云连接或实际远程开机。

## 三步测试

1. 安装 Docker Engine 和 Docker Compose 插件，下载本 PR 的源码。先确认宿主机与待唤醒电脑处在允许局域网广播的网络内，并且宿主机没有另一份 UU 服务正在使用同一身份；不要复用路由器现有身份文件。
2. 在源码目录运行 `docker compose build`，然后 `docker compose up -d`。首次启动才通过仓库现有 `scripts/stage-package.sh` 调用网易官方 API 下载官方插件，并使用仓库既有校验、解包逻辑；镜像本身不带任何闭源二进制。
3. 用 `docker compose logs --tail=80 uu-wol` 查看启动信息。插件是否在线、手机 UU 账号绑定、Windows UU 远程配置与 **手机关闭 Wi-Fi 仅用移动网络实际唤醒关机电脑** 都必须独立检查。没有完成最后一步，一律不能宣称 WOL 实测成功。

## 安全及数据

- Compose 使用宿主网络，以允许 LAN WOL 广播；**不是**端口隔离环境。运行前需审查容器将占用的监听端口，不要和宿主原有 UU 服务并行。无特权模式，去除全部 Linux capabilities（能力权限），只加回 `NET_RAW`（原始网络报文），不授予 `NET_ADMIN`（修改主机网络/防火墙）。
- UID/GID 10001 运行，根文件系统只读，`/tmp` 临时内存空间，`/var/lib/uu-wol` 为命名卷；兼容路径 `/usr/sbin/uu` 也指向此持久化运行目录，保留工作目录、`.uuplugin_uuid` 与账号状态；不把敏感文件写进镜像。不要公开共享该卷、日志或原始 UUID。**没有证据证明官方插件只依赖该文件**，仍需真实跨重建绑定验证。
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

CI 在隔离 Docker bridge（私有桥接网络）中额外尝试最长约 20 秒的官方插件运行与 TCP/16000 观察，不使用宿主网络，不保存设备身份，也不向日志输出插件原始内容。它会比较非 root（普通用户）、root（管理员身份但无网络管理权限）以及仅隔离网络命名空间内具备 NET_ADMIN 的测试，严禁将最后一种配置复制到 host 网络部署。诊断失败会使主测试明确失败，结果必须逐项检查。测试生成的 UUID 只是固定虚拟样本，不是网易真实设备身份。官方插件下载地址可能采用 HTTP，仓库原有 MD5 校验不能替代加密传输与强签名，正式版需要单独解决供应链验证风险。\n\nCI 完成门槛 1/2 不能自动升级门槛 3/4。受限权限导致 UU 插件不能运行时，请记录现象，不要直接打开 `privileged`（特权模式）、挂载 `docker.sock` 或更改宿主机防火墙。
