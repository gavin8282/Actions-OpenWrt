# Actions-OpenWrt (MTK MT798x / x86_64 自动化固件构建)

基于 GitHub Actions 自动化编译 OpenWrt / ImmortalWrt 固件，特别优化适配 MediaTek MT7981 / MT7986 系列路由器与 x86_64 软路由平台。

---

## 🌟 特性功能

- 🚀 **多分支/多上游自由切换**：支持一键在 UI 下拉框中直接点选目标仓库与分支：
  - `gavin8282/g-openwrt:25.12-mtk7981` (默认)
  - `gavin8282/g-openwrt:openwrt-25.12` (官方 25.12.6 稳定版 + MTK 闭源驱动/HNAT 移植)
  - `gavin8282/g-openwrt:24.10-mtk7981`
  - `gavin8282/g-openwrt:21.02-mtk7981`
  - `padavanonly/immortalwrt-mt798x-6.6:openwrt-24.10-6.6`
  - `chasey-dev/immortalwrt-mt798x-rebase:25.12`
- 📶 **MTK 闭源 Wi-Fi 驱动 & 硬件加速闭环**：
  - 完整支持联发科原厂驱动套件（`kmod-mt_wifi` 7.6.7.3、`kmod-warp` WED 卸载、`kmod-conninfra` 底层通信总线）。
  - 内核层集成 `kmod-mediatek_hnat` 硬件网络加速（PPE），千兆全双工跑满 CPU 负载趋近于 0%。
- 🚀 **针对 dae eBPF 与高并发网络的三阶自适应调优**：
  - 开机根据实际物理内存自动侦测并调节内核参数（`/etc/uci-defaults/98-adaptive-tuning`）：
    - **256MB 设备**：保守防 OOM（`vm.min_free_kbytes=10MB`，`bpf_jit_limit=128MB`，`backlog=8192`）。
    - **512MB~1GB MT798x 路由**：满血性能（`vm.min_free_kbytes=24MB`，`bpf_jit_limit=320MB`，`backlog=16384`）。
    - **2GB+ x86_64 软路由**：万兆高吞吐（`vm.min_free_kbytes=64MB`，`bpf_jit_limit=1GB`，`backlog=32768`）。
- 🖥 **x86_64 专用虚拟化支持**：
  - 自动编译生成 VMDK 格式；
  - 自动将 raw 镜像无缝转换为紧凑版压缩 `qcow2` 虚拟磁盘（适用于 PVE / KVM），并自动删除臃肿的未压缩生 `.img` 节省 CI 空间与配额。
- ⚡ **极致缓存加速与流水线加固**：
  - 深度集成 Actions Cache（CCache + DL 依赖缓存），编译成功后自动沉淀并继承。
  - 全流程启用 `set -o pipefail`，杜绝任何编译崩溃被管道吞掉而导致的“假成功”。
  - 注入 Node.js 24 运行时环境，消除 GitHub Actions Runner 弃用警告。
- 🛠 **开机预设与网络规范**：
  - 默认管理 IP 统一规范为 **`172.16.19.254/24`**。
  - 默认时区锁定 **`Asia/Shanghai (CST-8)`**，自动预置阿里与苹果 NTP 授时服务器。
  - 预设已验证的 root 密码 hash，保留密码登录，防止首次刷机失联。

---

## 📁 目录结构

```text
├── .github/workflows/
│   ├── Build OpenWrt Firmware.yml   # 核心固件自动化编译流水线
│   └── sync-upstream.yml           # 上游更新侦测与自动触发
├── configs/                         # 机型与架构配置文件 (.config)
│   ├── 25.12-mtk7981_dae.config    # MT7981 全机型轻量配置 (dae eBPF + MTK 闭源驱动 + PPE)
│   ├── 24.10-mtk7981_dae.config    # MT7981 24.10 分支轻量配置
│   ├── 24.10-rax3000m_dae.config   # RAX3000M 24.10 专用配置
│   ├── x86_64_dae.config           # x86_64 软路由配置 (含 BBR + dae eBPF)
│   └── 21.02.7-*.config            # 21.02.7 历史经典机型配置
├── diy-part1.sh                     # Feeds 更新前自定义脚本
└── diy-part2.sh                     # Feeds 更新后自定义脚本 (网络参数/时区/密码/自适应调优)
```

---

## 🚀 使用指南

1. 进入 GitHub 仓库页面，点击 **Actions** 选项卡。
2. 在左侧列表中选择 **Build OpenWrt Firmware**。
3. 点击 **Run workflow** 下拉菜单，直接通过下拉选择参数（全 UI 交互，无需手动敲命令）：
   - **选择源码仓库及分支**：
     - `gavin8282/g-openwrt:25.12-mtk7981` (默认)
     - `gavin8282/g-openwrt:openwrt-25.12` (官方 25.12.6 稳定版 + 闭源驱动移植)
     - `gavin8282/g-openwrt:24.10-mtk7981`
     - 其他上游分支
   - **选择基础配置文件**：
     - `configs/25.12-mtk7981_dae.config` (MT7981 首选)
     - `configs/x86_64_dae.config` (x86 软路由首选)
     - `configs/24.10-mtk7981_dae.config`
   - **常用机型快捷下拉选择**：
     - **ALL**：编译当前配置文件中包含的全部目标设备。
     - **单选指定设备**：直接从下拉列表中点选，支持：
       - `cmcc_rax3000m` (移动 RAX3000M NAND 版)
       - `cmcc_rax3000m-emmc` (移动 RAX3000M eMMC 版)
       - `h3c_magic-nx30-pro` (新华三 H3C NX30 Pro)
       - `xiaomi_mi-router-ax3000t` (小米 AX3000T)
       - `xiaomi_mi-router-wr30u-stock` (小米 WR30U 原厂布局)
       - `qihoo_360t7` (奇虎 360 T7)
       - `glinet_gl-mt3000` (格联 MT3000 Beryl AX)
       - `glinet_gl-mt2500` (格联 MT2500 Brume 2)
       - `asus_rt-ax52`、`cudy_wr3000-v1` 等
     - **CUSTOM**：一次性编译多台指定设备时选择此项，并在输入框中以空格分隔填入设备名。
   - **清理缓存**：需要彻底清除旧 CCache 全量冷编译时勾选。
4. 构建完成后，前往 **Releases** 或对应运行页面的 **Artifacts** 处下载固件。

---

## 🙏 致谢与上游来源 (Upstream Credits)

本项目代码与构建系统深度依托以下优秀的开源项目与维护者的无私贡献，特此鸣谢：

- **OpenWrt 官方项目**：[openwrt/openwrt](https://github.com/openwrt/openwrt) 提供稳定、纯净的 Linux 嵌入式发行版基准（Linux Kernel 6.12）。
- **MediaTek 原厂开源 Feeds**：[mediatek/mtk-openwrt-feeds](https://github.com/mediatek/mtk-openwrt-feeds) 提供联发科 Filogic 系列无线与底层芯片接口。
- **ImmortalWrt 25.12 Rebase**：[chasey-dev/immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) 提供 25.12 分支适配 MTK 闭源驱动（7.6.7.3）与 HNAT/WED 硬件加速的重要补丁。
- **ImmortalWrt MT798x 6.6**：[padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6) 提供 24.10 分支内核 6.6 的经典适配与机型支持。
- **Actions-OpenWrt 基础工作流**：[P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 提供优秀的 GitHub Actions 自动化编译流水线架构原型。

---

## 📄 License
MIT © [P3TERX](https://p3terx.com) & Contributors
