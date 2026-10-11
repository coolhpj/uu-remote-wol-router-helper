# 传统命令安装与特殊机型说明（高级用户）

> 这份内容从旧版 README 移入。普通用户请返回 [三步入门](../README.md#小白教程只看这-3-步)，直接使用数字菜单。
> 不要绕过底层安装脚本的安全检查。未验证机型不能因为系统架构相同就当作支持。


## 第 1 步：先把电脑自己的 WOL 配好

在需要远程开机的 Windows 电脑上：

1. 打开 **UU远程**；
2. 进入设置，开启 **“允许通过远程开机启动”**；
3. 按 UU远程里的“开始配置 / 开始协助”向导，把网卡 WOL 和 BIOS WOL 配好；
4. 电脑最好使用**有线网卡**连接路由器。

这一步不会因为装了路由器插件而自动完成。电脑本身不能被 Magic Packet 唤醒，后面怎么折腾路由器都没用。

官方图文教程：<https://www.uuremotepro.com/faq-article?id=wol-setup>

## 第 2 步：准备一个一直在线的“辅助设备”

### A. 官方支持的路由器

如果你的型号在网易官方列表里：

**按官方方法安装/开启 UU 插件即可，下面的命令全部跳过。**

### B. 没有 SSH/root 的路由器或运营商光猫

不要硬装本项目。

最简单的是：找一台旧 Android 手机，长期插电并连接家里 Wi‑Fi，在 UU远程 App 的设置中开启 **“远程开机支持 Wake on LAN”**。也可以使用另一台常开的 Windows/macOS。

### C. OpenWrt / iStoreOS / XiaoQiang，且你已经有 SSH/root

先把本仓库放到路由器的 `/tmp`。

最简单的方法：电脑端点击 GitHub 的 **Code → Download ZIP**，解压后用 WinSCP / SCP 上传整个目录到：

```text
/tmp/uu-remote-wol-router-helper
```

如果路由器本身有 Git，也可以：

```sh
git clone https://github.com/coolhpj/uu-remote-wol-router-helper.git /tmp/uu-remote-wol-router-helper
```

然后 SSH 进入路由器，执行：

```sh
cd /tmp/uu-remote-wol-router-helper
sh uu-helper.sh diagnose
```

只看输出里的这一行：

```text
platform: ...
```

### 如果显示 `platform: asuswrt`

**停止。** ASUSWRT 优先走厂商/网易官方集成，本项目不会自动覆盖 `/jffs/uu`。

### 如果显示 `platform: unknown`

**停止，不要猜型号安装。** 只运行：

```sh
sh uu-helper.sh collect-info
```

把脱敏后的输出提交 Issue，等待适配。

### 如果显示 `platform: openwrt`

> **MIPS 路由器暂时不要执行下面的完整安装命令。** 目前 `mipsel_24kc` / `openwrt-mipsel` 仍是实验性兼容；Lenovo Y1 / MT7620A 已在真机完成官方包校验，临时启动时观察到守护程序运行及网易云连接，但**移动数据远程唤醒连续两次失败**，其中一次插件在第 264 秒提前退出，仍待排查辅助设备绑定与网络拓扑。仅在 [Issue #1](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1) 最新指引及路由器可本地恢复条件下，使用独立的 `platforms/openwrt/mips-runtime-smoke.sh` 临时测试；它可能触发 `fw4 reload` 并短暂中断网络，清理失败必须人工检查。通用 `smoke-test.sh` 对该 MIPS 架构继续禁止启动；真实 MIPS 持久安装也继续被程序主动拦截。**不要直接执行通用安装或设置开机自启。**

对于其它已经确认适配路径且具备真实设备验证条件的 OpenWrt 环境，可以按下述受控步骤执行：

```sh
sh uu-helper.sh preflight && \
sh uu-helper.sh stage auto && \
UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE sh platforms/openwrt/smoke-test.sh && \
UU_PERSIST_INSTALL_CONFIRM=PERSIST_OPENWRT_UU sh platforms/openwrt/install.sh
```

这组命令使用 `&&` 串联：**任何一步失败，后面的步骤都会停止。** 不要跳过失败步骤硬装。

需要恢复安装前状态时：

```sh
UU_ROLLBACK_CONFIRM=ROLLBACK_OPENWRT_UU sh platforms/openwrt/rollback.sh
```

### 如果显示 `platform: xiaoqiang`

当前只支持**已有 Xiaomi/UU legacy metadata 的受控迁移路径**，不是所有小米/Redmi 路由器都能直接安装。

复制执行：

```sh
sh uu-helper.sh preflight && \
sh uu-helper.sh stage auto && \
UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE sh platforms/xiaoqiang/smoke-test.sh && \
UU_XQ_INSTALL_CONFIRM=MIGRATE_XIAOQIANG_UU sh platforms/xiaoqiang/install.sh
```

如果提示已有 UU runtime、legacy metadata 不完整或其它错误，**到这里停止，不要手工伪造文件或随便加确认参数。**

需要回滚：

```sh
UU_XQ_ROLLBACK_CONFIRM=ROLLBACK_XIAOQIANG_UU sh platforms/xiaoqiang/rollback.sh
```

## 第 3 步：先用手机绑定路由器，再测试“人在外面开机”

如果第 2 步使用本项目完成了持久安装，建议先**手工重启一次路由器**，确认持久安装真的能在冷启动后恢复。

> `/tmp` 通常会在 reboot 后被清空，所以**不要指望重启后仓库目录还在**。普通用户不需要为了验收再次上传仓库；如果后续需要 SSH 技术诊断，再重新把仓库上传到 `/tmp` 后运行 `sh uu-helper.sh diagnose`。

### 3.1 先安装手机端「网易 UU 主机加速器」

这一步很重要：**手机上需要的是「网易 UU 主机加速器」，不是 Windows 上的「UU远程」。这两个是不同客户端。**

1. 在手机应用商店搜索并安装 **网易 UU 主机加速器**；
2. 登录后，手机先连接到家里这台路由器的 **Wi‑Fi**；
3. 进入 **路由器加速 → 合作款路由器 → 扫描 / 添加路由器**；
4. 能识别到当前路由器后，按页面提示完成绑定或插件识别。

> 在「网易 UU 主机加速器」里要找的是 **合作款路由器**，不要点成“UU加速盒 / Steam 硬件 / UU加速棒”。

### 3.2 再确认账号对应关系

> 手机 **网易 UU 主机加速器** 登录的账号，必须和 Windows **UU远程** 当前使用的账号正确对应。否则即使路由器里的 `uuplugin` 已经联网、手机也能识别路由器，Windows UU远程仍可能找不到辅助设备。

### 3.3 回到 Windows UU远程刷新辅助设备

1. 打开 Windows **UU远程 → 远程开机配置**；
2. 重新扫描 / 刷新辅助设备；
3. 确认刚才绑定的路由器已经出现在辅助设备里；
4. 给**每一台需要远程开机的 PC 分别配置一次远程开机**。

### 3.4 最后做真正的外网测试

1. 正常关闭目标 PC；
2. 手机关闭 Wi‑Fi，只保留**移动数据**；
3. 打开手机 **UU远程**，点击目标 PC 的“远程开机”。

**关机 PC 真正被移动数据远程唤醒，才算成功。**
