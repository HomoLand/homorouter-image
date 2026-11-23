#!/bin/sh
set -eu

# Clean uninstaller for luci-theme-endfield on OpenWrt / ImmortalWrt 25.12.

cur="$(uci -q get luci.main.mediaurlbase || true)"
case "$cur" in
	/luci-static/endfield*)
		uci set luci.main.mediaurlbase='/luci-static/bootstrap'
		;;
esac

uci -q delete luci.themes.Endfield || true
uci -q delete luci.themes.EndfieldDark || true
uci -q delete luci.themes.EndfieldLight || true
uci commit luci || true

rm -rf \
	/usr/share/ucode/luci/template/themes/endfield \
	/usr/share/ucode/luci/template/themes/endfield-dark \
	/usr/share/ucode/luci/template/themes/endfield-light \
	/www/luci-static/endfield \
	/www/luci-static/endfield-dark \
	/www/luci-static/endfield-light \
	/www/luci-static/resources/menu-endfield.js \
	/www/luci-static/resources/view/endfield \
	/etc/uci-defaults/35_luci-theme-endfield \
	/tmp/luci-indexcache* \
	/tmp/luci-modulecache 2>/dev/null || true

printf 'luci-theme-endfield uninstalled cleanly.\n'
printf 'Active mediaurlbase: %s\n' "$(uci -q get luci.main.mediaurlbase || echo unknown)"
