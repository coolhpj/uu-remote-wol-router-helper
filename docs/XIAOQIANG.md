# XiaoQiang / 小米系适配说明

本页描述小米/Redmi XiaoQiang 固件家族的社区适配边界。当前完整实机验证样本是 **Redmi AX6000 / RB06**。

## 当前已验证样本

- Device: Redmi AX6000
- Device ID: RB06
- Firmware family: XiaoQiang / OpenWrt-derived
- Architecture: AArch64 / MT7986
- Historical UU channel: `openwrt-aarch64`
- Historical verified UU version: `v14.6.24`
- Persistent plugin directory: `/userdisk/appdata/2882303761518031252`
- Persistent helper directory: `/data/uu-v14`
- Startup method: UCI `firewall include`

> 版本号是 2026-08-30 实机验证时的历史事实。项目代码必须从网易官方 API 动态读取当前包与 MD5，不能写死版本。

## 为什么不用 `/etc/rc.local`

RB06 实测中，手工修改 `/etc/rc.local` 后模拟执行可以工作，但真实 reboot 后文件恢复为原厂内容。因此它不能作为本项目的可靠持久入口。

最终验证通过的方向是：

```text
/data 持久脚本
      ↓
UCI firewall include
      ↓
等待真实 WAN/API 可用
      ↓
启动 UU
      ↓
检查 :16000 ESTABLISHED
      ↓
首次失败自动重试一次
```

## 当前只读工具

### 平台检测

```sh
sh platforms/xiaoqiang/detect.sh
```

只读取：

- CPU 架构；
- UCI 是否存在；
- `xiaoqiang.common.NETMODE`；
- `/etc/config/xiaoqiang`；
- `/data` 与 `/userdisk/appdata` 是否存在/可写。

不会修改系统。

### UU 健康检查

```sh
sh platforms/xiaoqiang/health.sh
```

默认检查 RB06 已验证插件目录。其他设备可显式指定：

```sh
UU_PLUGIN_DIR=/path/to/plugin sh platforms/xiaoqiang/health.sh
```

健康检查把以下状态分开：

- monitor 是否运行；
- `uuplugin ./uu.conf` 是否运行；
- `xuplugin-guardian` 是否运行；
- `:16000` 是否真正处于 ESTABLISHED。

**进程在线不能替代云连接在线。**

## 已提取的 RB06 runtime 模板

最终实机验证过的运行层逻辑已经整理到：

```text
platforms/xiaoqiang/runtime/
├── uuplugin_monitor.sh
├── xnetease-uu
└── auto.sh
```

这些文件本身是**已验证运行模板**，现在已经被当前 XiaoQiang legacy-migration installer 复用。`auto.sh` 保留了本次真实冷启动故障最终修复的核心：等默认路由与网易 API、检查 `:16000`、首次失败自动重启一次。

仓库还提供离线回归测试，模拟“第一次云连接失败、第二次启动成功”，防止后续重构把这条关键恢复逻辑删掉。

## 临时 smoke-test（尚未实机复验）

当前实现已经加入 `platforms/xiaoqiang/smoke-test.sh` 保护壳，但它**暂时没有接入 `uu-helper.sh`**，因为还没有用 RB06 对这份重写后的脚本做第二次真实运行态复现。

保护条件包括：

- 默认拒绝执行；
- 必须显式设置 `UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE`；
- 必须先通过 XiaoQiang preflight；
- staging 包必须存在并重新通过 MD5 / tar 结构检查；
- 如果检测到已有 `uuplugin / guardian / monitor` 运行，还必须设置 `UU_ALLOW_STOP_EXISTING=YES`；
- 已有运行态必须存在已验证的 `xnetease-uu` 恢复 wrapper，否则在停止任何进程前拒绝执行；
- 临时测试结束后停止 staging 版本，并尝试恢复原运行态；
- 不写持久目录、不注册自启动。

只有 runtime、guardian、`:16000` 全部通过并完成原运行态恢复后，smoke-test 才会在 staging 目录生成与官方包 MD5 绑定的 `smoke-pass` 证据。未来持久安装器必须校验这个证据，不能因为 staging 成功就直接覆盖系统。

在 RB06 对重写脚本完成真实复验之前，本项目不会把它标记为可公开使用的 smoke-test 命令。

## 持久化 migration adapter（受控迁移）

当前已经加入：

- `platforms/xiaoqiang/install.sh`
- `platforms/xiaoqiang/rollback.sh`
- `platforms/xiaoqiang/persist-common.sh`

第一版**故意只支持本项目已经实机验证过的 legacy migration 路径**，不把“裸 RB06 从零安装”冒充成已验证能力。执行前必须同时存在：

- `/userdisk/appdata/2882303761518031252/manifest`
- `/userdisk/appdata/2882303761518031252/start_script`
- `/userdisk/appdata/installPlugin/2882303761518031252.json`
- `start_script` 中可确认的 `xnetease-uu` 引用
- 与当前官方包 MD5 绑定的 XiaoQiang `smoke-pass`

迁移会完整备份旧插件目录、旧 `/data/uu-v14` helper、旧 installPlugin JSON，以及原 `firewall.uuplugin` 的 type/path/enabled 状态；然后写入官方 staged runtime、已验证 monitor/wrapper/boot-helper，更新 Xiaomi 元数据中的显示版本，并注册本轮实机验证过的：

```text
firewall.uuplugin=include
firewall.uuplugin.type='script'
firewall.uuplugin.path='/data/uu-v14/auto.sh'
firewall.uuplugin.enabled='1'
```

`rollback.sh` 会恢复上述旧文件和旧 firewall include。当前不提供 destructive uninstall：因为本路径本质是“迁移已有 Xiaomi 插件”，在没有裸机 fresh-install 实机证据之前，rollback 比删除整套插件更安全。

fake-root 回归已经覆盖：默认拒绝、smoke-pass 闸门、fresh install fail-closed、官方四文件迁移、manifest/JSON 动态版本更新、firewall include 注册、完整 rollback 恢复。

**尚未在朋友 RB06 上用这份重写后的 installer 做第二次实机迁移复现**，因此不能把这条重写后的 installer 路径标记为 RB06 实机复验完成。

## 公开安装路径尚未开放的原因

当前实现不会因为检测到 `aarch64 + XiaoQiang` 就直接覆盖插件。

要把这条重写 installer 路径升级为 RB06 实机复验完成，至少还需要：

1. 识别具体设备/固件；
2. 确认不是 AP 模式；
3. 检查 `/tmp` 与持久区空间；
4. 查询网易官方 API；
5. 稳健解析 `status / md5 / url / url_bak`；
6. 下载官方包并验证 MD5；
7. 解压到 `/tmp` staging；
8. 验证预期文件存在；
9. **临时运行 smoke test**；
10. 确认 UU 云连接；
11. 备份旧插件；
12. 才允许持久替换；
13. 写 monitor / wrapper / boot helper；
14. 注册 UCI firewall include；
15. 真实 reboot；
16. 验证 App、账号绑定和手机移动数据 WOL。

任何一步失败都应在进入下一阶段前停止。

## RB06 已验证的官方包结构

2026-08-30 的 `openwrt-aarch64 v14.6.24` 临时解压目录中，已验证包含：

```text
uuplugin
uu.conf
xuplugin-guardian
xtables-nft-multi
```

社区适配器额外生成/维护的启动辅助文件不应假定由网易 tar 包提供。

## AP 模式

RB06 的旧适配逻辑会读取：

```sh
uci -q get xiaoqiang.common.NETMODE
```

`wifiapmode` / `lanapmode` 不进入当前 WOL helper 启动流程。未来通用 adapter 也应保持保守策略：不能确认网关/路由工作模式时，不自动安装。
