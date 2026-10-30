# MediaTek Filogic (MT7981/MT7986) 闭源无线驱动与 LuCI 集成深度审查与优化建议报告

本文档针对 `gavin8282/g-openwrt` 仓库中的两大核心分支（`openwrt-24.10` 基于官方 v24.10.8 / 内核 6.6；`openwrt-25.12` 基于官方最新 25.12 / 内核 6.12）以及 `gavin8282/Actions-OpenWrt` 云端编译工程，开展系统性技术审查。重点对 **MTK 闭源无线驱动栈（`kmod-mt_wifi` + `warp` + `conninfra`）**、**无线配置转化管道（`mtwifi-cfg` + `datconf`）**、**LuCI 前端界面交互（`luci-app-mtwifi-cfg` + `wireless-mtk.js` + `network.js`）**、**双频合一与 802.11k/v/r 快速漫游守护进程（`mtwifi-wapp` + `bs20` + `startwapp.sh`）**、**芯片级硬件加速（HNAT / PPE）** 以及 **GitHub Actions 云端 CI 构建体系** 进行了全链路诊断，并给出了具体代码级的修复与优化方案。

---

## 目录
1. [审查背景与测试基准](#一审查背景与测试基准)
2. [问题总览与严重性矩阵](#二问题总览与严重性矩阵)
3. [核心缺陷逐项深度剖析与根因追踪](#三核心缺陷逐项深度剖析与根因追踪)
   - [缺陷 1：mtwifi-cfg 运行时缺失 Lua 解释器与 nixio 库 (Critical)](#缺陷-1mtwifi-cfg-运行时缺失-lua-解释器与-nixio-库-critical)
   - [缺陷 2：luci.turboacc 探针缺失 LuCI Lua 运行环境 (High)](#缺陷-2luciturboacc-探针缺失-luci-lua-运行环境-high)
   - [缺陷 3：OpenWrt 25.12 下 iwinfo 依赖闭环死锁 (High)](#缺陷-3openwrt-2512-下-iwinfo-依赖闭环死锁-high)
   - [缺陷 4：wireless-mtk.js 与 mtwifi_cfg 频段/模式双向失步 (Medium)](#缺陷-4wireless-mtkjs-与-mtwifi_cfg-频段模式双向失步-medium)
   - [缺陷 5：startwapp.sh 漫游阈值误读 5G 节点与 MAC 获取脆弱性 (Medium)](#缺陷-5startwappsh-漫游阈值误读-5g-节点与-mac-获取脆弱性-medium)
   - [缺陷 6：turboacc 服务开机暴力覆盖 min_free_kbytes (Medium)](#缺陷-6turboacc-服务开机暴力覆盖-min_free_kbytes-medium)
   - [缺陷 7：LuCI network.js 编译期未预植入 MTK 网卡正则 (Medium)](#缺陷-7luci-networkjs-编译期未预植入-mtk-网卡正则-medium)
   - [缺陷 8：25.12-mtk7981_dae.config 设备爆炸隐患 (Medium)](#缺陷-82512-mtk7981_daeconfig-设备爆炸隐患-medium)
   - [缺陷 9：Actions 工作流配置文件路径双重前缀容错 (Low)](#缺陷-9actions-工作流配置文件路径双重前缀容错-low)
4. [全链路代码级落地方案与补丁集](#四全链路代码级落地方案与补丁集)
   - [源码仓库：openwrt (24.10 与 25.12 分支)](#1-源码仓库-openwrt-2410-与-2512-分支)
   - [配置仓库：Actions-OpenWrt (main 分支)](#2-配置仓库-actions-openwrt-main-分支)
5. [系统全流程验证方法](#五系统全流程验证方法)

---

## 一、审查背景与测试基准

* **代码基线**：
  - **openwrt-24.10**：对齐官方 OpenWrt `v24.10.8` 稳定发布版（Linux 内核 6.6.144），植入 padavanonly 闭源无线与 HNAT 加速驱动栈；
  - **openwrt-25.12**：对齐官方 OpenWrt 25.12 开发主线（Linux 内核 6.12），植入 chasey-dev 闭源驱动补丁与 6.12 兼容模块；
  - **Actions-OpenWrt**：云端全自动流水线，采用多 profile 设备矩阵打包，内置 `diy-part1.sh` 与 `diy-part2.sh` 脚本定制层。
* **审查重点**：
  验证在现代 OpenWrt（Firewall4/nftables、原生 JS/ucode LuCI 架构）环境下，传统 MTK 闭源驱动组件（基于 ioctl/WEXT、Lua 配置生成器、独立守护进程）能否形成无缝协同，是否存在隐蔽语法错误、依赖断裂、进程崩溃及网络震荡风险。

---

## 二、问题总览与严重性矩阵

| 编号 | 缺陷模块 | 影响范围 | 级别 | 核心现象与危害 |
| :---: | :--- | :--- | :---: | :--- |
| **01** | **`mtwifi-cfg` 运行时缺失 Lua 解释器与 Nixio** | 24.10 / 25.12 固件 | **🚨 致命 (Critical)** | 固件缺失 `/usr/bin/lua` 与 `nixio.so`，netifd 初始化驱动直接崩溃，**Wi-Fi 彻底无法起网** |
| **02** | **`luci.turboacc` 探针缺失 LuCI Lua 运行环境** | 24.10 / 25.12 LuCI | **🔴 严重 (High)** | 缺少 `luci-lua-runtime`，访问 TurboACC 页面触发 RPC 报错或界面空白卡死 |
| **03** | **OpenWrt 25.12 下 `iwinfo` 机制互斥锁死** | 25.12 固件 | **🔴 严重 (High)** | `WIFI_SCRIPTS_UCODE=y` 导致标准 C `iwinfo` 被架空，而定制 `iwinfo-ucode` 又被互斥标志阻断，终端 `iwinfo` 彻底失效 |
| **04** | **`wireless-mtk.js` 与 `mtwifi_cfg` 频段下发失步** | 24.10 / 25.12 LuCI | **🟡 中等 (Medium)** | LuCI 界面存在 `hwmode` 时仅更新 `hwmode`，后台 `mtwifi_cfg` 仅检测 `band`，导致 `WirelessMode` 为空，频段初始化异常 |
| **05** | **`startwapp.sh` 漫游阈值误读 5G 节点与 MAC 获取脆弱** | 24.10 / 25.12 漫游栈 | **🟡 中等 (Medium)** | 判定 2.4G 漫游时误读 5G 配置（`default_MT7981_1_2`），且首开机时 `br-lan` MAC 获取易抛错 |
| **06** | **`turboacc` 初始化脚本暴力覆盖 `min_free_kbytes`** | 24.10 / 25.12 系统栈 | **🟡 中等 (Medium)** | 开机将内存保护水位强制降为 4096KB，冲掉 24MB 安全保护线，高吞吐并发+dae 时易触发丢包 |
| **07** | **LuCI `network.js` 编译期未预植入 MTK 网卡正则** | Actions CI 阶段 | **🟡 中等 (Medium)** | 仅在首开机 uci-defaults 中替换，若升级固件或缓存未刷，LuCI 会将 `ra0`/`rax0` 识别为有线网卡 |
| **08** | **`25.12-mtk7981_dae.config` 设备全选爆炸** | Actions CI 阶段 | **🟡 中等 (Medium)** | 配置文件勾选了 100+ 款设备，若触发 `device_preset: ALL`，必定耗尽 GitHub Actions 磁盘空间或超时 |
| **09** | **Actions 工作流配置文件路径双重前缀容错** | Actions CI 阶段 | **🟢 提示 (Low)** | 工作流传参已带 `configs/` 前缀，配置加载第一分支产生双重 `configs/configs/` 冗余查找 |

---

## 三、核心缺陷逐项深度剖析与根因追踪

### 缺陷 1：mtwifi-cfg 运行时缺失 Lua 解释器与 nixio 库 (Critical)

#### 1. 现象与危害
固件刷入路由器后，无任何 Wi-Fi 信号发出；查看系统日志（`logread | grep netifd`），发现大量报错：
```
/lib/netifd/wireless/mtwifi.sh: line 105: /sbin/l1util: not found
/lib/netifd/wireless/mtwifi.sh: line 114: /sbin/mtwifi_cfg: not found
```
或者即使手动安装了 lua，也会报错：
```
lua: /sbin/mtwifi_cfg:19: module 'nixio' not found
```
导致 MTK 驱动配置文件（`.dat`）无法生成，硬件无线射频无法加电初始化。

#### 2. 技术根因深度追查
- **架构断层**：OpenWrt 官方自 23.05 起全面淘汰了基于 Lua 的 Web 运行时，将 LuCI 核心重构为前端原生 JavaScript，后端管理探针转向 ucode。因此，**在现代 OpenWrt 官方基线中，`lua` 解释器与 `nixio` 不再作为默认系统组件打包**。
- **构建依赖虚标**：
  在 [`package/mtk/applications/mtwifi-cfg/Makefile`](file:///home/G/github/openwrt/package/mtk/applications/mtwifi-cfg/Makefile) 中：
  ```makefile
  define Package/mtwifi-cfg
    TITLE:=mtwifi configure scripts for mt798x
    DEPENDS:=+iwinfo +wifi-dats +lua-cjson +datconf-lua
  endef
  ```
  `datconf-lua` 和 `lua-cjson` 仅声明了 `DEPENDS:=+liblua`（这仅仅是提供 `liblua.so.5.1` 动态链接库的库文件包），**根本没有依赖 `+lua`**（生成 `/usr/bin/lua` 命令行解释器的可执行包）。
  同时，`/sbin/mtwifi_cfg`（第 19 行）和 `/usr/lib/lua/l1dat_parser.lua`（第 151 行）显式声明：
  ```lua
  local nixio = require "nixio"
  ```
  而 `mtwifi-cfg` 的 `DEPENDS` 完全遗漏了 `+luci-lib-nixio`。
- **配置层失守**：
  检查 `Actions-OpenWrt/configs/` 下的 `24.10-mtk7981_dae.config` 和 `25.12-mtk7981_dae.config`，通过 `make defconfig` 实际求解后，由于没有显式启用，产物 `.config` 中赫然存在：
  ```make
  # CONFIG_PACKAGE_lua is not set
  # CONFIG_PACKAGE_luci-lib-nixio is not set
  ```
  这使得编译出的 rootfs 中既无 `/usr/bin/lua`，也无 `/usr/lib/lua/nixio.so`，脚本首行 `#!/usr/bin/lua` 触发内核 `execve` 找不到解释器直接报 127 退出码。

---

### 缺陷 2：luci.turboacc 探针缺失 LuCI Lua 运行环境 (High)

#### 1. 现象与危害
进入 LuCI 管理页面点击 `网络 -> Turbo ACC 硬件加速`，页面弹窗报错 `RPC error: Command failed` 或界面无响应、状态灯无法刷新。

#### 2. 技术根因深度追查
- [`/usr/libexec/rpcd/luci.turboacc`](file:///home/G/github/openwrt/package/mtk/applications/luci-app-turboacc-mtk/root/usr/libexec/rpcd/luci.turboacc) 是由 rpcd 调用的后端探测服务，文件头部：
  ```lua
  #!/usr/bin/env lua
  local json = require "luci.jsonc"
  local fs   = require "nixio.fs"
  local util = require "luci.util"
  local sys  = require "luci.sys"
  ```
- 检查 [`package/mtk/applications/luci-app-turboacc-mtk/Makefile`](file:///home/G/github/openwrt/package/mtk/applications/luci-app-turboacc-mtk/Makefile)：
  ```makefile
  LUCI_TITLE:=LuCI support for MTK HNAT
  LUCI_DEPENDS:=+kmod-tcp-bbr @!PACKAGE_luci-app-turboacc
  ```
  未声明任何与 Lua 运行时相关的依赖（`+luci-lua-runtime +luci-lib-nixio`）。在新版系统环境下，rpcd 执行该探针时会直接死于 `module 'luci.jsonc' not found`。

---

### 缺陷 3：OpenWrt 25.12 下 iwinfo 依赖闭环死锁 (High)

#### 1. 现象与危害
在 OpenWrt 25.12 固件中，在终端执行 `iwinfo` 命令无法查询 MTK 闭源网卡状态（提示 `No such wireless device: ra0` 或直接报错），且 LuCI 某些依赖终端命令行的状态感知组件失灵。

#### 2. 技术根因深度追查
- **25.12 官方策略**：OpenWrt 25.12 默认开启了 `CONFIG_WIFI_SCRIPTS_UCODE=y`。
  查看 [`package/network/utils/iwinfo/Makefile`](file:///home/G/github/openwrt/package/network/utils/iwinfo/Makefile)：
  ```makefile
  ifdef CONFIG_WIFI_SCRIPTS_UCODE
    define Package/iwinfo/install
      :
    endef
  ```
  官方把传统 C 编译的 `iwinfo` 命令行安装过程掏空，改由 `wifi-scripts` 提供基于 ucode 的 `/usr/bin/iwinfo`。但 `wifi-scripts` 的脚本只引入了 `import * as nl80211 from 'nl80211'`，对 MTK 闭源无线驱动的 private ioctl / WEXT 体系一无所知。
- **上游修复与本地依赖互斥死锁**：
  chasey-dev 在 25.12 分支开发了 `package/network/utils/iwinfo-ucode` 包，并通过 `99-replace-iwinfo` 试图在检测到脚本版 `iwinfo` 时进行替换。
  然而在 `iwinfo-ucode/Makefile` 中写着：
  ```makefile
  define Package/iwinfo-ucode
    DEPENDS:=+ucode-mod-iwinfo @!PACKAGE_iwinfo
  endef
  ```
  这里带有 `@!PACKAGE_iwinfo` 强互斥。而移植过来的 `mtwifi-cfg/Makefile` 中硬编码了 `DEPENDS:=+iwinfo ...`。
  Kconfig 解析器在处理时发现 `PACKAGE_iwinfo` 被 `mtwifi-cfg` 强行选定为 `=y`，从而**无情地禁用了 `iwinfo-ucode`**。
  结果就是：`iwinfo` 选了但不装文件，`iwinfo-ucode` 想装却被互斥规则禁止，用户最终只能拿到一个不支持 MTK 的残缺版 `wifi-scripts` 脚本。

---

### 缺陷 4：wireless-mtk.js 与 mtwifi_cfg 频段/模式双向失步 (Medium)

#### 1. 现象与危害
用户在 Web 页面修改 Wi-Fi 频宽（如 20MHz 改为 160MHz）或调整无线信道并点击保存应用后，无线射频未能正确应用 802.11ax 模式，握手协商速率受限，甚至被降级为旧版模式。

#### 2. 技术根因深度追查
- **前端保存逻辑缺陷**：
  在 [`wireless-mtk.js`](file:///home/G/github/openwrt/package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js#L566-L574) 的 `CBIWifiFrequencyValue.write` 中：
  ```javascript
  uci.set('wireless', section_id, 'htmode', value[0] || null);

  if (this.useBandOption)
      uci.set('wireless', section_id, 'band', value[1]);
  else
      uci.set('wireless', section_id, 'hwmode', (value[1] == '2g') ? '11g' : '11a');

  uci.set('wireless', section_id, 'channel', value[2]);
  ```
  当初始配置中存在 `hwmode` 时，`this.useBandOption` 会被置为 `false`。此时 LuCI 写入 `/etc/config/wireless` 时**只会更新 `hwmode`，完全不会写入 `band` 字段**。
- **后台解析逻辑偏执**：
  进入驱动转换后台 [`/sbin/mtwifi_cfg`](file:///home/G/github/openwrt/package/mtk/applications/mtwifi-cfg/files/mtwifi-cfg/mtwifi_cfg#L430-L499)：
  ```lua
  local WirelessMode
  if cfg.config.band == "2g" then
      if string.sub(cfg.config.htmode,1,2) == "HE" then
          WirelessMode = 16 -- PHY_11AX_24G
      else
          WirelessMode = 9  -- PHY_11BGN_MIXED
      end
  elseif cfg.config.band == "5g" then
      if string.sub(cfg.config.htmode,1,2) == "HE" then
          WirelessMode = 17 -- PHY_11AX_5G
      else
          WirelessMode = 15 -- PHY_11VHT_N_MIXED
      end
  end
  ...
  set_dat(dats, apidx, "WirelessMode", WirelessMode)
  ```
  `mtwifi_cfg` **只认 `band` 字段，根本没有读取 `hwmode` 作为回退机制**。一旦 UCI 中仅有 `hwmode` 而无 `band`，`WirelessMode` 变量直接变成 `nil`，最终写入 `mt7981.dbdc.b0.dat` 中的 `WirelessMode=` 为空，触发 MTK 底层驱动 fallback 到默认配置或报配置解析错误。

---

### 缺陷 5：startwapp.sh 漫游阈值误读 5G 节点与 MAC 获取脆弱性 (Medium)

#### 1. 现象与危害
- 开启 802.11v 漫游转向后，在 LuCI 修改 2.4GHz 的漫游阈值（`steeringthresold`），后台并没有激活 2.4G 漫游逻辑；反而在只修改 5GHz 漫游阈值时，2.4G 进程却被意外拉起。
- 路由器开机初期，热插拔接口过早触发 `100-startwapp`，因 `br-lan` 尚未建立导致日志抛出 `cat: /sys/class/net/br-lan/address: No such file or directory`，并将 `1905d.cfg` 的 ALID 设为空值。

#### 2. 技术根因深度追查
在 [`package/mtk/applications/mtwifi-cfg/files/wapp/startwapp.sh`](file:///home/G/github/openwrt/package/mtk/applications/mtwifi-cfg/files/wapp/startwapp.sh)：
- **行 90-94（明显的复制粘贴错误）**：
  ```sh
  ra0_7981="$(uci_get_default wireless.default_MT7981_1_2.steeringthresold 0)"
  ra0_7986="$(uci_get_default wireless.default_MT7986_1_2.steeringthresold 0)"
  if [ "$ra0_7981" -lt "0" ] || [ "$ra0_7986" -lt "0" ]; then
      ra0=1
  fi
  ```
  根据 `l1profile.dat`，`MT7981_1_1` 是 2.4G（`ra0`），`MT7981_1_2` 是 5G（`rax0`）。此处判定 `ra0`（2.4G）是否需要拉起漫游时，居然读取的是 `default_MT7981_1_2`（5G 接口）的配置！应当修正为 `default_MT7981_1_1`。
- **行 35（缺少降级防御）**：
  ```sh
  br0_mac=$(cat /sys/class/net/br-lan/address)
  ```
  直接裸读取系统文件，未做容错处理。

---

### 缺陷 6：turboacc 服务开机暴力覆盖 min_free_kbytes (Medium)

#### 1. 现象与危害
在大流量并发下载、BT 跑满千兆带宽或运行 `dae` eBPF 透明代理时，路由器出现内核偶发丢包，或 `dmesg` 抛出 `page allocation failure: order:0, mode:0x...`。

#### 2. 技术根因深度追查
- 在 `Actions-OpenWrt/diy-part2.sh` 中，我们为系统精心注入了 `98-adaptive-tuning`：
  ```sh
  # 针对 512MB MT7981 路由器设置 24MB 安全保护线
  vm.min_free_kbytes = 24576
  ```
- 然而在 [`package/mtk/applications/luci-app-turboacc-mtk/root/etc/init.d/turboacc`](file:///home/G/github/openwrt/package/mtk/applications/luci-app-turboacc-mtk/root/etc/init.d/turboacc#L113) 内部：
  ```sh
  echo 4096 > /proc/sys/vm/min_free_kbytes
  echo 3 > /proc/sys/vm/drop_caches
  ```
  `turboacc` 的启动顺序是 `START=90`，它在系统启动末期执行，**直接将 `min_free_kbytes` 强行改回了极小的 4MB (4096)**，并且无缘无故清空了系统的 PageCache。4MB 对于开启了独立 SLAB 缓存的 MTK 闭源网卡驱动来说极易在高并发下耗尽内存池。

---

### 缺陷 7：LuCI network.js 编译期未预植入 MTK 网卡正则 (Medium)

#### 1. 现象与危害
在固件刷机升级（保留配置）或初次进入系统、浏览器缓存生效时，LuCI 的 `网络 -> 接口` 页面中，`ra0` 和 `rax0` 被显示为“以太网适配器”，甚至允许用户将其错误绑定或在网桥中发生逻辑错位。

#### 2. 技术根因深度追查
- LuCI 核心库 [`feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js`](file:///home/G/github/openwrt/feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js#L40-L45) 定义无线设备正则：
  ```javascript
  var iface_patterns_wireless = [
      /^wlan\d+/,
      /^wl\d+/,
      /^ath\d+/,
      /^\w+\.network\d+/
  ];
  ```
- 虽然后续 `luci-app-mtwifi-cfg.default` 会在开机后尝试 sed 替换，但这是基于目标机的后置动作。如果在编译阶段 `diy-part2.sh` 就将该正则固化到 `network.js` 中，即可杜绝任何由于启动时序、升级不保留配置脚本未跑导致的识别缺陷。

---

### 缺陷 8：25.12-mtk7981_dae.config 设备爆炸隐患 (Medium)

#### 1. 现象与危害
在 GitHub Actions 中使用 `configs/25.12-mtk7981_dae.config` 并保持默认 `device_preset: ALL` 运行，构建任务会在运行数小时后因**磁盘爆满（No space left on device）**或**超时（12小时）**而中途失败。

#### 2. 技术根因深度追查
检查 [`Actions-OpenWrt/configs/25.12-mtk7981_dae.config`](file:///home/G/github/Actions-OpenWrt/configs/25.12-mtk7981_dae.config)：
该配置文件中激活了 **100 多款** 设备（包括大量 Cudy、Zyxel、Comfast、TP-Link、Elecom、OpenWrt One 等冷门型号）。而 `24.10-mtk7981_dae.config` 中精准收敛为 15 款主流验证设备。必须将 25.12 的设备列表对齐收敛。

---

### 缺陷 9：Actions 工作流配置文件路径双重前缀容错 (Low)

#### 1. 现象与危害
若手动输入配置名或扩展下拉项时带不带 `configs/` 前缀不一致，可能触发 `❌ 在工作流配置库与源码仓库中均未找到` 误报错。

#### 2. 技术根因深度追查
在 `Build OpenWrt Firmware.yml` 第 232 行：
```bash
if [ -f "$GITHUB_WORKSPACE/runner-configs/configs/$CONFIG_NAME" ]; then
```
当 `inputs.config_file` 输入为 `configs/25.12-mtk7981_dae.config` 时，该判断拼接为 `runner-configs/configs/configs/...`（双重目录），虽然下方 `elif [ -f "$GITHUB_WORKSPACE/runner-configs/$CONFIG_NAME" ]` 能够捕获，但缺乏规范的去除前缀归一化逻辑。

---

## 四、全链路代码级落地方案与补丁集

### 1. 源码仓库：openwrt (24.10 与 25.12 分支)

#### 【修改 A】`package/mtk/applications/mtwifi-cfg/Makefile`
> 彻底解决 Lua 运行时与 Nixio 库缺失（缺陷 1）

```diff
--- a/package/mtk/applications/mtwifi-cfg/Makefile
+++ b/package/mtk/applications/mtwifi-cfg/Makefile
@@ -17,7 +17,7 @@ define Package/mtwifi-cfg
   CATEGORY:=MTK Properties
   SUBMENU:=Applications
   TITLE:=mtwifi configure scripts for mt798x
-  DEPENDS:=+iwinfo +wifi-dats +lua-cjson +datconf-lua  
+  DEPENDS:=+iwinfo +wifi-dats +lua +lua-cjson +datconf-lua +luci-lib-nixio
 endef
 
 define Package/mtwifi-wapp
```

#### 【修改 B】`package/mtk/applications/luci-app-turboacc-mtk/Makefile`
> 补齐 TurboACC 界面 RPC 探针运行依赖（缺陷 2）

```diff
--- a/package/mtk/applications/luci-app-turboacc-mtk/Makefile
+++ b/package/mtk/applications/luci-app-turboacc-mtk/Makefile
@@ -8,7 +8,7 @@ include $(TOPDIR)/rules.mk
 PKG_LICENSE:=GPL-3.0-only
 
 LUCI_TITLE:=LuCI support for MTK HNAT
-LUCI_DEPENDS:=+kmod-tcp-bbr @!PACKAGE_luci-app-turboacc
+LUCI_DEPENDS:=+kmod-tcp-bbr +luci-lua-runtime +luci-lib-nixio @!PACKAGE_luci-app-turboacc
 LUCI_PKGARCH:=all
 
 include $(TOPDIR)/feeds/luci/luci.mk
```

#### 【修改 C】`package/mtk/applications/luci-app-turboacc-mtk/root/etc/init.d/turboacc`
> 移除冲刷内核内存保护参数与清空缓存逻辑（缺陷 6）

```diff
--- a/package/mtk/applications/luci-app-turboacc-mtk/root/etc/init.d/turboacc
+++ b/package/mtk/applications/luci-app-turboacc-mtk/root/etc/init.d/turboacc
@@ -110,8 +110,6 @@ for port in $available_interfaces; do
 else
     echo "Invalid IPv4 address: $fastpath_mh_eth_hnat_ap"
 fi
-    echo 4096 > /proc/sys/vm/min_free_kbytes
-    echo 3 > /proc/sys/vm/drop_caches
     sed -i '/prefer-family/d' /etc/wgetrc
     echo "prefer-family = IPv4" >> /etc/wgetrc
 }
```

#### 【修改 D】`package/mtk/applications/mtwifi-cfg/files/wapp/startwapp.sh`
> 修正 2.4G 漫游阈值读取节点，并对 MAC 获取增加降级防御（缺陷 5）

```diff
--- a/package/mtk/applications/mtwifi-cfg/files/wapp/startwapp.sh
+++ b/package/mtk/applications/mtwifi-cfg/files/wapp/startwapp.sh
@@ -32,7 +32,7 @@ log_i "startwapp.sh start"
 
 run_cmd sh -c "killall bs20 2>/dev/null || true"
 run_cmd sh -c "killall wapp 2>/dev/null || true"
-br0_mac=$(cat /sys/class/net/br-lan/address)
+br0_mac=$(cat /sys/class/net/br-lan/address 2>/dev/null || cat /sys/class/net/eth0/address 2>/dev/null || echo "00:11:22:33:44:55")
 ctrlr_al_mac=$br0_mac
 agent_al_mac=$br0_mac
 ra0=0
@@ -87,8 +87,8 @@ run_cmd sed -i "s/map_agent_alid=.*/map_agent_alid=${agent_al_mac}/g" /etc/map/
     ra0=1
     fi
     
-    ra0_7981="$(uci_get_default wireless.default_MT7981_1_2.steeringthresold 0)"
-    ra0_7986="$(uci_get_default wireless.default_MT7986_1_2.steeringthresold 0)"
+    ra0_7981="$(uci_get_default wireless.default_MT7981_1_1.steeringthresold 0)"
+    ra0_7986="$(uci_get_default wireless.default_MT7986_1_1.steeringthresold 0)"
     if [ "$ra0_7981" -lt "0" ] || [ "$ra0_7986" -lt "0" ]; then
     ra0=1
     fi
```

#### 【修改 E】`wireless-mtk.js` 与 `mtwifi_cfg` 频段下发双向加固
> 根治 LuCI 提交与驱动解析因频段字段缺失而降级的隐患（缺陷 4）

1. 在 [`wireless-mtk.js`](file:///home/G/github/openwrt/package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js#L568) 中确保无论如何同时写入 `band` 与 `hwmode`：
```diff
--- a/package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js
+++ b/package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js
@@ -566,10 +566,8 @@ var CBIWifiFrequencyValue = form.Value.extend({
 	write: function(section_id, value) {
 		uci.set('wireless', section_id, 'htmode', value[0] || null);
 
-		if (this.useBandOption)
-			uci.set('wireless', section_id, 'band', value[1]);
-		else
-			uci.set('wireless', section_id, 'hwmode', (value[1] == '2g') ? '11g' : '11a');
+		uci.set('wireless', section_id, 'band', value[1]);
+		uci.set('wireless', section_id, 'hwmode', (value[1] == '2g') ? '11g' : '11a');
 
 		uci.set('wireless', section_id, 'channel', value[2]);
 	}
```

2. 在 [`mtwifi_cfg`](file:///home/G/github/openwrt/package/mtk/applications/mtwifi-cfg/files/mtwifi-cfg/mtwifi_cfg#L430) 中增加基于 `hwmode` 的容错回退机制：
```diff
--- a/package/mtk/applications/mtwifi-cfg/files/mtwifi-cfg/mtwifi_cfg
+++ b/package/mtk/applications/mtwifi-cfg/files/mtwifi-cfg/mtwifi_cfg
@@ -428,9 +428,14 @@ function parse_config(devname, cfg, dats)
     if type(cfg.config.country) == type("") and #cfg.config.country == 2 then
         dats.CountryCode = cfg.config.country
-        if cfg.config.band == "2g" then
+        local band = cfg.config.band
+        if not band and cfg.config.hwmode then
+            band = (cfg.config.hwmode == "11g" or cfg.config.hwmode == "11b") and "2g" or "5g"
+        end
+        if band == "2g" then
             dats.CountryRegion = defs.countryRegions[cfg.config.country][1]
-        elseif cfg.config.band == "5g" then
+        elseif band == "5g" then
             dats.CountryRegionABand = defs.countryRegions[cfg.config.country][2]
         end
     end
@@ -484,7 +489,11 @@ function parse_config(devname, cfg, dats)
     end
 
     local WirelessMode
-    if cfg.config.band == "2g" then
+    local band = cfg.config.band
+    if not band and cfg.config.hwmode then
+        band = (cfg.config.hwmode == "11g" or cfg.config.hwmode == "11b") and "2g" or "5g"
+    end
+    if band == "2g" then
         if string.sub(cfg.config.htmode,1,2) == "HE" then
             WirelessMode = 16 -- PHY_11AX_24G
         else
```

#### 【修改 F】`openwrt-25.12` 分支专属：解开 `iwinfo` 互斥死锁（缺陷 3）
在 `openwrt-25.12` 分支的 [`package/network/utils/iwinfo-ucode/Makefile`](file:///home/G/github/openwrt/package/network/utils/iwinfo-ucode/Makefile) 中，移除阻碍被安装的 `@!PACKAGE_iwinfo` 限制：
```diff
--- a/package/network/utils/iwinfo-ucode/Makefile
+++ b/package/network/utils/iwinfo-ucode/Makefile
@@ -23,7 +23,7 @@ define Package/ucode-mod-iwinfo/description
 define Package/iwinfo-ucode
   SECTION:=utils
   CATEGORY:=Utilities
   TITLE:=Wireless Information utility rewritten in ucode
-  DEPENDS:=+ucode-mod-iwinfo @!PACKAGE_iwinfo
+  DEPENDS:=+ucode-mod-iwinfo
 endef
```

---

### 2. 配置仓库：Actions-OpenWrt (main 分支)

#### 【修改 A】`diy-part2.sh` 加固
> 在编译期同时预植入 `wireless-mtk.js` 与 `network.js` 正则（缺陷 7）

在 [`Actions-OpenWrt/diy-part2.sh`](file:///home/G/github/Actions-OpenWrt/diy-part2.sh) 末尾添加：
```bash
# 6. Pre-patch LuCI network.js to recognize MTK raX/apcliX wireless interfaces at build time
if [ -f "feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js" ]; then
    sed -i 's#/\^wlan\\d+/,#/\^wlan\\d+/,/\^ra[xiyez]?\\d+/,/\^apcli[xiyez]?\\d+/,#' feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js 2>/dev/null || true
fi
```

#### 【修改 B】`configs/` 基础配置文件补齐关键包声明
在以下 3 个核心配置文件中：
- `Actions-OpenWrt/configs/24.10-mtk7981_dae.config`
- `Actions-OpenWrt/configs/24.10-rax3000m_dae.config`
- `Actions-OpenWrt/configs/25.12-mtk7981_dae.config`

显式追加声明，确保依赖绝无死角：
```make
CONFIG_PACKAGE_lua=y
CONFIG_PACKAGE_luci-lib-nixio=y
CONFIG_PACKAGE_luci-lua-runtime=y
CONFIG_PACKAGE_ucode-mod-iwinfo=y
CONFIG_PACKAGE_iwinfo-ucode=y
```

#### 【修改 C】`configs/25.12-mtk7981_dae.config` 收敛设备清单（缺陷 8）
将 `25.12-mtk7981_dae.config` 中多余的 80+ 个无用 profile 剥离，对齐 `24.10-mtk7981_dae.config` 的 15 款核心机型列表：
- `abt_asr3000`
- `cetron_ct3003`
- `cmcc_a10`
- `cmcc_rax3000m`
- `cmcc_rax3000m-emmc-mtk`
- `cmcc_xr30-stock`
- `h3c_magic-nx30-pro`
- `imou_lc-hx3001`
- `jcg_q30-pro`
- `konka_komi-a31`
- `livinet_zr-3020`
- `qihoo_360t7`
- `xiaomi_mi-router-ax3000t`
- `xiaomi_mi-router-wr30u-stock`
- `creatlentem_clt-r30b1-112m`

---

## 五、系统全流程验证方法

在完成上述代码修改后，可通过以下三步进行全链路闭环验证：

### 1. 本地依赖解析与收敛验证
在 `openwrt` 仓库根目录分别针对两大分支载入配置执行求解：
```bash
# 验证 24.10 分支依赖
git checkout openwrt-24.10
cp /home/G/github/Actions-OpenWrt/configs/24.10-mtk7981_dae.config .config
make defconfig
grep -E "CONFIG_PACKAGE_(lua|luci-lib-nixio|luci-lua-runtime|mtwifi-cfg)" .config
# 确认输出全为 =y 且无 conflict 报错

# 验证 25.12 分支依赖
git checkout openwrt-25.12
cp /home/G/github/Actions-OpenWrt/configs/25.12-mtk7981_dae.config .config
make defconfig
grep -E "CONFIG_PACKAGE_(lua|luci-lib-nixio|luci-lua-runtime|iwinfo-ucode|mtwifi-cfg)" .config
# 确认输出全为 =y 且无 conflict 报错
```

### 2. 真实目标机运行时检查清单
固件刷机开机后，在 SSH 终端执行以下指令核实闭源栈状态：
1. **解释器可用性**：
   `lua -v`（应正确输出 Lua 5.1.5，退出码 0）；
2. **Nixio 模块健全性**：
   `lua -e 'local n = require "nixio"; print("Nixio OK")'`（应打印 `Nixio OK`）；
3. **驱动配置解析测试**：
   `/sbin/l1util list`（应输出 `MT7981_1_1 MT7981_1_2`）；
4. **无线状态与漫游守护**：
   `iwinfo ra0 info` 与 `iwinfo rax0 info`（信道、ESSID、速率正常回显）；
   `ps | grep -E "wapp|bs20"`（确认两大多频协同后台守护进程已常驻运行）；
5. **硬件加速状态验证**：
   `cat /sys/kernel/debug/hnat/hook_toggle`（回显应为 `enabled`）；
   `cat /sys/kernel/debug/hnat/hnat_stats`（有网络吞吐时确认 `ppe1/ppe2` 报文计数递增）。

---
*建议文档编制完成。*
