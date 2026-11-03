#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Modify default LAN IP to 172.16.19.254/24
sed -i 's/192.168.1.1/172.16.19.254/g' package/base-files/files/bin/config_generate

# 1. Set default timezone to Asia/Shanghai (CST-8)
sed -i "s/timezone='GMT0'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
sed -i "s/zonename='UTC'/zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# 2. Add Alibaba & Apple NTP servers (only if not already present in config_generate)
if ! grep -q "ntp.aliyun.com" package/base-files/files/bin/config_generate 2>/dev/null; then
    sed -i "/delete system.ntp/a \\
\\t\\tset system.ntp='timeserver'\\n\\t\\tset system.ntp.enabled='1'\\n\\t\\tset system.ntp.enable_server='0'\\n\\t\\tadd_list system.ntp.server='ntp.aliyun.com'\\n\\t\\tadd_list system.ntp.server='time.apple.com'\\n\\t\\tadd_list system.ntp.server='time1.cloud.tencent.com'\\n\\t\\tadd_list system.ntp.server='pool.ntp.org'" package/base-files/files/bin/config_generate
fi
sed -i '/add_list system.ntp.server=.time.cloudflare.com./d' package/base-files/files/bin/config_generate 2>/dev/null || true
sed -i '/add_list system.ntp.server=.time1.google.com./d' package/base-files/files/bin/config_generate 2>/dev/null || true

# 3. Set default LuCI language to Simplified Chinese (zh_cn)
if [ -d "package/emortal/default-settings/files" ]; then
    sed -i 's/set luci.main.lang="auto"/set luci.main.lang="zh_cn"/g' package/emortal/default-settings/files/99-default-settings 2>/dev/null || true
fi
mkdir -p package/base-files/files/etc/uci-defaults
cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
uci -q batch << 'EOC'
set luci.main.lang='zh_cn'
commit luci
set system.@system[0].timezone='CST-8'
set system.@system[0].zonename='Asia/Shanghai'
commit system
set dropbear.@dropbear[0].PasswordAuth='on'
set dropbear.@dropbear[0].RootPasswordAuth='on'
commit dropbear
EOC
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

# Set empty root password (no password needed for first login)
sed -i 's|^root:[^:]*:|root::|' package/base-files/files/etc/shadow

# 4. Adaptive kernel tuning for dae eBPF & high-concurrency networking
# Dynamically adjusts based on hardware RAM (256MB aggressive vs 512MB MT7981 full vs 2GB+ x86)
mkdir -p package/base-files/files/etc/uci-defaults
cat << 'EOT' > package/base-files/files/etc/uci-defaults/98-adaptive-tuning
#!/bin/sh
TOTAL_RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 262144)

if [ "$TOTAL_RAM_KB" -lt 350000 ]; then
    # 256MB device profile: aggressive yet physically safe
    MIN_FREE=10240
    BPF_LIMIT=134217728
    BACKLOG=8192
    SOMAXCONN=2048
elif [ "$TOTAL_RAM_KB" -lt 1500000 ]; then
    # 512MB ~ 1GB MT7981 / MT7986 router profile: full performance
    MIN_FREE=24576
    BPF_LIMIT=335544320
    BACKLOG=16384
    SOMAXCONN=4096
else
    # 2GB+ x86 / VM profile: extreme throughput
    MIN_FREE=65536
    BPF_LIMIT=1073741824
    BACKLOG=32768
    SOMAXCONN=16384
fi

mkdir -p /etc/sysctl.d
cat << SYSCTL_EOF > /etc/sysctl.d/98-adaptive-tuning.conf
net.core.netdev_max_backlog = $BACKLOG
net.core.somaxconn = $SOMAXCONN
net.core.bpf_jit_limit = $BPF_LIMIT
vm.min_free_kbytes = $MIN_FREE
vm.vfs_cache_pressure = 50
vm.swappiness = 10
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
SYSCTL_EOF

sysctl -p /etc/sysctl.d/98-adaptive-tuning.conf 2>/dev/null || true
exit 0
EOT
chmod +x package/base-files/files/etc/uci-defaults/98-adaptive-tuning

# 5. Pre-install MTK wireless view into LuCI network module to guarantee LuCI Wi-Fi management works out-of-the-box (MTK Filogic targets only)
if [ -f "package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js" ] && \
   grep -q "CONFIG_TARGET_mediatek=y" .config 2>/dev/null; then
    mkdir -p feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network 2>/dev/null || true
    cp -f package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js 2>/dev/null || true
fi

# 6. Pre-patch LuCI network.js to recognize MTK raX/apcliX wireless interfaces at build time
LUCI_NET_JS="feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js"
if [ -f "$LUCI_NET_JS" ] && ! grep -sq 'ra\[xiyez\]' "$LUCI_NET_JS"; then
    sed -i 's#/\^wlan\\d+/,#/\^wlan\\d+/,/^ra[xiyez]?\\d+/,/^apcli[xiyez]?\\d+/,#' "$LUCI_NET_JS" 2>/dev/null || true
fi

# 7. Pre-patch LuCI status menu to display MTK closed-source wireless in realtime graphs (MTK Filogic targets only)
if [ -f "package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/luci-mod-status.json" ] && \
   grep -q "CONFIG_TARGET_mediatek=y" .config 2>/dev/null; then
    mkdir -p feeds/luci/modules/luci-mod-status/root/usr/share/luci/menu.d 2>/dev/null || true
    cp -f package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/luci-mod-status.json feeds/luci/modules/luci-mod-status/root/usr/share/luci/menu.d/luci-mod-status.json 2>/dev/null || true
fi

# 8. Adaptive PPE count in TurboACC (MT7981 = 1, MT7986 = 2)
TURBOACC_JS="package/mtk/applications/luci-app-turboacc-mtk/htdocs/luci-static/resources/view/turboacc.js"
if [ -f "$TURBOACC_JS" ]; then
    sed -i 's/o.default = 2;/o.default = 1;/g' "$TURBOACC_JS" 2>/dev/null || true
fi

# 9. Ensure dae eBPF stream parser kernel options for MTK Filogic
for cfg_file in target/linux/mediatek/filogic/config-6.6 target/linux/mediatek/filogic/config-6.12; do
    if [ -f "$cfg_file" ]; then
        grep -q "CONFIG_BPF_STREAM_PARSER=y" "$cfg_file" || echo "CONFIG_BPF_STREAM_PARSER=y" >> "$cfg_file"
        grep -q "CONFIG_STREAM_PARSER=y" "$cfg_file" || echo "CONFIG_STREAM_PARSER=y" >> "$cfg_file"
        grep -q "CONFIG_NET_SOCK_MSG=y" "$cfg_file" || echo "CONFIG_NET_SOCK_MSG=y" >> "$cfg_file"
        grep -q "CONFIG_CGROUP_BPF=y" "$cfg_file" || echo "CONFIG_CGROUP_BPF=y" >> "$cfg_file"
    fi
done

# 10. Fix rpcd-mod-luci cmake_minimum_required 3.31 on older host cmake
for f in feeds/luci/libs/rpcd-mod-luci/src/CMakeLists.txt feeds/luci/libs/rpcd-mod-rrdns/src/CMakeLists.txt; do
    if [ -f "$f" ]; then
        sed -i 's/VERSION 3.31/VERSION 3.20/g' "$f" 2>/dev/null || true
    fi
done
