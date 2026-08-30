# Private Review / 公开前门禁

本页用于把“代码已经完成”和“可以公开发布”严格分开。仓库在所有硬门禁完成、维护者明确确认之前保持 **Private**。

## 已完成

### 仓库与 Git 基线

- [x] 本地 Git 已安全接入远端现有历史；
- [x] 正常 `fetch / commit / push` 工作流可用；
- [x] 不使用 force push；
- [x] GitHub 仓库保持 Private；
- [x] `LICENSE / SECURITY / CONTRIBUTING / Issue Forms` 已建立；
- [x] 网易闭源二进制不进入仓库。

### 通用安全层

- [x] NetEase API parser 不依赖 JSON key 顺序；
- [x] 官方 MD5 校验；
- [x] 临时下载 URL 默认脱敏；
- [x] tar 结构校验；
- [x] 架构到官方 channel 的 fail-closed 映射；
- [x] `smoke-pass` 证据闸门；
- [x] 敏感信息扫描；
- [x] `tests/run-all.sh` 全量回归入口。

### Redmi AX6000 / RB06

- [x] 历史真实设备链路已完成手机移动数据 Remote WOL；
- [x] 最终 runtime 模板已从权威证据提取；
- [x] 重写后的 smoke-test guard 已完成离线测试；
- [x] legacy-migration installer / rollback 已完成 fake-root 回归；
- [x] 裸机 fresh install 明确 fail closed，不冒充已验证能力。

### Generic OpenWrt / iStoreOS x86_64 样本

- [x] detect / preflight / stage auto；
- [x] 官方 `openwrt-x86_64` 临时 runtime 与 UU 云连接；
- [x] UU主机加速绑定 OpenWrt；
- [x] 手机移动数据 Remote WOL 功能终验；
- [x] persistence adapter 离线回归；
- [x] 真实持久安装；
- [x] 真实 reboot 后 procd 自动恢复；
- [x] reboot 后 UU 云连接与 OpenClash 恢复。

### ASUSWRT

- [x] RT-AX86U 只读 detect / health 实机参考；
- [x] 明确“官方集成优先、Generic 项目默认不覆盖 `/jffs/uu`”的平台策略；
- [x] 不为了功能数量额外制造一个通用 ASUSWRT 覆盖式安装器。

## Public 前硬门禁

以下项目未完成前，不把仓库切为 Public：

### 1. RB06 重写代码实机复验

- [ ] 在合适窗口使用重写后的 XiaoQiang smoke-test 做一次真实复现；
- [ ] 在有明确回滚点的情况下验证 legacy-migration installer；
- [ ] 验证 rewritten rollback 能恢复安装前状态；
- [ ] 不把朋友路由器当日常调试机，失败必须立即停止扩大变更。

### 2. iStoreOS 部署链最后验收

- [ ] reboot 之后再做一次手机移动数据 Remote WOL；
- [ ] 真实执行一次 rollback；
- [ ] rollback 后确认 UU / OpenClash / 网络规则恢复到预期状态；
- [ ] 如需要继续保留实验安装，再重新按已验证路径安装，而不是手工拼回文件。

### 3. 多辅助设备行为收口

见 [`MULTI-AUX-DEVICE.md`](MULTI-AUX-DEVICE.md)。

- [x] A：iStoreOS-only 已完成 Remote WOL；
- [ ] B：AX86U-only、PC 不重新配置；
- [ ] C：两边同时在线并抓 WOL/Magic Packet 证据；
- [ ] README 最终只能写实测行为，不把样本现象写成网易官方优先级规则。

### 4. GitHub Actions 真正上线

- [x] `.github/workflows/ci.yml` 本地内容已准备；
- [ ] 当前 `gh` OAuth Token 增加 `workflow` scope；
- [ ] 正常 push workflow；
- [ ] 至少观察一次 GitHub 云端 Actions 全绿。

### 5. 最终公开前安全审计

- [ ] 再跑一次全仓库 sensitive scan；
- [ ] 检查历史 commit 是否包含不应公开的真实 IP/MAC/账号/临时 key；
- [ ] 检查 README 和设备档案没有把测试环境的私网地址写成通用配置；
- [ ] 确认仓库不包含原始完整聊天、PDF、第三方闭源 UU 二进制或未授权第三方代码。

## 推荐完成，但不是代码正确性的硬阻塞

### README 证据图

- [ ] 从权威 PDF/原始截图中挑少量证据图；
- [ ] 裁剪并脱敏；
- [ ] 不上传完整聊天/PDF；
- [ ] 当前工具链缺少安全的二进制文件导入通道，因此不使用 base64/网页编辑器硬塞。

图片是发布质量增强项；如果其它硬门禁全部通过，也可以先发布纯文本 v0.x，再补图。

### 第三设备 RS2

- [ ] 先确认准确型号、固件、CPU 架构；
- [ ] 再决定进入哪个 platform adapter；
- [ ] 当前资产库只有“RS2”名字，没有足够事实，禁止猜型号建档。

RS2 是扩展兼容面的样本，不是 v0.x 首次公开的必要条件。

## 当前明确不支持/不承诺

- XiaoQiang 裸机 fresh install：**未实机验证，当前 installer 会 fail closed**；
- ASUSWRT Generic 覆盖安装：**设计上默认不提供**，优先厂商官方集成；
- UU 游戏加速与任意 Clash/sing-box 透明代理同时开启：**不属于 WOL-only 兼容承诺**；
- 未知品牌/型号自动安装：**禁止**，只能 Detect → Collect → Redact → Report；
- 多辅助路由器 failover/优先级：网易公开文档未明确，项目只记录实测。

## 切 Public 前最后动作

只有硬门禁全部通过后：

1. 全量测试；
2. 全量敏感扫描；
3. GitHub Actions 云端全绿；
4. README / compatibility / security 最终人工复核；
5. 创建第一个 pre-release/tag（如需要）；
6. **由维护者明确确认后**再把仓库从 Private 切换为 Public。

项目不会把“代码已经能运行”自动等同于“可以公开”。
