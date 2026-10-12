# 网易 UU 远程开机 · 路由器助手

![网易 UU 远程开机路由器助手：设计概览图](docs/images/uu-doc-00-overview.png)

*项目功能概览（设计示意图，不代表任何型号已经通过实际远程唤醒验收）。*

让具备 OpenWrt 等环境的路由器，有机会成为网易 UU 远程开机的辅助设备。**自动识别环境、获取并校验官方插件、引导测试与安装**，不用自己挑选一堆命令。

> 非网易官方项目。**不是所有路由器都能安装**；设备型号和固件须满足条件，手机移动网络实际唤醒成功才算验证通过。

## 按平台下载（测试打包，尚非正式发行版）

项目提供自动构建的分平台 ZIP（压缩包），测试通过后可在 [GitHub Actions：Platform ZIP packages](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/workflows/platform-packages.yml) 对应成功任务的测试附件中下载（需要 GitHub 登录）。**目前未创建正式 Releases 发布版，不要把测试 ZIP 当成所有同架构设备均已验证。**

| 包名 | 适用环境 | 安装验证范围 |
| --- | --- | --- |
| `uu-helper-openwrt-x86_64.zip` | OpenWrt / iStoreOS x86_64 | 已验证的仅为当前 iStoreOS x86_64 实机样本 |
| `uu-helper-openwrt-aarch64.zip` | OpenWrt ARM64 | 候选测试包，不保证任意型号可安装 |
| `uu-helper-openwrt-mipsel-y1-beta.zip` | Lenovo Y1 / Newifi mini R6830 | **实验版**，重启自启与长期稳定性尚待志愿者验收 |
| `uu-helper-xiaoqiang-aarch64.zip` | 小米 / 红米 XiaoQiang ARM64 固件 | 已验证参考型号为 Redmi AX6000；其他型号仍需验证 |
| `uu-helper-asuswrt.zip` | 华硕 ASUSWRT / 梅林 | **官方集成优先，只提供检测辅助，不覆盖原厂 UU** |

解压后 Windows 用户可使用 `start-windows.cmd` 上传助手，其他用户可按手动教程上传并运行 `sh uu-helper.sh start`。压缩包带有设备平台与处理器限制，选错包会拒绝安装相关操作；全部只包含项目开源脚本，**不附带网易闭源插件**，使用时才通过官方接口下载并校验。

开发者可运行 `python3 scripts/build-platform-packages.py --output dist` 在本地生成五个确定性 ZIP 和 `SHA256SUMS.txt`（校验清单）；正式对外稳定版仍须等待对应设备完成实机验收。

## 新手快速开始（3 步）

**第 1 步｜设置电脑唤醒。** 打开 Windows **UU远程 → 远程开机配置**，按提示开启主板和网卡的 WOL（网络唤醒）。建议电脑使用网线，并先确认局域网内能唤醒。

**第 2 步｜启动路由器助手。** 路由器需要已开启 SSH（远程登录），并能用管理员账号登录。点击 GitHub 的 **Code → Download ZIP**，解压后双击 **`start-windows.cmd`**，输入路由器地址。助手会自动上传文件，打开数字菜单。

首次连接请核对 SSH 指纹；可能需要输入几次路由器密码。**这一步只启动助手，不会自动安装插件。**

<details>
<summary>看图操作：下载与 Windows 启动</summary>

![GitHub 下载步骤示意图（非真实网页截图）](docs/images/uu-doc-01-download.png)

![Windows 连接助手示意图（非真实设备截图）](docs/images/uu-doc-02-windows.png)

*两张均为操作示意图；图中的 `router.example.invalid` 是测试地址。*

</details>

**第 3 步｜先运行插件，再绑定和远程开机。** 按数字菜单的设备提示完成适用的运行步骤；**只有路由器上的 UU 插件正在运行时**，才用连接该路由器 Wi-Fi 的手机打开 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器**，查找并添加路由器。在电脑 **UU远程** 中刷新、选择该辅助设备并完成本机配置，确认账号对应。最后关闭手机 Wi-Fi，使用**移动数据**尝试唤醒电脑。仅下载插件或出现云连接，不等于完成了手机绑定。

**只有电脑真正被远程唤醒才算成功**，插件在线不代表远程开机成功。

### 其他使用方式与注意事项

非 Windows 用户或快速启动失败，可按 [手动上传教程](docs/MANUAL-SETUP.md) 上传文件后运行：

```sh
cd /tmp/uu-remote-wol-router-helper
sh uu-helper.sh start
```

助手自动识别设备并显示可用菜单；是否能安装仍取决于设备及固件。**网易 UU 已直接支持的路由器优先使用官方方案；Lenovo Y1 的移动数据远程开机已在临时运行中获得实机成功反馈。正式通用 MIPS（处理器架构）安装仍然禁用，但现已提供**仅限 Lenovo Y1、需主动确认的实验性持久安装方案**，将官方插件在开机后下载校验并运行于内存中；实机重启和卸载尚待志愿者验证。** 具备本地恢复条件的测试者可查看 [Lenovo Y1 专用试用说明](docs/OPENWRT.md#lenovo-y1自愿试用的持久启动方案尚待真机验收) 与 [Issue #1](https://github.com/coolhpj/uu-remote-wol-router-helper/issues/1)。

<details>
<summary>查看路由器菜单示例</summary>

![OpenWrt ARM64 菜单：根据真实 QEMU 日志排版，不是直接截图](docs/images/uu-doc-03-openwrt-qemu.png)

*根据 [QEMU ARM64 虚拟机测试日志](https://github.com/coolhpj/uu-remote-wol-router-helper/actions/runs/38160517622) 排版，并非真实屏幕截图；其他设备菜单可能不同。*

</details>

更多信息：[高级操作教程](docs/MANUAL-SETUP.md) · [设备兼容矩阵](docs/COMPATIBILITY.md)。

---

## 你应该看到什么？

完整链路应该是：

```text
手机移动数据
    ↓
网易 UU 云端
    ↓
家里常在线的辅助设备
    ↓
局域网 Magic Packet
    ↓
关机 PC 开机
```

只满足下面这些情况都还不能算最终成功：

- `uuplugin` 进程存在；
- 路由器能联网；
- UU主机加速能看到路由器；
- 局域网里手工 WOL 能开机。

最终验收必须是：**手机关闭 Wi‑Fi，仅使用移动数据，把真正关机的 PC 唤醒。**

## 实机验证结果与设备状态

| Router / Environment | Platform | Remote WOL | 说明 |
|---|---|---:|---|
| Redmi AX6000 / RB06 | XiaoQiang / OpenWrt-derived | ✅ | 已完成真实冷启动、UU 云连接、移动数据 Remote WOL |
| ASUS RT-AX86U | ASUSWRT / Merlin-KoolShare | ✅ | 官方/model-specific 路径；本项目默认不覆盖官方集成 |
| iStoreOS x86_64 样本 | Generic OpenWrt | ✅ | 已完成持久安装、reboot、自启动、Remote WOL、rollback 与再次 reboot |
| Lenovo Y1 / Newifi mini R6830 | OpenWrt / MIPS | ✅（临时运行） | 2026-10-12 实机通过手机移动数据远程开机；尚未验证持久安装、重启及回滚，**禁止正式安装** |
| 其它 Generic OpenWrt | OpenWrt | 待逐台验证 | 架构相同不等于自动兼容 |

> `✅` 仅表示该设备/样本已有真实移动数据远程开机证据。**临时运行成功不等于已完成永久安装或重启回滚验收**；Lenovo Y1 仍是实验性设备，不标记为完整 Verified（已验证）。

完整兼容矩阵：[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)

下图是实测环境中 UU主机加速识别 ASUS RT-AX86U 与 OpenWrt 辅助设备的脱敏截图：

![UU主机加速识别 ASUS RT-AX86U 与 OpenWrt 辅助设备](docs/images/uu-openwrt-device.webp)

## 最常见的几个问题

### 路由器后台像运营商光猫，没有插件市场，也没有 SSH/root

这类设备通常**不适合直接使用本项目**。不要为了 UU远程去动 TR069、VLAN、运营商 WAN 等配置。

优先使用 Android / 常开电脑作为 UU 辅助设备，或者在光猫后面增加一台真正支持 UU/OpenWrt 的路由器。

### 路由器已经被 UU主机加速识别，但 UU远程仍提示没有辅助设备

先检查：

- UU主机加速与 UU远程是否处于正确的同账号关系；
- 当前 PC 是否单独完成过一次远程开机配置；
- 是否先在 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器** 添加了**正在运行 UU 插件**的路由器；
- 路由器上的 UU 是否真正建立云连接，而不是只有进程存在。

### 同一个账号下有多台 PC，为什么只有一台能开？

每台 PC 都要分别完成自己的 WOL / 远程开机配置，不会因为同账号自动继承。

### `diagnose` 显示 `platform: unknown`

不要拿其它型号脚本硬套。运行：

```sh
sh uu-helper.sh collect-info
```

提交脱敏报告后再适配。

## 安全边界

本项目：

- **不提供**破解、漏洞利用或绕过设备安全限制取得 SSH/root 的教程；
- **不提交**网易 `uuplugin`、`xuplugin-guardian`、`xtables-nft-multi` 等闭源二进制；
- 运行时只从网易官方通道获取插件，并进行完整性校验；
- 未知设备默认只允许 `Detect → Collect → Redact → Report`，不会自动猜型号安装；
- Generic OpenWrt 的一个样本通过，不代表所有 OpenWrt 自动兼容。

安全说明：[`SECURITY.md`](SECURITY.md)

SSH/root 边界：[`docs/SSH-ACCESS.md`](docs/SSH-ACCESS.md)

## 想看技术细节？

README 只保留普通用户真正需要看的内容。实现、实验和平台差异放在下面：

- 完整设备矩阵：[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)
- Generic OpenWrt / iStoreOS：[`docs/OPENWRT.md`](docs/OPENWRT.md)
- XiaoQiang / Redmi AX6000：[`docs/XIAOQIANG.md`](docs/XIAOQIANG.md)
- ASUSWRT：[`docs/ASUSWRT.md`](docs/ASUSWRT.md)
- 多辅助设备行为：[`docs/MULTI-AUX-DEVICE.md`](docs/MULTI-AUX-DEVICE.md)
- 贡献新设备：[`CONTRIBUTING.md`](CONTRIBUTING.md)

## 项目原则

本项目来自真实设备排障，并大量使用 AI 辅助分析和代码生成。因此维护规则很简单：

> **Verified（已验证）必须来自真实硬件证据，不能来自 AI 推测。**

任何 AI 生成代码进入可写入路由器的路径前，都必须有明确安全门、回滚设计、自动测试和真实设备证据。

## License / 许可证与署名

本项目使用 [MIT License](LICENSE)。

Copyright (c) 2026 **coolhpj and contributors**.

MIT 许可证允许使用、复制、修改、合并、发布、分发、再许可和商业使用；但在重新发布本项目代码或其 substantial portions（主要部分）时，**必须保留原版权声明和 MIT 许可文本**。

如果你基于本项目制作衍生版本，欢迎同时注明原始项目来源，方便用户找到上游更新与兼容性说明：

<https://github.com/coolhpj/uu-remote-wol-router-helper>

> 注：回链到原仓库是推荐做法；MIT 许可证的强制要求是保留版权声明和许可文本，不额外增加限制。

