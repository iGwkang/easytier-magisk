# easytier-magisk

[EasyTier](https://github.com/EasyTier/EasyTier) for Magisk，以 root 方式在 Android 上运行官方 `easytier-core`，支持官方 `config.toml` 全量字段与绝大部分命令行参数（守护相关参数除外）。

- 支持架构：`arm`（armeabi-v7a）、`arm64`、`x64`（x86_64）
- 安装目录：`/data/adb/modules/easytier-magisk`
- 数据目录：`/data/adb/easytier-magisk`

## 功能

- 官方 `config.toml` 全量配置：IPv4/IPv6、DHCP、监听协议、子网代理、出口节点、WireGuard 门户、端口转发、SOCKS5、ACL、安全模式、STUN、端口白名单、全部 `flags`。
- 官方 CLI 参数：存在 `/data/adb/easytier-magisk/command_args` 时作为 `easytier-core` 参数，可使用 `--config-server`、`--config-dir`、`--no-tun` 等官方选项；支持引号与反斜杠转义。
- Web 管理界面：内置 `easytier-web-embed`，可开启官方 Web UI/配置服务器，并可选让本机节点由该界面托管。
- 进程守护：崩溃自动重启、配置错误时进入慢重试并写入模块状态。
- 日志：官方文件日志轮转 + 控制台日志，统一位于 `/data/adb/easytier-magisk/log`。
- 热点 NAT：可选把热点/USB 网络共享客户端流量经虚拟网络转发。
- 模块禁用即停止；守护进程仍在运行（未重启设备）时重新启用会自动恢复。

## 使用

1. 安装模块并重启设备。
2. 编辑 `/data/adb/easytier-magisk/config.toml`：填写 `ipv4`，或把 `dhcp` 改为 `true`，否则节点只转发流量、不创建 TUN。
3. 点击 Magisk 模块的“操作”按钮重启并查看节点状态与最近日志。

### 运行配置

`/data/adb/easytier-magisk/module.conf` 控制模块自身行为，升级不覆盖：

| 配置项 | 说明 |
| --- | --- |
| `CONFIG_FILE` | 配置文件路径 |
| `CUSTOM_HOSTNAME` | 固定主机名；留空自动使用“品牌-型号” |
| `RPC_PORTAL` | `easytier-cli` 与核心的 RPC 地址（默认仅本机） |
| `EASYTIER_LOG_LEVEL` / `EASYTIER_LOG_SIZE_MB` / `EASYTIER_LOG_COUNT` | 文件日志级别与轮转 |
| `WEB_ENABLE` / `WEB_ADDR` / `WEB_PORT` / `WEB_CONFIG_PORT` | Web 管理界面开关、监听地址与端口 |
| `WEB_ARGS` | 追加给 `easytier-web-embed` 的官方参数，支持引号 |
| `WEB_MANAGE_LOCAL` / `WEB_MANAGE_TOKEN` | 让本机节点由本机 Web 配置服务器托管 |
| `HOTSPOT_NAT` | `1` 开启热点/USB 共享 NAT |

### 启动参数模式（官方 CLI）

把 `/data/adb/easytier-magisk/command_args.sample` 重命名为 `command_args`：

```text
# 通过配置服务器下发配置
--config-server udp://1.2.3.4:22020/admin --machine-id android-phone

# 多配置文件，含空格的路径用引号
-c "/data/adb/easytier-magisk/a b.toml" -c /data/adb/easytier-magisk/b.toml

# 指定 TUN 名称，热点 NAT 会自动识别
-c /data/adb/easytier-magisk/config.toml --dev-name et0
```

存在有效参数时不再传 `-c config.toml`。支持空格分隔、单/双引号、反斜杠转义和 `#` 整行注释；未写 `--machine-id` 时会自动补一个保存在数据目录的稳定 ID。
不支持 `--daemon`（守护由模块负责）和 `--check-config`、`--gen-autocomplete` 等一次性参数。

### Web 管理界面

```sh
WEB_ENABLE=1
WEB_ADDR=0.0.0.0   # 默认 127.0.0.1，仅本机；局域网访问再改
```

重启后访问 `http://<设备IP>:11211` 注册账号。

要让本机节点由这个 Web 界面管理（而不是只管理外部接入的节点），注册后在 `module.conf` 设置：

```sh
WEB_MANAGE_LOCAL=1
WEB_MANAGE_TOKEN=<刚注册的用户名>
```

重启后 core 以 `-w <协议>://127.0.0.1:<WEB_CONFIG_PORT>/<用户名> --machine-id <稳定ID>` 运行，配置由 Web 界面下发，`config.toml` 不再使用。若同时存在 `command_args`，则仍以 `command_args` 为准。
其他设备也可接入本机配置服务器：

```text
--config-server udp://<设备IP>:22020/<用户名> --machine-id <固定ID>
```

公网使用请限制端口访问或设置 `WEB_ARGS="--disable-registration"`。

### 热点共享

```sh
HOTSPOT_NAT=1
```

模块会把热点、USB 网络共享、非默认以太网接口的客户端流量 NAT 到 EasyTier TUN：源地址改写为虚拟 IP，对端按虚拟网段回程，无需在对端配置 `proxy_network`。运行中改回 `HOTSPOT_NAT=0` 后 watcher 会在 10 秒内清理规则。

### 日志

```text
/data/adb/easytier-magisk/log/module.log          # 守护进程日志
/data/adb/easytier-magisk/log/core.console.log    # 核心控制台输出
/data/adb/easytier-magisk/log/core/               # 核心官方文件日志
/data/adb/easytier-magisk/log/web.console.log     # Web 管理界面输出
/data/adb/easytier-magisk/web/et.db               # Web 数据库
/data/adb/easytier-magisk/machine-id              # 自动生成的稳定设备标识
```

### 命令行

```sh
/data/adb/modules/easytier-magisk/easytier/arm64/easytier-cli peer
/data/adb/modules/easytier-magisk/easytier/arm64/easytier-cli route
/data/adb/modules/easytier-magisk/easytier/arm64/easytier-cli acl stats
```

## 已知限制

- 仅支持 `arm` / `arm64` / `x64`；32 位 x86 Android 无官方 Linux 构建，安装时会拒绝。
- `accept_dns`（Magic DNS）核心会启动 DNS 服务，但 Android 应用通过 netd 解析，不会自动读取 `/etc/resolv.conf`；需要应用级 DNS 时请自行通过 netd/iptables 重定向。
- 热点 NAT 依赖 `iptables`，仅处理 IPv4；不支持 nftables-only 且无 iptables 兼容层的系统。
- 为让 main 表里的 EasyTier 路由生效，模块会插入 `pref 30000 from all lookup main`（IPv4/IPv6）。若与其他 VPN/分流方案冲突，可自行删除该规则或调整 `common.sh` 中的 `ET_RULE_PREF`。
- 本机 Web 托管模式（`WEB_MANAGE_LOCAL=1`）下由 Web 界面保存配置，`config.toml` 不再生效。

## 卸载

在 Magisk 中卸载模块会停止进程、清理 NAT 规则与策略路由，并删除 `/data/adb/easytier-magisk`。
