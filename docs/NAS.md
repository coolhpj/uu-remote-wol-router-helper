# Docker 版｜路由器插件模式（支持 NAS）

这个版本在 Docker 中运行网易 UU **路由器插件身份**，适用于部分路由器、NAS 和常开的 Linux 主机。普通非网关 NAS 可能遇到发现或绑定问题。

**如果想用独立辅助设备身份，请改看 [Docker 独立辅助设备模式](NAS-WOL-ONLY-BETA.md)。** 两种模式的账号绑定和数据卷不能混用。

## 下载与准备

[下载固定源码 ZIP](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/28a25816101b68e8fc269109942c2f465f0e5b72.zip) · [实验代码 PR #16](https://github.com/coolhpj/uu-remote-wol-router-helper/pull/16) · [测试反馈 #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15)

- 需要 Linux、Docker Engine、Docker Compose 和可联网构建的环境。优先 x86_64；ARM64 仅通过自动构建测试。
- QNAP、群晖、飞牛、极空间是否能直接运行 Compose，取决于各自系统和版本；NAS 图形容器管理器未必支持源码构建，建议使用终端。
- 先确认目标电脑已设置 WOL，NAS 和电脑在能传递局域网唤醒广播的网络里。
- ZIP 是源码，不是现成镜像，也不附带网易闭源插件。启动时按校验规则从官方通道获取插件。

## 安装（在 NAS / Linux 终端）

把 ZIP 解压到不会被自动清理的目录，进入**解压后的仓库根目录**，先检查：

```sh
sh scripts/nas-preflight.sh
docker compose config --quiet
```

两项检查通过后，再构建并启动：

```sh
docker compose build
docker compose up -d --no-build
docker compose ps
```

`NAS_PREFLIGHT_OK` 只代表基本环境检查通过，不表示 UU 已能远程开机。此版使用 `host` 网络、非 root 用户、只读根文件系统及受限权限，**不需要**特权容器或 Docker socket 挂载；不要为了排错自行开启这些权限。

## 绑定和实测

1. 在手机网易 UU App 中按**合作款路由器**方式尝试添加这个辅助设备，在电脑的「UU远程」完成远程开机配置。
2. 手机关闭 Wi-Fi、只使用移动数据，尝试唤醒自己已关机的电脑。
3. 只有电脑真的开机才算成功。绑定成功后，还需要分别测试容器重建和 NAS 重启后是否保持原绑定。

有问题时，在原安装目录查看日志：

```sh
docker compose logs --tail=60 uu-wol
```

**暂停或退出测试**：

```sh
docker compose stop
docker compose down
```

`down` 默认保留设备身份卷。**不要添加 `-v`**，否则会删除绑定数据；升级前先备份身份卷。不要同时运行两种模式并让它们共用数据。

## 反馈

在 [Issue #15](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/15) 简单说明 NAS/系统/CPU、能否构建、能否绑定、移动数据能否真正唤醒，以及重启后是否仍有效。

不要公开二维码、Token、UUID/SN、MAC/IP、NAS 密码或完整原始日志。

本版本尚未完成普通 NAS 的远程唤醒实机验收，不能当作稳定版；[已有五平台路由器测试包](https://github.com/coolhpj/uu-remote-wol-router-helper/releases/tag/v0.1.0-beta.2)也**不包含**本 Docker 镜像。

**开发说明：** 本项目部分代码、测试和文档由 **ChatGPT（OpenAI GPT-6）协助开发**，维护者审核发布。非网易官方项目。
