## 📝 更新日志（v2.3.1 → v2.3.2）

### 🚀 新功能 / Feature Enhancements

* 支持 QUIC 代理 [@KKRainbow](https://github.com/KKRainbow)
* 支持子网代理映射功能 [@KKRainbow](https://github.com/KKRainbow)
*  `easytier-core` 支持多配置文件加载 [@xzzpig](https://github.com/xzzpig)
* 添加转发带宽速率限制功能（bps limiter）[@KKRainbow](https://github.com/KKRainbow)
* Web 支持 IPv4/IPv6 双栈访问 [@BlackLuny](https://github.com/BlackLuny)
* 支持通过 命令行设置机器 UID [@KKRainbow](https://github.com/KKRainbow)
* 添加 RPC 门户白名单，默认仅允许本地访问 [@xzzpig](https://github.com/xzzpig)
* GUI / Web 支持 Toml 配置的导入、导出和编辑 [@xzzpig](https://github.com/xzzpig)


### 🐞 问题修复 / Bug Fixes

* 修复 roaming 后 WireGuard peer 表丢失的问题 [@imkiva](https://github.com/imkiva)
* 修复 OSPF 路由条目残留的问题 [@KKRainbow](https://github.com/KKRainbow)
* 修复内置 STUN 服务未使用 XOR-MAPPED 地址的问题 [@KKRainbow](https://github.com/KKRainbow)
* 移除 macOS 上 utun 设备的默认路由设置 [@KKRainbow](https://github.com/KKRainbow)
* 添加对 RPC 数据包合法性的检查（Fix #963）[@BlackLuny](https://github.com/BlackLuny)
* 更新 `default_port` 与 SNI 逻辑，提升反向代理可达性 [@thezzisu](https://github.com/thezzisu)
* 支持 `--proxy-forward-by-system` 与 `--enable-exit-node` 同时使用 [@imkiva](https://github.com/imkiva)
* KCP 支持自动重连机制 [@KKRainbow](https://github.com/KKRainbow)
* 批量压缩代替流式压缩，降低内存使用 [@KKRainbow](https://github.com/KKRainbow)
* 为 `PeerConn` 添加 `is_hole_punched` 属性，取代原打洞状态表 [@liusen373](https://github.com/liusen373)

### 📄 其他改动 / Other Changes

* 更新 core.yml，使用 UPX 4.2.4 进行打包优化 [@KKRainbow](https://github.com/KKRainbow)

## 👥 新贡献者 / New Contributors

* 🎉 @thezzisu 首次贡献于 [#947](https://github.com/EasyTier/EasyTier/pull/947)
* 🎉 @imkiva 首次贡献于 [#954](https://github.com/EasyTier/EasyTier/pull/954)
* 🎉 @BlackLuny 首次贡献于 [#953](https://github.com/EasyTier/EasyTier/pull/953)
* 🎉 @tianxiayu007 首次贡献于 [#1004](https://github.com/EasyTier/EasyTier/pull/1004)
* 🎉 @liusen373 首次贡献于 [#1001](https://github.com/EasyTier/EasyTier/pull/1001)

🔗 **完整更新记录**: [点击查看完整变更](https://github.com/EasyTier/EasyTier/compare/v2.3.1...v2.3.2)

---

## 📝 Release Notes (v2.3.1 → v2.3.2)

### 🚀 Feature Enhancements

* Added support for QUIC proxy [@KKRainbow](https://github.com/KKRainbow)
* Added subnet proxy mapping support [@KKRainbow](https://github.com/KKRainbow)
* `easytier-core` now supports loading multiple configuration files [@xzzpig](https://github.com/xzzpig)
* Added bandwidth rate limiting for forwarding traffic (bps limiter) [@KKRainbow](https://github.com/KKRainbow)
* Web interface now supports IPv4/IPv6 dual-stack access [@BlackLuny](https://github.com/BlackLuny)
* Allow setting machine UID via command line [@KKRainbow](https://github.com/KKRainbow)
* Added RPC portal whitelist, local access only by default [@xzzpig](https://github.com/xzzpig)
* GUI/Web now supports importing, exporting, and editing Toml configurations [@xzzpig](https://github.com/xzzpig)

### 🐞 Bug Fixes

* Fixed issue where WireGuard peer table was lost after client roaming [@imkiva](https://github.com/imkiva)
* Fixed OSPF route residue by adjusting route entry management [@KKRainbow](https://github.com/KKRainbow)
* Fixed internal STUN server to use XOR-MAPPED address [@KKRainbow](https://github.com/KKRainbow)
* Removed default route on macOS `utun` devices [@KKRainbow](https://github.com/KKRainbow)
* Added sanity check for incoming RPC packets (Fix #963) [@BlackLuny](https://github.com/BlackLuny)
* Improved reverse proxy reachability by updating `default_port` and SNI logic [@thezzisu](https://github.com/thezzisu)
* Enabled `--proxy-forward-by-system` to work with `--enable-exit-node` [@imkiva](https://github.com/imkiva)
* Added KCP reconnect mechanism [@KKRainbow](https://github.com/KKRainbow)
* Replaced streaming compression with bulk compression to reduce memory usage [@KKRainbow](https://github.com/KKRainbow)
* Introduced `is_hole_punched` property to `PeerConn`, replacing global punch state table [@liusen373](https://github.com/liusen373)

### 📄 Other Changes

* Updated `core.yml` to use UPX 4.2.4 for binary packing optimization [@KKRainbow](https://github.com/KKRainbow)

## 👥 New Contributors

* 🎉 @thezzisu made their first contribution in [#947](https://github.com/EasyTier/EasyTier/pull/947)
* 🎉 @imkiva made their first contribution in [#954](https://github.com/EasyTier/EasyTier/pull/954)
* 🎉 @BlackLuny made their first contribution in [#953](https://github.com/EasyTier/EasyTier/pull/953)
* 🎉 @tianxiayu007 made their first contribution in [#1004](https://github.com/EasyTier/EasyTier/pull/1004)
* 🎉 @liusen373 made their first contribution in [#1001](https://github.com/EasyTier/EasyTier/pull/1001)

🔗 **Full Changelog**: [View Full Changes](https://github.com/EasyTier/EasyTier/compare/v2.3.1...v2.3.2)


---
