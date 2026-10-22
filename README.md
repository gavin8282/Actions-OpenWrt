# Actions-OpenWrt (MTK MT798x / Filogic 自动化固件构建)

基于 GitHub Actions 自动化编译 OpenWrt / ImmortalWrt 固件，特别优化适配 MediaTek MT7981 / MT7986 系列路由器平台。

---

## 🌟 特性功能

- 🚀 **多分支/多上游自由切换**：支持一键选择官方/自定义仓库：
  - `gavin8282/g-openwrt:24.10-mtk7981` (默认)
  - `gavin8282/g-openwrt:25.12-mtk7981`
  - `gavin8282/g-openwrt:21.02-mtk7981`
  - `padavanonly/immortalwrt-mt798x-6.6:openwrt-24.10-6.6`
  - `chasey-dev/immortalwrt-mt798x-rebase:25.12`
- ⚡ **极致缓存加速**：深度集成 Actions Cache（CCache + DL 依赖缓存），显著缩短编译周期。
- 📦 **配置灵活检出**：自动支持本仓库 `configs/` 目录下的定制配置，以及源码内置的 `defconfig/` 配置。
- 🛠 **DIY 自定义钩子**：支持执行 `diy-part1.sh`（更新 feeds 前）与 `diy-part2.sh`（更新 feeds 后）。
- 🏷 **自动打包与发布**：
  - 自动归档全量固件、生成 `sha256sums.txt` 校验和。
  - 自动创建 GitHub Release 并附带完整构建元数据。
  - 自动轮转清理历史 Release（默认保留最近 10 次有效构建）。

---

## 📁 目录结构

```text
├── .github/workflows/
│   ├── Build OpenWrt Firmware.yml   # 核心现代化编译流水线
│   └── update-checker.yml           # 上游更新侦测与自动触发
├── configs/                         # 自定义机型配置文件 (.config)
│   ├── mt7981-ax3000_dae.config
│   ├── 24.10-rax3000m_dae.config
│   └── ...
├── diy-part1.sh                     # Feeds 更新前自定义脚本
├── diy-part2.sh                     # Feeds 更新后自定义脚本
└── start_op_screen.sh               # 本地/服务器 Screen 编译辅助脚本
```

---

## 🚀 使用指南

1. 进入 GitHub 仓库页面，点击 **Actions** 选项卡。
2. 在左侧列表中选择 **Build OpenWrt Firmware**。
3. 点击 **Run workflow** 下拉菜单：
   - **选择源码仓库及分支**：根据需要选择 24.10 / 25.12 等。
   - **配置文件文件名**：默认 `mt7981-ax3000_dae.config`。
   - **指定构建设备（单选/多选）**：
     - **留空**：默认编译配置文件中勾选的全部设备。
     - **单选**：填入单个设备标识，如 `cmcc_rax3000m`。
     - **多选**：以空格分隔多个机型，如 `cmcc_rax3000m h3c_nx30pro xiaomi_mi-router-ax3000t`。
     - *常见 MT7981 设备名*：`cmcc_rax3000m`、`h3c_nx30pro`、`xiaomi_mi-router-ax3000t`、`xiaomi_mi-router-wr30u-stock`、`cetron_ct3003`、`mt7981-360-t7-108M` 等。
   - **清理缓存**：需要重新全量构建时勾选。
4. 构建完成后，前往 **Releases** 或对应运行页面的 **Artifacts** 处下载固件。

---

## 📄 License
MIT © [P3TERX](https://p3terx.com) & Contributors
