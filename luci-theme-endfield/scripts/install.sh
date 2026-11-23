#!/bin/sh
set -eu

# Universal standalone installer for OpenWrt / ImmortalWrt 25.12 routers.
# Does NOT change your active default theme unless --set-default is passed.

SET_DEFAULT=0
for arg in "$@"; do
	case "$arg" in
		--set-default) SET_DEFAULT=1 ;;
		-h|--help)
			printf 'Usage: %s [--set-default]\n' "$0"
			exit 0
			;;
		*)
			printf 'Unknown argument: %s\n' "$arg" >&2
			exit 2
			;;
	esac
done

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
"$SCRIPT_DIR/stage-files.sh" /

sh /etc/uci-defaults/35_luci-theme-endfield
rm -f /etc/uci-defaults/35_luci-theme-endfield

if [ "$SET_DEFAULT" = 1 ]; then
	uci set luci.main.mediaurlbase='/luci-static/endfield'
	uci commit luci
fi

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null || true

printf 'luci-theme-endfield installed.\n'
printf 'Registered themes: Endfield (auto), EndfieldDark, EndfieldLight\n'
printf 'Active mediaurlbase: %s\n' "$(uci -q get luci.main.mediaurlbase || echo unknown)"
