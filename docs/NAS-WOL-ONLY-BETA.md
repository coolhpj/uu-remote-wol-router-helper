# Docker 版｜独立辅助设备模式（支持 NAS）

让常开的 NAS 或 Linux 主机作为网易 UU 远程开机的**独立辅助设备**，不要求 NAS 是主路由器。

**当前只有源码测试版**：GitHub 的 Docker 构建、离线安全检查和模拟局域网唤醒包测试已经通过，**还没有完成这个版本的手机移动数据实机唤醒验收**。优先由熟悉 Docker 的 x86_64 用户测试；ARM64 暂未验证。

## 下载和安装

[下载固定源码 ZIP](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/66707aeb20f0021b45ac5f95d4aec243197b4c41.zip) · [原始 Docker 构建文件](https://github.com/coolhpj/uu-remote-wol-router-helper/blob/66707aeb20f0021b45ac5f95d4aec243197b4c41/labs/gpl-isolation/docker/README.md) · [GitHub 测试结果](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/runs/43452562641)

在自己的测试 NAS / Linux 设备上解压 ZIP，进入 `labs/gpl-isolation/docker` 目录。

1. 把 `.env.example` 复制成 `.env`，填好**要唤醒电脑的 MAC** 和**本机局域网网卡名称**。不要公开文件或填写外网接口。
2. 在该目录构建镜像并扫码授权：

```sh
docker compose --profile service build
docker compose run --rm -it uu-wol-only login --no-gui
```

这里使用第三方开源客户端，不是网易官方程序；请在自己能管理的测试设备上使用自己的账号。

3. 启动并查看状态：

```sh
docker compose --profile service up -d --no-build
docker compose --profile service ps
```

4. 用手机移动数据尝试唤醒自己的关机电脑，随后测试 NAS 重启后能否继续唤醒。

退出测试时执行：

```sh
docker compose --profile service down
```

`down` 默认保留绑定数据。**不要添加 `-v`** 删除身份卷，也不要与路由器插件模式混用身份文件。

## 反馈与说明

请到 [Issue #23](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/23) 告诉我们设备型号、能否扫码、电脑能否开机、NAS 重启后是否有效。不要上传二维码、Token、MAC/IP、密码或完整日志。

本模式基于 [uu-remote-linux](https://github.com/VallierDev/uu-remote-linux)，源码及补丁遵守 **GPL-3.0-or-later**；不属于主项目 MIT 代码。[另一种 Docker 路由器插件模式在这里](NAS.md)。

**开发说明：** 本项目部分代码、测试和文档由 **ChatGPT（OpenAI GPT-6）协助开发**，维护者审核发布。非网易官方项目。
