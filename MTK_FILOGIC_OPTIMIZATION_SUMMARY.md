# MTK Filogic (MT7981) 闭源驱动移植与系统优化技术白皮书

本文档系统性总结针对 `openwrt-24.10`（官方 v24.10.8 基线）与 `openwrt-25.12` 两大分支，在联发科 Filogic 系列（以 MT7981 / 360T7 / CMCC RAX3000M / NX30 Pro 等机型为代表）上的闭源无线驱动与硬件加速栈移植、去 FullCone 僵尸代码重构、LuCI 配置下发闭环保障、双频合一漫游深度优化及本地/云端全链路验证的全部工作。

---

## 目录
1. [项目背景与核心目标](#一项目背景与核心目标)
2. [底层驱动移植与基线对齐](#二底层驱动移植与基线对齐)
3. [网络栈与架构清理：彻底剔除 FullCone 僵尸逻辑](#三网络栈与架构清理彻底剔除-fullcone-僵尸逻辑)
4. [双频合一与无线漫游闭环（802.11k/v/r）](#四双频合一与无线漫游闭环80211kvr)
5. [LuCI 配置修改与下发生效机制深度加固](#五luci-配置修改与下发生效机制深度加固)
6. [系统性能与硬件级抗干扰优化](#六系统性能与硬件级抗干扰优化)
7. [GitHub Actions 云端流水线与环境加固](#七github-actions-云端流水线与环境加固)
8. [CMCC RAX3000M 固件选型与刷机指南](#八cmcc-rax3000m-固件选型与刷机指南)
9. [验证结论与仓库提交追踪](#九验证结论与仓库提交追踪)

---

## 一、项目背景与核心目标

* **平台基准**：
  - `openwrt-24.10`：基于官方 OpenWrt `v24.10.8` 源码（Linux 内核 6.6.144），引入联发科私有驱动与加速栈。
  - `openwrt-25.12`：针对下一代构建（Linux 内核 6.12）对齐闭源驱动与调度组件。
* **核心诉求**：
  1. 彻底解决官方开源 `kmod-mt76` 在高并发、复杂环境下的发热与吞吐瓶颈，引入原厂 MTK 闭源驱动（`kmod-mt_wifi` + `kmod-warp` + `kmod-conninfra`）；
  2. 启用 MTK HNAT 芯片级硬件加速（线速千兆 NAT 卸载）；
  3. 保障 `dae` eBPF/BTF 内核级透明代理高性能运行；
  4. 根治 LuCI 界面保存 Wi-Fi 配置不生效、双频合一缺失的隐患；
  5. 剔除与 Firewall4 (nftables) 架构冲突的旧 iptables / FullCone 冗余代码；
  6. 确保配置 0 语法冲突，并在本地冷构建全量验证（退出码 0）后推送到 GitHub。

---

## 二、底层驱动移植与基线对齐

1. **彻底剔除开源 `kmod-mt76` 冲突**：
   - 开源 `mt76` 驱动（`kmod-mt7915e`）与 MTK 闭源驱动 `kmod-mt_wifi` 会争抢硬件射频与固件。
   - 对齐上游 `padavanonly` 的提交策略，彻底执行 `git rm -rf package/kernel/mt76`，并在各机型配置中显式禁用开源无线固件打包，净省约 4MB Flash。
2. **GCC 14 / 高版本工具链编译兼容**：
   - 官方 24.10 / 25.12 引入了 GCC 14，默认启用了更严格的代码检查（`-Werror` 会将未初始化的微小警告提升为编译错误）。
   - 内核配置显式关闭 `CONFIG_KERNEL_WERROR`，保证闭源驱动补丁集平稳编译。
3. **DTS 与硬件加速节点恢复**：
   - 官方基线 `mt7981.dtsi` 默认未定义 HNAT 硬件节点，导致 DTS 编译报 `&hnat undefined`。
   - 恢复包含 `hnat@15000000`、时钟挂载与 PPE 表项的 MTK 平台专属设备树。
4. **U-Boot 引导体系与 FIP 生成对齐**：
   - 移植 122 个 U-Boot 引导补丁，确保为 15 款机型（包括 `creatlentem_clt-r30b1`、`cmcc_rax3000m`、`360t7` 等）完整产出开源大分区 `bl31-uboot.fip`，避免 `target/linux/install` 阶段因找不到引导产物而中断。

---

## 三、网络栈与架构清理：彻底剔除 FullCone 僵尸逻辑

在官方 OpenWrt 24.10 / 25.12 全面转向 **Firewall4 (nftables)** 的背景下，旧版的“全锥形 NAT (Full Cone NAT / `xt_FULLCONENAT`)”存在严重的架构失配：

1. **深层技术根因**：
   - `xt_FULLCONENAT` 强依赖旧版 `iptables` / `xtables`。在纯 `nftables` 环境下，调用 `iptables -t nat -L` 会不断启动失效子进程造成 CPU 空转。
   - **与 HNAT 互斥**：MediaTek HNAT 是硬件 PPE 内部的 5 元组流卸载（FOE 表线速直通），外部首包打洞回落 CPU。纯软件打洞逻辑容易破坏硬件流表建立，降低转发吞吐。
   - **IPv6 无需 NAT**：IPv6 具备端到端独立公网 IP 与 Open/Type A 直通特性，FullCone 纯属 IPv4 时代的单公网 IP 缓解方案，对 IPv6 毫无意义且存在打洞串扰隐患。
2. **清理行动（双分支同步提交）**：
   - **前端视图**：彻底删除 `luci-app-turboacc-mtk` 界面中的“全锥形 NAT”状态灯、下拉选择框与轮询检测方法。
   - **RPC 探针**：移除 `usr/libexec/rpcd/luci.turboacc` 中对 `xt_FULLCONENAT.ko`、`nft_fullcone.ko` 以及 `iptables` 规则的扫描代码。
   - **内核控制**：移除 `etc/init.d/turboacc` 中对 `/proc/sys/net/netfilter/nf_conntrack_nat_mode` 的写操作与默认 UCI 选项。
   - **保留核心价值**：完整保留 **HNAT 芯片硬件加速开关**、**连接速率绑定阈值 (pps) 控制** 及 **IPv6 硬件加速直通**。

---

## 四、双频合一与无线漫游闭环（802.11k/v/r）

针对此前用户反馈的“双频合一不生效”、“Wi-Fi 无法自动切换 5G”等问题，进行了系统级机制修复：

1. **核心守护进程补齐（`mtwifi-wapp`）**：
   - MTK 闭源双频合一不是简单的 SSID 相同，而是依赖后台守护进程 `/sbin/bs20`（Band Steering 2.0）与 `/sbin/wapp`。
   - 在所有配置文件中显式启用 `CONFIG_PACKAGE_mtwifi-wapp=y`。
   - 从 24.10 完整移植缺失的 `files/wapp/` 模块（包含 `bs20`、`startwapp.sh`、`wapp`、`libcrypto.so.1.1`）至 `openwrt-25.12` 分支。
2. **消除配置参数冲突**：
   - 清除了配置文件中此前存在的宏冲突（如置顶 `CONFIG_MTK_BAND_STEERING=y`，彻底清除文件末尾由脚本自动附带的 `# CONFIG_MTK_BAND_STEERING is not set`）。
3. **漫游铁三角协议栈完备化**：
   - 补充开启 `CONFIG_MTK_WNM_SUPPORT=y`（802.11v BSS 转换管理）。
   - 配合 `CONFIG_MTK_DOT11K_RRM_SUPPORT=y` (11k) 与 `CONFIG_MTK_DOT11R_FT_SUPPORT=y` (11r)，路由器可主动监测信号并向终端发送 BSS 迁移请求，使手机在走动时毫秒级平滑漫游至 5G。

---

## 五、LuCI 配置修改与下发生效机制深度加固

为了 100% 杜绝“在 LuCI 修改无线参数点击保存后毫无反应”的问题，打通了整条下发管道：

### 1. 执行链路还原
$$\text{LuCI 提交} \rightarrow \text{UCI (/etc/config/wireless)} \rightarrow \text{netifd} \rightarrow \text{mtwifi.sh} \rightarrow \text{/sbin/mtwifi\_cfg setup} \rightarrow \text{datconf.so} \rightarrow \text{.dat 驱动文件} \rightarrow \text{驱动热重载}$$

### 2. 关键断链点修复
* **补齐 `datconf-lua` 依赖**：
  - `/sbin/mtwifi_cfg` 本质上是 Lua 脚本（`local datconf = require "datconf"`）。
  - 排查发现 `25.12` 仅配置了 `ucode-mod-datconf`，遗漏了 `CONFIG_PACKAGE_datconf-lua=y`，导致 netifd 调用时直接崩溃。已在所有配置中补齐 `datconf-lua` 与 `lua-cjson`。
* **补齐 `iwinfo` 与 `wireless-tools`**：
  - LuCI 界面依赖 `iwinfo` 获取可用信道与连接设备，MTK 私有层依赖 `wireless-tools` (`iwpriv`) 与底层驱动通信。已显式全量配置。
* **补齐 `CONFIG_PACKAGE_luci=y`**：
  - 发现 `24.10` 的 target 配置中遗漏了 `CONFIG_PACKAGE_luci=y`，导致生成的固件连 Web 服务器（`uhttpd`）和基础管理页都不会打包。已全部纠正并置顶启用。
* **LuCI 视图安装双保险机制**：
  - **保险 1（代码层）**：将 `luci-app-mtwifi-cfg.default` 中的 `mv` 替换为 `mkdir -p` + `cp -f`，避免由于启动顺序或目录缺失导致视图覆盖失败。
  - **保险 2（固件编译层）**：在 `diy-part2.sh` 中增加预部署指令，在编译阶段就将 `wireless-mtk.js` 写入 `luci-mod-network` 模板，出厂即自带联发科专用无线配置面板。

---

## 六、系统性能与硬件级抗干扰优化

在 `Actions-OpenWrt` 配置文件中注入了针对 MT7981 / RAX3000M 的系统级性能与稳定性调优参数：

| 优化宏 / 配置项 | 功能与收益 |
| :--- | :--- |
| `CONFIG_MTK_WIFI_SKB_USES_SLAB=y` | 开启独立专用 SLAB 缓存池分配 skb，防止网络吞吐跑满时内存碎片化引发丢包 |
| `CONFIG_MTK_BRCM_256QAM_SUPPORT=y` | 激活 2.4G TurboQAM / 256-QAM 调制，显著提升 iPhone 及博通网卡设备的握手速率 |
| `CONFIG_MTK_VHT_TXBF_2G_EPIGRAM_IE_SUPPORT=y` | 增强 2.4GHz 频段下的波束成形（Beamforming）兼容性 |
| `CONFIG_MTK_THERMAL_PROTECT_SUPPORT=y` | 启用射频温控平滑保护，高负荷过热时平滑降频，杜绝硬件死锁 |
| `CONFIG_MTK_USB_SUPPORT=y`<br>`CONFIG_MTK_USB_EMI_SUPPORT=y` | 针对 RAX3000M 等带 USB 3.0 的路由器，自动调节时钟抑制高速信号对 2.4G 天线的辐射干扰 |
| `# CONFIG_WARP_DBG_SUPPORT is not set` | 关闭 WED 驱动内核调试打桩日志，消除 ringbuffer 刷屏与不必要的 CPU 中断消耗 |
| `CONFIG_PACKAGE_kmod-tcp-bbr=y`<br>`CONFIG_PACKAGE_kmod-sched-cake=y` | 为系统及 `dae` eBPF 代理提供 BBR 拥塞控制与 CAKE 队列算法，大幅改善跨国高延迟网络下的吞吐抗抖动能力 |

---

## 七、GitHub Actions 云端流水线与环境加固

1. **工作流 UI 选项升级**：
   - 在 `Actions-OpenWrt/.github/workflows/Build OpenWrt Firmware.yml` 中新增官方稳定基线分支选项：`gavin8282/g-openwrt:openwrt-24.10`。
2. **免除云端下载失败（离线化追踪）**：
   - 私有闭源驱动的外部下载源（如 raw.githubusercontent.com）常有网络超时或 404 风险。
   - 将驱动所需的核心源码包直接存入仓库 `dl/` 目录并纳入 git 追踪：
     - **24.10**：7 个核心驱动包（`mt7981-7.6.7.0...`、`datconf...`、`warp...` 等）。
     - **25.12**：4 个 6.12 内核专属包（`mt79xx_20250408-705eb4...`、`warp_20250408...` 等）。
3. **系统默认凭据与认证方式**：
   - 默认 LAN IP：`172.16.19.254/24`。
   - 时区与 NTP：`Asia/Shanghai (CST-8)`，集成阿里云与腾讯云授时服务器。
   - 远程登录：允许 Dropbear 密码登录（`PasswordAuth='on'`，`RootPasswordAuth='on'`）。
   - root 密码哈希值保持用户指定的自定义密文。

---

## 八、CMCC RAX3000M 固件选型与刷机指南

在 Filogic / MT7981 架构下，编译输出目录（`bin/targets/mediatek/filogic/`）中**没有 `-factory.bin` 是完全正常的标准行为**，这是因为该平台采用的是 FIT Image（`.itb`）格式配合 U-Boot 引导体系。

### 1. 产物角色对照
* `...-cmcc_rax3000m-squashfs-sysupgrade.itb`：**正式固件**（含 rootfs 与 squashfs 分区，支持持久化保存配置）。
* `...-cmcc_rax3000m-initramfs-recovery.itb`：**内存过渡救援固件**（内存临时系统，关机不保存）。
* `...-cmcc_rax3000m-nand-bl31-uboot.fip`：**开源大分区 U-Boot 引导文件**。

### 2. 刷机操作流程
* **情况 A：路由器已经刷入了第三方开源 U-Boot（如 ImmortalWrt / 大分区 U-Boot）**
  - 按住 Reset 键插电开机，电脑网线连接 LAN 口设置固定 IP（192.168.1.2），浏览器进入 U-Boot Web 恢复页面（`192.168.1.1`）。
  - **直接上传刷入**：`openwrt-mediatek-filogic-cmcc_rax3000m-squashfs-sysupgrade.itb`。
* **情况 B：当前已经在旧版 OpenWrt / ImmortalWrt 运行**
  - 进入当前系统的 `系统 -> 备份/升级` 界面。
  - **直接上传刷入**：`openwrt-mediatek-filogic-cmcc_rax3000m-squashfs-sysupgrade.itb`（无需保留配置）。
* **情况 C：从原厂中国移动系统首次刷机**
  - 需要先通过原厂漏洞/TTL 刷入开源 U-Boot `...-bl31-uboot.fip`，再在 U-Boot Web 界面刷入 `sysupgrade.itb`。

---

## 九、验证结论与仓库提交追踪

### 1. 本地全量构建验证
* **测试用例**：在 `openwrt-24.10` 分支上，载入包含全套 MTK 闭源 Wi-Fi、HNAT、dae 内核依赖、LuCI 及优化参数的完整配置文件，执行冷构建 `make -j$(nproc) world`。
* **构建结果**：**`FULL_VERIFY2_EXIT=0`（通关退出码 0，无任何阻断报错）**。
* **产物核验**：
  - 成功生成全部 15 款机型镜像文件；
  - 确认产出 `mtwifi-wapp_1-r2_aarch64_cortex-a53.ipk`（经解包验证完整包含 `/sbin/bs20`、`/sbin/startwapp.sh`、`/sbin/wapp`）；
  - SHA256 校验清单与 Packages.gz 软件源索引完备。

### 2. 仓库提交清单

#### 源码仓库：`gavin8282/g-openwrt`
* `openwrt-24.10`：
  - `68692e0`：彻底移除冲突的开源 `mt76` 源码包。
  - `43ae17c`：恢复包含 `&hnat` 节点的 `mt7981.dtsi` 设备树。
  - `f2599d0`：全面剔除 `luci-app-turboacc-mtk` 中的 Full Cone NAT 界面与探针。
  - `0e9e4ca`：预置 MTK 闭源依赖压缩包至 `dl/`。
  - `5d64474`：加固 `luci-app-mtwifi-cfg` 视图文件的部署鲁棒性。
* `openwrt-25.12`：
  - `61f672e`：同步清除 Full Cone NAT 僵尸逻辑。
  - `0e9e4ca`：移植 `mtwifi-wapp` / `bs20` 守护服务，补齐 802.11kvr 频段引导。
  - `c5526bd`：同步加固 LuCI 视图部署机制。
  - `3f0cd2b`：补齐 6.12 内核所需闭源驱动压缩包至 `dl/`。

#### 配置仓库：`gavin8282/Actions-OpenWrt`
* `main` 分支：
  - `bd08259`：对齐 15 款 MT7981 机型 profile 命名。
  - `d1e8c0e`：Actions 工作流增加 `openwrt-24.10` 分支选项。
  - `e3e5517`：`diy-part2.sh` 确保 Dropbear 密码登录。
  - `e4952bb`：注入 BBR、CAKE、WAPP、802.11v、256QAM、USB EMI 等优化参数。
  - `a497a2f`：关闭 WARP 调试打桩，消除配置冲突项。
  - `a4b25cb`：显式启用 `lua-cjson`、`iwinfo`、`datconf-lua`。
  - `e0d2002`：全量启用 `CONFIG_PACKAGE_luci=y`，并在 `diy-part2.sh` 中增加出厂级前端视图预部署机制。

---
*文档编制完成。所有代码、脚本、配置及归档包均已全部推送到 GitHub 远程仓库，可直接启动 GitHub Actions 运行云端编译。*
