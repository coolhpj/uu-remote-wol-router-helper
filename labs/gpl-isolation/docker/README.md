# GPL 独立辅助设备 Docker 隔离候选（尚非公开安装版）

> **当前仅供隔离实验审查。** 本目录并不是 [PR #16](https://github.com/coolhpj/uu-remote-wol-router-helper/pull/16) 已发布的“路由器插件身份” NAS 源码测试版。这里采用另一种网易 UU 远程辅助设备身份，GPL-3.0-or-later 的上游 Linux 客户端始终与 MIT 主分支分开。未完成真实服务端/实机唤醒与 NAS 重启持续性验证，不要把这一候选误当稳定版。

## 工作内容与安全边界

- Docker 构建阶段下载精确的 GPL 上游固定提交，在本地临时源码里应用 `../apply-wol-only.py`，无需复制/合并 GPL Rust 源码到 MIT 项目。
- 可执行程序**没有完整远控入口**：唯一交互子命令是 `login --no-gui`，常驻服务强制要求 `UU_WOL_ONLY=1`；其余命令在初始化音频、输入、桌面和远控会话之前被拒绝。
- 指定唯一 MAC 和 LAN 接口，同网段限制，UDP/9 单包定向广播；不要求 root、Docker socket、`privileged`、`NET_ADMIN` 或公网映射端口，但使用 **host 网络**（网络暴露不等于容器隔离）。
- 身份与账号凭据保存在**独立命名卷** `uu_wol_only_data`。不要把它与 PR #16 的路由器 UUID/SN 数据卷混用。

## 隔离环境中准备复验的方法（暂勿用于正式生产 NAS）

**需要**：Linux x86_64、Docker Engine / Compose、GitHub 可访问、可联网构建 Rust、与目标设备同一可广播 LAN，以及预先配置 WOL 的待唤醒 PC。当前 ARM64 的这个独立 GPL 镜像尚未验收。

只有在 Owner 批准进入真实云端/真实 NAS 测试之后，才在隔离测试宿主上执行以下步骤：

1. 在**本 GPL 诊断分支**获取代码，在 `labs/gpl-isolation/docker/` 将 `.env.example` 复制成只属于本机的 `.env`，填写自己明确允许的 PC MAC 和 NAS LAN 接口。不要将 `.env`、`config.json` 或二维码上传至 GitHub。
2. 在该目录用 `docker compose --profile service config --quiet` 审查配置，再用 `docker compose --profile service build` 本机编译固定 GPL 源码（首次可能较耗时）。
3. 只用 `docker compose run --rm -it uu-wol-only login --no-gui` 发起账号二维码授权；它会在本机终端显示一次性二维码，成功后凭据以 0600 写入命名卷。扫码前要确认自己理解它正在向非官方 GPL 客户端授予账号绑定。
4. 如获准上线，用 `docker compose --profile service up -d --no-build` 启动，并以 `docker compose --profile service ps` 与脱敏日志只读核对。首次真实 WOL 应优先用**隔离测试网段的虚拟目标**验收，严禁未经许可向用户的 Windows 真实主机发包。
5. 用 `docker compose --profile service stop` 暂停；`docker compose --profile service down` 移除容器（默认保留凭据卷）。**不要使用 `down -v`** 除非明确决定注销此独立测试身份并已备份。

## 仍需完成的真实验收

1. 检查新 Docker 镜像在有授权真实房间在线时，远程桌面、终端、文件传输、WebRTC 和端口映射不可启动，且不会开放非预期监听端口。
2. 以移动数据从 UU App 发起唤醒，证实云端命令、唯一允许的 MAC、指定网卡、真实 102 字节 UDP/9 与关机 PC 开机，随后重启 NAS 验证同一云端身份继续可用。
3. 针对发行物提供完整 GPL 归属、对应源代码与补丁、SHA-256 和明确回滚方案；本目录当前是源码候选，不提供预编译可安装镜像。

本目录所有测试结论必须引用同一提交的 GitHub Actions 实际日志；只在云端编译成功**不等于**上述真实业务验收成功。
