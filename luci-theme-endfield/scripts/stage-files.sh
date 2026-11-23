#!/bin/sh
set -eu

# Stage luci-theme-endfield/root/ + dark/light symlinks into a target directory.
# Usage: stage-files.sh <dest-dir>

[ "$#" -eq 1 ] || {
	printf 'Usage: %s <dest-dir>\n' "$0" >&2
	exit 2
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PKG_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="$PKG_ROOT/root"
DEST="$1"

mkdir -p \
	"$DEST/etc/uci-defaults" \
	"$DEST/usr/share/ucode/luci/template/themes/endfield" \
	"$DEST/www/luci-static/endfield" \
	"$DEST/www/luci-static/resources/view/endfield"

cp -f "$SRC_ROOT/etc/uci-defaults/35_luci-theme-endfield" "$DEST/etc/uci-defaults/35_luci-theme-endfield"
chmod 0755 "$DEST/etc/uci-defaults/35_luci-theme-endfield"

cp -f "$SRC_ROOT/usr/share/ucode/luci/template/themes/endfield/"*.ut "$DEST/usr/share/ucode/luci/template/themes/endfield/"
chmod 0644 "$DEST/usr/share/ucode/luci/template/themes/endfield/"*.ut
ln -snf endfield "$DEST/usr/share/ucode/luci/template/themes/endfield-dark"
ln -snf endfield "$DEST/usr/share/ucode/luci/template/themes/endfield-light"

cp -f "$SRC_ROOT/www/luci-static/endfield/"* "$DEST/www/luci-static/endfield/"
chmod 0644 "$DEST/www/luci-static/endfield/"*
ln -snf endfield "$DEST/www/luci-static/endfield-dark"
ln -snf endfield "$DEST/www/luci-static/endfield-light"

cp -f "$SRC_ROOT/www/luci-static/resources/menu-endfield.js" "$DEST/www/luci-static/resources/menu-endfield.js"
cp -f "$SRC_ROOT/www/luci-static/resources/view/endfield/sysauth.js" "$DEST/www/luci-static/resources/view/endfield/sysauth.js"
chmod 0644 \
	"$DEST/www/luci-static/resources/menu-endfield.js" \
	"$DEST/www/luci-static/resources/view/endfield/sysauth.js"
