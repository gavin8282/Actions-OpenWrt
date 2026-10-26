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

# Ensure root user has no password (empty password for direct login)
# Using standard hash for empty password ($1$Kn3ybXc9$jqLVkRInLjmpMRWhTlsxN0) so rpcd/crypt validation succeeds
sed -i 's|^root:[^:]*:|root:\$1\$Kn3ybXc9\$jqLVkRInLjmpMRWhTlsxN0:|' package/base-files/files/etc/shadow
