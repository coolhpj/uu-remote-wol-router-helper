# XiaoQiang RB06 verified runtime templates

本目录保存从 2026-08-30 Redmi AX6000 / RB06 真实终验配置中提取的运行层模板：

- `uuplugin_monitor.sh`
- `xnetease-uu`
- `auto.sh`

它们对应的已验证链路是：

```text
UCI firewall include
        ↓
/data/uu-v14/auto.sh
        ↓
等待 default route + 网易 API
        ↓
xnetease-uu plugon
        ↓
uuplugin_monitor.sh
        ↓
uuplugin + xuplugin-guardian
        ↓
:16000 ESTABLISHED
```

## 重要边界

这些文件是 **runtime 模板，不是安装器**。

仓库目前不会自动把它们写到生产路由器。持久安装器仍需要完成：

- 设备 profile 确认；
- staging + 官方 MD5；
- 临时 smoke-test；
- 旧版本持久备份；
- 安装失败回滚；
- UCI firewall 配置备份/恢复；
- 真实 reboot 验证。

## 与最终实机配置的关系

模板保留了最终硬件验证过的关键逻辑，同时把固定路径做成可选环境变量，便于离线测试。默认值仍是 RB06 的真实路径。

`auto.sh` 最重要的不是固定延时，而是：

1. 已在线则跳过，避免 firewall reload 重复重启；
2. 等默认路由与网易 API 真正可用；
3. 第一次启动后检查 `:16000 ESTABLISHED`；
4. 未上线则自动 `plugoff → plugon` 重试一次；
5. 记录最终云连接状态。

这正是 RB06 真实冷启动中“进程在线但云连接不上”的故障修复点。
