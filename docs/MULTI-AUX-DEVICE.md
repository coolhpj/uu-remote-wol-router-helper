# 多个 UU远程辅助路由器：当前已知事实与 A/B/C 验证方法

> 本页记录实测现象与待验证假设。网易公开文档目前没有明确说明：同一 UU 账号、同一台待唤醒 PC 存在多个合格辅助路由器时，是否同时绑定、如何选择、是否自动故障转移。

## 当前已验证事实

当前样本环境同时有：

- ASUS RT-AX86U 自带/官方集成 UU runtime；
- NAS 虚拟机中的 iStoreOS / Generic OpenWrt `openwrt-x86_64` runtime；
- 两者使用同一 UU 账号；
- 同一台 Windows PC 已配置 UU远程 WOL。

实测得到：

1. AX86U 与 iStoreOS UU 同时在线时，UU远程配置页显示“华硕路由器”。
2. 暂停 AX86U UU、保留 iStoreOS UU 后，配置页切换为通用“路由器”。
3. 在只有 iStoreOS UU 参与的实验条件下，手机关闭 Wi-Fi、仅使用移动数据，已成功唤醒 Windows。
4. iStoreOS 的 UU主机加速识别依赖客户端默认网关这一点已在当前样本观察到：手机默认网关指向 iStoreOS 时，UU主机加速可识别并绑定 OpenWrt。
5. 在之后不重新扫码、不重新配置 PC 的前提下，仅恢复 AX86U UU、停止 iStoreOS UU，手机关闭 Wi-Fi、仅使用移动数据，Windows 仍成功被远程开机。
6. 因此可以排除“配置 iStoreOS 后旧华硕辅助路径被简单覆盖删除”这一种最简单解释；但仍不能据此断言网易云端一定永久同时绑定多个辅助设备，或一定存在固定 failover/优先级规则。
7. 在 AX86U 与 iStoreOS UU 同时在线的 C 实验中，手机仅使用移动数据触发远程开机后，LAN 抓包明确捕获到由 AX86U 发出的标准 WOL：一组为 UDP/9 的 102-byte Magic Packet，紧接着又出现一组 EtherType `0x0842` 的原生 Magic Packet；同一抓包窗口内没有观察到 iStoreOS 发出对应 WOL 广播。约 29 秒后，Magic Packet 目标网卡开始发出 DHCP/局域网流量，与 Windows 实际开机时间链一致。

## 不能直接下结论的事情

当前**不能**把以下说法写成官方事实：

- “一个 PC 只能绑定一个辅助路由器”；
- “一个 PC 可以永久同时绑定多个辅助路由器”；
- “华硕优先级一定高于 OpenWrt”；
- “主辅助设备离线时网易一定自动 failover 到第二台”；
- “App 页面显示哪个名字，就一定是哪台设备实际发出的 Magic Packet”。

这些都需要对照实验或网易官方后续说明。

## A/B/C 对照实验

实验期间**不要重新扫码、不要重新配置 PC**，否则会引入新的绑定变量。

### A — iStoreOS-only

```text
AX86U UU: OFF
iStoreOS UU: ON
PC WOL 配置: 保持不变
手机: 仅移动数据
```

当前样本结果：**Remote WOL 成功**。

意义：证明 iStoreOS/OpenWrt 可以独立承担该次 WOL 辅助链路。

### B — AX86U-only

```text
AX86U UU: ON
iStoreOS UU: OFF
PC WOL 配置: 不重新扫码、不重新配置
手机: 仅移动数据
```

状态：**已完成，Remote WOL 成功**。

实测条件：

- AX86U UU：ON；
- iStoreOS UU：OFF；
- PC：未重新扫码、未重新配置；
- 手机：关闭 Wi-Fi，仅使用 5G/移动数据；
- 结果：Windows 成功远程开机。

判读：

- 旧华硕辅助路径在 iStoreOS 配置/绑定实验之后仍然可用；
- 这至少说明旧路径没有被简单覆盖删除；
- 但仅凭 B 成功仍无法区分“PC 同时保留多个辅助设备”与“网易云端动态选择其它合格辅助设备”，因此仍需 C 实验抓取实际 Magic Packet 发送证据。

### C — 双在线 + 抓 WOL 证据

```text
AX86U UU: ON
iStoreOS UU: ON
PC WOL 配置: 保持不变
同时观察两台设备的 WOL 发送证据
```

状态：**已完成，双在线时由 AX86U 发出实际 WOL。**

实测条件：

- AX86U UU：ON；
- iStoreOS UU：ON；
- PC：保持原配置，不重新扫码；
- 手机：关闭 Wi-Fi，仅使用移动数据；
- 在同一 LAN bridge 上抓取广播 UDP 与 WOL EtherType。

抓包结果：

- 捕获到 AX86U 发出的 UDP/9、102-byte Magic Packet；
- 紧接着捕获到 AX86U 发出的 EtherType `0x0842` 原生 Magic Packet；
- 两个包都指向同一目标网卡；
- 约 29 秒后该目标网卡开始发出 DHCP/局域网流量，证明对应主机已上线；
- 同一捕获窗口内未观察到 iStoreOS 发出对应 WOL 广播。

判读：

- 在**当前这一组样本和当前配置状态**下，双在线时实际执行唤醒的是 AX86U；
- 这与配置页此前显示“华硕路由器”的现象一致；
- 但仍不能把它推广成网易官方固定优先级规则，也不能据此声称所有双辅助环境都必然优先 ASUS。

## 排障建议

在同账号多路由器环境中，如果 UU远程一直显示另一台路由器：

1. 不要先修改 BIOS、网卡 WOL 或重新安装插件；
2. 先确认候选辅助路由器的 `uuplugin / guardian / :16000`；
3. 把“同账号下其它 UU 路由器是否同时在线”作为独立变量；
4. 使用 A/B/C 对照，而不是反复扫码覆盖配置；
5. 最终以真实移动数据 WOL 与必要的发包证据为准。

## 发布口径

公开 README 只能写“当前样本观察到的行为”，不得写成网易官方优先级规则。若后续找到网易官方关于多辅助设备/故障切换的明确说明，再用官方资料更新本页。
