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
commit luci
set system.@system[0].timezone='CST-8'
set system.@system[0].zonename='Asia/Shanghai'
commit system
EOC
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

# Set root default password hash
sed -i 's|^root:[^:]*:|root:\$5\$gW00AqXbA96VHnY0\$Ph.iV76QIlLkpsNJ6EYEDzHp6N1QY43eGX3Cm2.6j1D:|' package/base-files/files/etc/shadow
