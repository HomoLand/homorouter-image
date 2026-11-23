#!/bin/sh
set -eu

# Package standalone luci-theme-endfield release archive (.tar.gz)
# and optional native OpenWrt 25.12 .apk when an apk binary supporting mkpkg is supplied.
#
# Usage: pack-release.sh --out-dir DIR [--version VER] [--apk-bin PATH]

OUT_DIR=''
VERSION='0.1.0'
APK_BIN=''

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out-dir) OUT_DIR="$2"; shift 2 ;;
		--version) VERSION="$2"; shift 2 ;;
		--apk-bin) APK_BIN="$2"; shift 2 ;;
		-h|--help)
			printf 'Usage: %s --out-dir DIR [--version VER] [--apk-bin PATH]\n' "$0"
			exit 0
			;;
		*)
			printf 'Unknown argument: %s\n' "$1" >&2
			exit 2
			;;
	esac
done

[ -n "$OUT_DIR" ] || { printf 'Missing --out-dir\n' >&2; exit 2; }

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PKG_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
OUT_DIR="$(CDPATH= cd -- "$OUT_DIR" && pwd)"

TMP_WORK="$(mktemp -d)"
trap 'rm -rf "$TMP_WORK"' EXIT INT TERM

# 1. Universal standalone tarball (works on any OpenWrt / ImmortalWrt 25.12 router)
TAR_STAGE="$TMP_WORK/luci-theme-endfield-$VERSION"
mkdir -p "$TAR_STAGE/scripts" "$TAR_STAGE/root"
cp -a "$PKG_ROOT/root/." "$TAR_STAGE/root/"
cp -f "$PKG_ROOT/scripts/stage-files.sh" "$PKG_ROOT/scripts/install.sh" "$PKG_ROOT/scripts/uninstall.sh" "$TAR_STAGE/scripts/"
chmod 0755 "$TAR_STAGE/scripts/"*.sh "$TAR_STAGE/root/etc/uci-defaults/35_luci-theme-endfield"

TAR_OUT="$OUT_DIR/luci-theme-endfield-$VERSION.tar.gz"
tar -C "$TMP_WORK" -czf "$TAR_OUT" "luci-theme-endfield-$VERSION"
printf '[pack-release] created %s\n' "$TAR_OUT"

# 2. Optional native apk-v3 package via apk mkpkg (when ImageBuilder host apk is available)
if [ -n "$APK_BIN" ] && [ -x "$APK_BIN" ]; then
	if "$APK_BIN" mkpkg --help >/dev/null 2>&1; then
		APK_ROOT="$TMP_WORK/apk-root"
		"$SCRIPT_DIR/stage-files.sh" "$APK_ROOT"
		POSTINST="$TMP_WORK/post-install"
		PRERM="$TMP_WORK/pre-deinstall"
		cat > "$POSTINST" <<'EOF'
#!/bin/sh
if [ -f /etc/uci-defaults/35_luci-theme-endfield ]; then
	sh /etc/uci-defaults/35_luci-theme-endfield && rm -f /etc/uci-defaults/35_luci-theme-endfield
fi
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null || true
exit 0
EOF
		cat > "$PRERM" <<'EOF'
#!/bin/sh
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
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null || true
exit 0
EOF
		chmod 0755 "$POSTINST" "$PRERM"
		APK_OUT="$OUT_DIR/luci-theme-endfield-$VERSION-r1.apk"
		"$APK_BIN" mkpkg \
			--files "$APK_ROOT" \
			--output "$APK_OUT" \
			--script "post-install:$POSTINST" \
			--script "pre-deinstall:$PRERM" \
			--info "name:luci-theme-endfield" \
			--info "version:${VERSION}-r1" \
			--info "arch:noarch" \
			--info "license:Apache-2.0" \
			--info "description:Endfield Industrial Theme for LuCI 25.12" \
			--info "url:https://github.com/HomoLand/homorouter-image" \
			--info "depends:luci-base"
		printf '[pack-release] created %s\n' "$APK_OUT"
	else
		printf '[pack-release] apk binary does not support mkpkg; skipping .apk\n'
	fi
fi
