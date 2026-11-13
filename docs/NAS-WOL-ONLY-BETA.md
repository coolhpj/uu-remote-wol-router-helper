# NAS 独立辅助设备版（WOL-only 测试版）

把常开的 NAS 当成网易 UU 远程开机辅助设备，帮忙唤醒家里已关机的电脑。支持 Docker 部署，不要求 NAS 是主路由器。

**当前是源码测试版，还没有完成这份代码的真实手机远程唤醒验收。** 优先由熟悉 Docker 的 x86_64 NAS 用户自愿测试；ARM64 暂未验证。

## 下载与测试

- [下载源码 ZIP（固定版本）](https://github.com/coolhpj/uu-remote-wol-router-helper/archive/66707aeb20f0021b45ac5f95d4aec243197b4c41.zip)
- [Docker 安装文件与详细说明](https://github.com/coolhpj/uu-remote-wol-router-helper/blob/66707aeb20f0021b45ac5f95d4aec243197b4c41/labs/gpl-isolation/docker/README.md)
- [GitHub 测试结果](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/runs/43452562641)：源码测试、镜像构建和模拟局域网发包通过，**不代表实机唤醒成功**。

在自己的测试 NAS 上解压源码 ZIP，进入 `labs/gpl-isolation/docker` 目录。

**第一步：** 把 `.env.example` 复制为 `.env`，填入要唤醒的电脑网卡 MAC，以及 NAS 正确的局域网网卡名称。不要公开这份文件。

**第二步：** 在该目录执行：

```sh
docker compose --profile service build
docker compose run --rm -it uu-wol-only login --no-gui
```

按终端提示，用自己的网易 UU 远程 App 扫码登录。请注意：这里用的是第三方开源客户端，不是网易官方程序。

**第三步：** 启动并查看状态：

```sh
docker compose --profile service up -d --no-build
docker compose --profile service ps
```

手机关闭 Wi-Fi，用移动数据尝试唤醒自己的电脑。成功后再测试 NAS 重启，看看是否还能唤醒。

**第四步：** 结束测试时，在同一目录执行 `docker compose --profile service down`。它会保留账号绑定数据；不要随意添加 `-v` 删除数据卷。

## 反馈

请到 [Issue #23](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/23) 留下 NAS 型号、系统、是否能扫码、是否真正开机，以及重启后是否有效即可。

**不要上传** 二维码、账号 Token、MAC/IP、完整日志和 NAS 密码。

## 和其他版本的区别

- [路由器版](../README.md#按平台下载预览测试版尚非稳定版)：适合 OpenWrt、iStoreOS 等路由器。
- [Docker 路由器模式](NAS.md)：运行路由器插件身份。
- **本版**：运行独立辅助设备身份，主要面向普通 NAS。

两种 Docker 方案不能混用身份文件。这个独立版本基于 [GPL 开源项目 uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) 改造，保留 GPL-3.0-or-later 许可，不属于主项目的 MIT 代码。

**开发说明：** 本项目部分代码、测试及文档由 **ChatGPT（OpenAI GPT-6）协助开发**，由仓库维护者审核发布。非网易官方项目。
