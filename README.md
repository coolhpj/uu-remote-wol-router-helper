# UU Remote WOL Router Helper｜网易 UU远程开机路由器辅助设备

> 非官方社区项目 / Unofficial community project. Not affiliated with NetEase.

这是一个面向 **网易 UU远程开机 / Wake-on-LAN（WOL）** 的路由器辅助设备项目。针对官方没有直接提供插件入口、但具备 **OpenWrt / iStoreOS / XiaoQiang（小米/Redmi 路由器）** 等环境和合法 SSH/root 权限的设备，提供平台诊断、网易官方包校验、受控安装与回滚；ASUSWRT 则优先识别并引导使用厂商/网易官方集成。

当前真实验证样本包括 **Redmi AX6000 / RB06、ASUS RT-AX86U、iStoreOS x86_64**。其它 Generic OpenWrt 设备仍需逐台验证，不因架构相同自动继承兼容结论。

## 先看这里：你的路由器可能根本不需要本项目

**第一件事不是敲命令，而是先用网易 UU 主机加速器检查你的路由器能不能直接走官方方案。**

手机先连接到这台路由器的 Wi‑Fi，然后打开 **网易 UU 主机加速器**：

1. 点 **“路由器加速”**；
2. 点 **“合作款路由器”**；
3. 扫描 / 添加当前路由器；
4. 如果能识别到你的型号，就优先按 UU 的官方提示完成绑定或插件安装，**不要使用本项目**；
5. 完成后再回到 **UU远程 → 远程开机配置**，重新扫描 / 刷新辅助设备。

> **账号一定要对上：** 手机里的 **网易 UU 主机加速器** 和 Windows 电脑上的 **UU远程** 必须处于正确的同一账号关系。我们真实排障时就遇到过“路由器插件已经在线、UU主机加速器也能看到路由器，但 UU远程仍提示没有辅助设备”的情况，最后问题就在账号关系没有对应正确。
>
> 在 UU 主机加速器里这里找的是 **“合作款路由器”**，不要点成“UU加速盒 / Steam 硬件 / UU加速棒”。

官方说明：

- **网易官方：华硕、小米路由器怎么装 UU 插件来辅助开机？** <https://www.uuremotepro.com/faq-article?id=wol-plugin>
- **网易官方：哪些路由器能当远程开机的辅助设备？** <https://www.uuremotepro.com/faq-article?id=wol-router>
- 如果上面的直达页发生跳转，可进入 **网易 UU远程帮助中心** <https://www.uuremotepro.com/faq>，搜索：`哪些路由器能当远程开机的辅助设备？`
- **网易官方完整远程开机教程：** <https://www.uuremotepro.com/faq-article?id=wol-setup>

### 怎么选？

| 你的情况 | 最省事的做法 |
|---|---|
| 路由器在网易官方支持列表里 | **直接用官方方法，本项目不用装** |
| 路由器不支持，但家里有常开 Android / Windows / macOS | **优先把它当 UU 辅助设备，本项目也可以不用装** |
| 运营商光猫/封闭路由器，没有 SSH/root | **不要硬刷，改用 Android / 常开电脑辅助设备** |
| OpenWrt / iStoreOS / XiaoQiang，已有合法 SSH/root | 可以继续看下面的本项目教程 |

网易官方说明中，局域网辅助设备并不只有路由器，也可以是保持在线的 Windows/macOS、开启 WOL 辅助功能的 Android，或 UU 加速盒。因此**能用官方简单方案，就不要为了使用本项目去破解或刷路由器。**

---

# 小白教程：只看这 3 步

**第 1 步｜先让电脑支持唤醒。** Windows 上打开 **UU远程 → 远程开机配置**，按官方向导启用 BIOS（主板固件）与网卡 WOL（局域网唤醒）。电脑优先连接有线网络；可先用局域网设备验证电脑能被唤醒。

**第 2 步｜把助手放进路由器，打开菜单。** 仅适用于你已经合法拥有 SSH/root（管理员远程终端）权限的路由器。先从 GitHub 下载仓库 ZIP（压缩包）并解压，通过 WinSCP/SCP（文件传输工具）将整个目录上传到：

```text
/tmp/uu-remote-wol-router-helper
```

通过 SSH 登录路由器，在刚上传的代码目录中运行 **统一入口**：

```sh
cd /tmp/uu-remote-wol-router-helper
sh uu-helper.sh start
```

程序自动识别路由器与处理器、展示可用操作，用 **0–6 数字菜单**引导检查、官方下载校验、受控测试或恢复；你不必自己选择 `asuswrt`、`openwrt` 或 `xiaoqiang` 的脚本。**不支持的机型不会出现正式安装操作。**

> 已在网易 UU「合作款路由器」中直接支持的设备，优先走官方方案，不必用本工具。MIPS（处理器架构）机型如 Lenovo Y1 目前仍是实验性支持，菜单禁止持久安装。任何临时运行或持久安装均需要确认，绝不会因进入菜单就自动修改路由器。

**第 3 步｜绑定网易账号，验证真正远程开机。** 手机先连接家中 Wi-Fi，打开 **网易 UU 主机加速器 → 路由器加速 → 合作款路由器**，按提示添加路由器；确保与 Windows **UU远程** 使用正确的账号关系。在 Windows UU远程里刷新辅助设备、逐台配置电脑。最后关闭手机 Wi-Fi，**仅用移动数据**尝试唤醒关机的电脑。

**真正唤醒成功才算通过**，插件启动或连上云端不代表成功。

需要特殊机型说明、传统手动命令或故障排查？查看 [高级操作教程](docs/MANUAL-SETUP.md) 和 [设备兼容矩阵](docs/COMPATIBILITY.md)。

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

## 已验证设备 / 环境

| Router / Environment | Platform | Remote WOL | 说明 |
|---|---|---:|---|
| Redmi AX6000 / RB06 | XiaoQiang / OpenWrt-derived | ✅ | 已完成真实冷启动、UU 云连接、移动数据 Remote WOL |
| ASUS RT-AX86U | ASUSWRT / Merlin-KoolShare | ✅ | 官方/model-specific 路径；本项目默认不覆盖官方集成 |
| iStoreOS x86_64 样本 | Generic OpenWrt | ✅ | 已完成持久安装、reboot、自启动、Remote WOL、rollback 与再次 reboot |
| 其它 Generic OpenWrt | OpenWrt | 待逐台验证 | 架构相同不等于自动兼容 |

> `✅` 只用于已经有真实移动数据远程开机证据的设备/样本，不因为插件能启动就标记兼容。

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

