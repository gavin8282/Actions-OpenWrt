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

# 2. Add Alibaba & Apple NTP servers
sed -i "/delete system.ntp/a \\
\\t\\tset system.ntp='timeserver'\\n\\t\\tset system.ntp.enabled='1'\\n\\t\\tset system.ntp.enable_server='0'\\n\\t\\tadd_list system.ntp.server='ntp.aliyun.com'\\n\\t\\tadd_list system.ntp.server='time.apple.com'\\n\\t\\tadd_list system.ntp.server='time1.cloud.tencent.com'\\n\\t\\tadd_list system.ntp.server='pool.ntp.org'" package/base-files/files/bin/config_generate
sed -i '/add_list system.ntp.server=.time.cloudflare.com./d' package/base-files/files/bin/config_generate
sed -i '/add_list system.ntp.server=.time1.google.com./d' package/base-files/files/bin/config_generate

# 3. Set default LuCI language to Simplified Chinese (zh_cn)
if [ -d "package/emortal/default-settings/files" ]; then
    sed -i 's/set luci.main.lang="auto"/set luci.main.lang="zh_cn"/g' package/emortal/default-settings/files/99-default-settings 2>/dev/null || true
fi
mkdir -p package/base-files/files/etc/uci-defaults
cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
uci -q batch << 'EOC'
set luci.main.lang='zh_cn'
set luci.main.mediaurlbase='/luci-static/argon'
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

# Set root default password hash
sed -i 's|^root:[^:]*:|root:\$5\$gW00AqXbA96VHnY0\$Ph.iV76QIlLkpsNJ6EYEDzHp6N1QY43eGX3Cm2.6j1D:|' package/base-files/files/etc/shadow

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
SYSCTL_EOF

sysctl -p /etc/sysctl.d/98-adaptive-tuning.conf 2>/dev/null || true
exit 0
EOT
chmod +x package/base-files/files/etc/uci-defaults/98-adaptive-tuning

# 5. Pre-install MTK wireless view into LuCI network module to guarantee LuCI Wi-Fi management works out-of-the-box
if [ -f "package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js" ]; then
    mkdir -p feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network 2>/dev/null || true
    cp -f package/mtk/applications/luci-app-mtwifi-cfg/root/usr/share/luci-app-mtwifi-cfg/wireless-mtk.js feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js 2>/dev/null || true
fi

# 6. Pre-patch LuCI network.js to recognize MTK raX/apcliX wireless interfaces at build time
if [ -f "feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js" ]; then
    sed -i 's#/\\^wlan\\\\d+/,#/\\^wlan\\\\d+/,/\\^ra[xiyez]?\\\\d+/,/\\^apcli[xiyez]?\\\\d+/,#' feeds/luci/modules/luci-base/htdocs/luci-static/resources/network.js 2>/dev/null || true
fi
