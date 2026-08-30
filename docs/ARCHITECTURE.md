# Architecture / 架构设计

## 核心原则

项目不按“每个路由器型号复制一份脚本”维护，而采用：

```text
Common Core
   │
   ├── Platform Detection
   ├── Official Download / Verify
   ├── Health Check
   ├── Diagnostics
   └── Rollback Contract
          │
          ├── XiaoQiang Adapter
          ├── ASUSWRT Adapter
          ├── OpenWrt Adapter
          └── Future Vendor Adapters
                 │
                 └── Device Profiles
```

## Common Core 应负责

- 识别 CPU 架构；
- 识别固件家族；
- 识别可用平台 adapter；
- 查询网易官方插件信息；
- 下载与完整性验证；
- 统一日志格式；
- 统一健康检查；
- 统一诊断结果；
- 统一回滚约定；
- 默认脱敏采集。

Common Core 不应该知道某个型号的 `/data`、`/jffs`、UCI 或 NVRAM 细节。

## Platform Adapter 应负责

平台 adapter 只处理该固件家族的差异：

- 持久目录；
- 服务启动机制；
- firewall hook；
- UCI / NVRAM / init / procd；
- 依赖文件；
- 平台特定健康检查；
- 平台特定卸载/回滚。

## Device Profile 应负责

设备 profile 是小型数据文件，用于记录：

- vendor / model / device id；
- firmware family；
- architecture；
- matched adapter；
- UU channel；
- 已验证能力；
- 历史测试日期；
- 特殊注意事项。

设备 profile 不应该复制完整安装代码。

## 未知设备策略

默认：

```text
Unknown Device
    ↓
Read-only Detect
    ↓
Collect + Redact
    ↓
Human/AI Review
    ↓
Match existing adapter?
   ↙                ↘
 Yes                No
  ↓                  ↓
Experimental test   New platform research
```

未知设备禁止直接进入自动安装。

## WOL 成功链

本项目最终关心的是：

```text
Remote Client
   ↓
NetEase UU Cloud
   ↓
Always-on Router Helper
   ↓
LAN Magic Packet
   ↓
Target NIC / PC
```

对路由器而言，最低健康指标包括：

1. 插件进程正常；
2. 云控制连接正常；
3. App 能识别路由器；
4. 路由器与正确 UU 账号建立关系；
5. 目标 PC 单独完成远程开机配置；
6. 手机移动数据完成真实远程唤醒。

## 与 Wake-on-WAN 的关系

传统公网 Wake-on-WAN，例如：

```text
Remote Sender → Public UDP Port → Router NAT → PC UDP/9
```

可以作为备用或诊断链，但它不是本项目所描述的网易 UU 云辅助设备机制。

两者应在文档和代码中明确分开。
