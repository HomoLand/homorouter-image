#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
IB_ROOT="$ROOT/imagebuilder"

usage() {
  cat <<'EOF'
Usage:
  imagebuilder/build.sh --profile <name|path> [options]

Options:
  --profile NAME|PATH      Profile name under imagebuilder/profiles/ (e.g. x86_64-efi, r68s)
                           or path to a .conf file.
  --work-dir DIR           Cache and extraction directory (default: /tmp/immortalwrt-ib-work).
  --out-dir DIR            Output directory for images, SHA256SUMS, and package-audit.txt
                           (default: /tmp/immortalwrt-ib-out/<profile>-<timestamp>).
  --adguard-bin FILE       Optional AdGuardHome static binary to pre-embed at
                           /opt/AdGuardHome/AdGuardHome (0755) in read-only /rom via FILES/.
  --local-packages DIR     Optional directory of local *.apk files copied into
                           ImageBuilder packages/ (e.g. newer luci-app-openclash-*.apk
                           so fresh Zashboard/MetaCubeXD UI is baked into /rom directly).
  --extra-files DIR        Optional directory merged into ImageBuilder FILES/ overlay.
  --extra-packages "PKGS"  Optional space-separated extra packages appended to profile PACKAGES.
  --retries N              Number of make image attempts reusing persistent dl cache (default: 3).
  --skip-download          Reuse cached ImageBuilder archive in --work-dir (SHA256 still verified).
  --dry-run                Validate profile and inputs, print resolved build plan, and exit 0.
  -h, --help               Show this help.
EOF
}

log() {
  printf '%s\n' "[imagebuilder] $*"
}

warn() {
  printf '%s\n' "[imagebuilder][warn] $*" >&2
}

die() {
  printf '%s\n' "[imagebuilder][error] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

sha256_of_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "missing sha256sum or shasum"
  fi
}

hash_line() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1"
  else
    die "missing sha256sum or shasum"
  fi
}

normalize_ws() {
  printf '%s\n' "$1" | tr '\r\n\t' '   ' | awk '{ $1=$1; print }'
}

set_kconfig_int() {
  cfg_file="$1"
  cfg_key="$2"
  cfg_val="$3"
  cfg_tmp="$cfg_file.tmp.$$"
  if [ -f "$cfg_file" ]; then
    awk -v k="$cfg_key" -v v="$cfg_val" '
      BEGIN { replaced = 0 }
      $0 ~ ("^" k "=") || $0 ~ ("^# " k " is not set$") {
        if (!replaced) {
          print k "=" v
          replaced = 1
        }
        next
      }
      { print }
      END {
        if (!replaced) print k "=" v
      }
    ' "$cfg_file" > "$cfg_tmp"
  else
    printf '%s=%s\n' "$cfg_key" "$cfg_val" > "$cfg_tmp"
  fi
  mv "$cfg_tmp" "$cfg_file"
}

disable_kconfig() {
  cfg_file="$1"
  cfg_key="$2"
  cfg_tmp="$cfg_file.tmp.$$"
  if [ -f "$cfg_file" ]; then
    awk -v k="$cfg_key" '
      BEGIN { replaced = 0 }
      $0 ~ ("^" k "=") || $0 ~ ("^# " k " is not set$") {
        if (!replaced) {
          print "# " k " is not set"
          replaced = 1
        }
        next
      }
      { print }
      END {
        if (!replaced) print "# " k " is not set"
      }
    ' "$cfg_file" > "$cfg_tmp"
  else
    printf '# %s is not set\n' "$cfg_key" > "$cfg_tmp"
  fi
  mv "$cfg_tmp" "$cfg_file"
}

validate_positive_int() {
  val="$1"
  name="$2"
  case "$val" in
    ''|*[!0-9]*|0) die "$name must be a positive integer: $val" ;;
  esac
}

validate_nonneg_int() {
  val="$1"
  name="$2"
  case "$val" in
    ''|*[!0-9]*) die "$name must be a non-negative integer: $val" ;;
  esac
}

validate_sha256_hex() {
  hex="$1"
  case "$hex" in
    *[!0-9a-fA-F]*|'') die "invalid IMAGEBUILDER_SHA256: $hex" ;;
  esac
  [ "${#hex}" -eq 64 ] || die "IMAGEBUILDER_SHA256 must be 64 hex chars: $hex"
}

PROFILE_ARG=''
WORK_DIR='/tmp/immortalwrt-ib-work'
OUT_DIR=''
ADGUARD_BIN=''
LOCAL_PACKAGES=''
EXTRA_FILES=''
EXTRA_PACKAGES=''
MAKE_RETRIES="${IMAGEBUILDER_RETRIES:-3}"
RETRY_DELAY="${IMAGEBUILDER_RETRY_DELAY:-3}"
SKIP_DOWNLOAD=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || die "missing value for $1"
      PROFILE_ARG="$2"
      shift 2
      ;;
    --work-dir)
      [ "$#" -ge 2 ] || die "missing value for $1"
      WORK_DIR="$2"
      shift 2
      ;;
    --out-dir)
      [ "$#" -ge 2 ] || die "missing value for $1"
      OUT_DIR="$2"
      shift 2
      ;;
    --adguard-bin)
      [ "$#" -ge 2 ] || die "missing value for $1"
      ADGUARD_BIN="$2"
      shift 2
      ;;
    --local-packages)
      [ "$#" -ge 2 ] || die "missing value for $1"
      LOCAL_PACKAGES="$2"
      shift 2
      ;;
    --extra-files)
      [ "$#" -ge 2 ] || die "missing value for $1"
      EXTRA_FILES="$2"
      shift 2
      ;;
    --extra-packages)
      [ "$#" -ge 2 ] || die "missing value for $1"
      EXTRA_PACKAGES="$2"
      shift 2
      ;;
    --retries)
      [ "$#" -ge 2 ] || die "missing value for $1"
      MAKE_RETRIES="$2"
      shift 2
      ;;
    --skip-download)
      SKIP_DOWNLOAD=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$PROFILE_ARG" ] || { usage >&2; exit 2; }

if [ -f "$PROFILE_ARG" ]; then
  PROFILE_FILE="$PROFILE_ARG"
elif [ -f "$IB_ROOT/profiles/$PROFILE_ARG.conf" ]; then
  PROFILE_FILE="$IB_ROOT/profiles/$PROFILE_ARG.conf"
elif [ -f "$IB_ROOT/profiles/$PROFILE_ARG" ]; then
  PROFILE_FILE="$IB_ROOT/profiles/$PROFILE_ARG"
else
  die "profile not found: $PROFILE_ARG"
fi

PROFILE_LABEL="$(basename -- "$PROFILE_FILE" .conf)"

IMMORTALWRT_RELEASE=''
IMMORTALWRT_KERNEL=''
IMMORTALWRT_TARGET=''
IMMORTALWRT_SUBTARGET=''
IMMORTALWRT_PROFILE=''
IMAGEBUILDER_ARCHIVE=''
IMAGEBUILDER_URL=''
IMAGEBUILDER_SHA256=''
KERNEL_PARTSIZE=''
ROOTFS_PARTSIZE=''
DISABLE_KCONFIG=''
EXPECTED_IMAGE_GLOB=''
PACKAGES=''
REQUIRED_AUDIT_PACKAGES=''
FORBIDDEN_PACKAGES=''

# shellcheck disable=SC1090
. "$PROFILE_FILE"

for req_var in \
  IMMORTALWRT_RELEASE \
  IMMORTALWRT_TARGET \
  IMMORTALWRT_SUBTARGET \
  IMMORTALWRT_PROFILE \
  IMAGEBUILDER_ARCHIVE \
  IMAGEBUILDER_URL \
  IMAGEBUILDER_SHA256 \
  PACKAGES; do
  eval "req_val=\"\${$req_var:-}\""
  [ -n "$req_val" ] || die "profile $PROFILE_FILE is missing required setting: $req_var"
done

case "$IMAGEBUILDER_URL" in
  https://*) ;;
  *) die "IMAGEBUILDER_URL must use HTTPS: $IMAGEBUILDER_URL" ;;
esac
validate_sha256_hex "$IMAGEBUILDER_SHA256"

if [ -n "$KERNEL_PARTSIZE" ]; then
  validate_positive_int "$KERNEL_PARTSIZE" KERNEL_PARTSIZE
fi
if [ -n "$ROOTFS_PARTSIZE" ]; then
  validate_positive_int "$ROOTFS_PARTSIZE" ROOTFS_PARTSIZE
fi
validate_positive_int "$MAKE_RETRIES" --retries
validate_nonneg_int "$RETRY_DELAY" IMAGEBUILDER_RETRY_DELAY

if [ -n "$ADGUARD_BIN" ]; then
  [ -f "$ADGUARD_BIN" ] && [ -s "$ADGUARD_BIN" ] \
    || die "--adguard-bin must be a non-empty regular file: $ADGUARD_BIN"
  adg_parent="$(CDPATH= cd -- "$(dirname -- "$ADGUARD_BIN")" && pwd -P)"
  ADGUARD_BIN="${adg_parent%/}/$(basename -- "$ADGUARD_BIN")"
fi
LOCAL_APK_LIST=''
if [ -n "$LOCAL_PACKAGES" ]; then
  [ -d "$LOCAL_PACKAGES" ] || die "--local-packages directory does not exist: $LOCAL_PACKAGES"
  LOCAL_PACKAGES="$(CDPATH= cd -- "$LOCAL_PACKAGES" && pwd -P)"
  for apk_f in "$LOCAL_PACKAGES"/*.apk; do
    [ -e "$apk_f" ] || continue
    [ -f "$apk_f" ] && [ -s "$apk_f" ] || die "invalid local apk file: $apk_f"
    apk_base="$(basename -- "$apk_f")"
    LOCAL_APK_LIST="${LOCAL_APK_LIST:+$LOCAL_APK_LIST }$apk_base"
  done
  [ -n "$LOCAL_APK_LIST" ] || die "--local-packages directory contains no *.apk files: $LOCAL_PACKAGES"
fi
if [ -n "$EXTRA_FILES" ]; then
  [ -d "$EXTRA_FILES" ] || die "--extra-files directory does not exist: $EXTRA_FILES"
  EXTRA_FILES="$(CDPATH= cd -- "$EXTRA_FILES" && pwd -P)"
fi

BASE_PACKAGES="$(normalize_ws "$PACKAGES")"
EXTRA_PACKAGES_NORM="$(normalize_ws "$EXTRA_PACKAGES")"
if [ -n "$EXTRA_PACKAGES_NORM" ]; then
  FINAL_PACKAGES="$(normalize_ws "$BASE_PACKAGES $EXTRA_PACKAGES_NORM")"
else
  FINAL_PACKAGES="$BASE_PACKAGES"
fi
REQUIRED_AUDIT_NORM="$(normalize_ws "$REQUIRED_AUDIT_PACKAGES")"
FORBIDDEN_NORM="$(normalize_ws "$FORBIDDEN_PACKAGES")"
DISABLE_KCONFIG_NORM="$(normalize_ws "$DISABLE_KCONFIG")"

for cfg_disable in $DISABLE_KCONFIG_NORM; do
  case "$cfg_disable" in
    CONFIG_*[!A-Za-z0-9_]*|'') die "invalid Kconfig key in DISABLE_KCONFIG: $cfg_disable" ;;
    CONFIG_*) ;;
    *) die "invalid Kconfig key in DISABLE_KCONFIG: $cfg_disable" ;;
  esac
done

# Enforce forbidden package policy before starting any download or build.
for pkg in $FINAL_PACKAGES; do
  case "$pkg" in
    -*) continue ;;
  esac
  for bad in $FORBIDDEN_NORM; do
    if [ "$pkg" = "$bad" ]; then
      die "forbidden package requested in PACKAGES: $pkg"
    fi
  done
done

if [ -z "$OUT_DIR" ]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  OUT_DIR="/tmp/immortalwrt-ib-out/${PROFILE_LABEL}-${ts}"
fi

if [ "$DRY_RUN" = 1 ]; then
  printf 'profile_file=%s\n' "$PROFILE_FILE"
  printf 'release=%s\n' "$IMMORTALWRT_RELEASE"
  printf 'kernel=%s\n' "${IMMORTALWRT_KERNEL:-unknown}"
  printf 'target=%s/%s\n' "$IMMORTALWRT_TARGET" "$IMMORTALWRT_SUBTARGET"
  printf 'profile=%s\n' "$IMMORTALWRT_PROFILE"
  printf 'archive=%s\n' "$IMAGEBUILDER_ARCHIVE"
  printf 'url=%s\n' "$IMAGEBUILDER_URL"
  printf 'sha256=%s\n' "$IMAGEBUILDER_SHA256"
  printf 'kernel_partsize=%s\n' "${KERNEL_PARTSIZE:-default}"
  printf 'rootfs_partsize=%s\n' "${ROOTFS_PARTSIZE:-default}"
  printf 'disable_kconfig=%s\n' "${DISABLE_KCONFIG_NORM:-none}"
  printf 'retries=%s\n' "$MAKE_RETRIES"
  printf 'adguard_bin=%s\n' "${ADGUARD_BIN:-none}"
  printf 'local_packages=%s\n' "${LOCAL_APK_LIST:-none}"
  printf 'extra_files=%s\n' "${EXTRA_FILES:-none}"
  printf 'out_dir=%s\n' "$OUT_DIR"
  printf 'packages=%s\n' "$FINAL_PACKAGES"
  exit 0
fi

require_cmd tar
require_cmd zstd
require_cmd make
if [ "$SKIP_DOWNLOAD" != 1 ]; then
  require_cmd curl
fi

mkdir -p "$WORK_DIR" "$OUT_DIR"
WORK_DIR="$(CDPATH= cd -- "$WORK_DIR" && pwd -P)"
OUT_DIR="$(CDPATH= cd -- "$OUT_DIR" && pwd -P)"

CACHE_DIR="$WORK_DIR/cache"
DL_CACHE_DIR="$CACHE_DIR/dl/$PROFILE_LABEL"
EXTRACT_PARENT="$WORK_DIR/extract/$PROFILE_LABEL"
STAGE_FILES="$WORK_DIR/files/$PROFILE_LABEL"
ARCHIVE_PATH="$CACHE_DIR/$IMAGEBUILDER_ARCHIVE"
OUT_BIN_DIR="$OUT_DIR/bin"

rm -rf "$OUT_BIN_DIR"
mkdir -p "$CACHE_DIR" "$DL_CACHE_DIR" "$OUT_BIN_DIR"

if [ ! -f "$ARCHIVE_PATH" ]; then
  [ "$SKIP_DOWNLOAD" != 1 ] || die "--skip-download set but cached archive is missing: $ARCHIVE_PATH"
  part_path="$ARCHIVE_PATH.part.$$"
  trap 'rm -f "$part_path"' EXIT INT TERM
  log "download $IMAGEBUILDER_URL"
  curl -fsSL --retry 3 --connect-timeout 15 -o "$part_path" "$IMAGEBUILDER_URL"
  mv "$part_path" "$ARCHIVE_PATH"
  trap - EXIT INT TERM
else
  log "reuse cached archive: $ARCHIVE_PATH"
fi

actual_sha256="$(sha256_of_file "$ARCHIVE_PATH" | tr 'A-F' 'a-f')"
expected_sha256="$(printf '%s' "$IMAGEBUILDER_SHA256" | tr 'A-F' 'a-f')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  die "SHA256 mismatch for $ARCHIVE_PATH: expected=$expected_sha256 actual=$actual_sha256"
fi
log "verified ImageBuilder SHA256: $actual_sha256"

rm -rf "$EXTRACT_PARENT"
mkdir -p "$EXTRACT_PARENT"
log "extract $IMAGEBUILDER_ARCHIVE -> $EXTRACT_PARENT"
zstd -dc "$ARCHIVE_PATH" | tar -xf - -C "$EXTRACT_PARENT"

IB_DIR=''
if [ -f "$EXTRACT_PARENT/Makefile" ]; then
  IB_DIR="$EXTRACT_PARENT"
else
  for candidate in "$EXTRACT_PARENT"/*; do
    if [ -d "$candidate" ] && [ -f "$candidate/Makefile" ]; then
      [ -z "$IB_DIR" ] || die "multiple ImageBuilder directories found in $EXTRACT_PARENT"
      IB_DIR="$candidate"
    fi
  done
fi
[ -n "$IB_DIR" ] || die "extracted archive does not contain an ImageBuilder Makefile"

if [ -d "$IB_DIR/dl" ] && [ ! -L "$IB_DIR/dl" ]; then
  for pre_dl in "$IB_DIR/dl"/*; do
    [ -e "$pre_dl" ] || continue
    pre_name="$(basename -- "$pre_dl")"
    [ -e "$DL_CACHE_DIR/$pre_name" ] || cp -a "$pre_dl" "$DL_CACHE_DIR/$pre_name"
  done
fi
rm -rf "$IB_DIR/dl"
ln -s "$DL_CACHE_DIR" "$IB_DIR/dl"
log "linked persistent dl cache: $IB_DIR/dl -> $DL_CACHE_DIR"

if [ -n "$KERNEL_PARTSIZE" ]; then
  set_kconfig_int "$IB_DIR/.config" CONFIG_TARGET_KERNEL_PARTSIZE "$KERNEL_PARTSIZE"
  log "configured CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE"
fi
if [ -n "$ROOTFS_PARTSIZE" ]; then
  set_kconfig_int "$IB_DIR/.config" CONFIG_TARGET_ROOTFS_PARTSIZE "$ROOTFS_PARTSIZE"
  log "configured CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE"
fi
if [ -n "$DISABLE_KCONFIG_NORM" ]; then
  for cfg_disable in $DISABLE_KCONFIG_NORM; do
    disable_kconfig "$IB_DIR/.config" "$cfg_disable"
  done
  log "disabled Kconfig options: $DISABLE_KCONFIG_NORM"
fi

if [ -n "$LOCAL_PACKAGES" ]; then
  mkdir -p "$IB_DIR/packages"
  for apk_f in "$LOCAL_PACKAGES"/*.apk; do
    [ -f "$apk_f" ] || continue
    cp -f "$apk_f" "$IB_DIR/packages/"
  done
  log "staged local apk packages into $IB_DIR/packages/: $LOCAL_APK_LIST"
fi

USE_FILES=0
ADGUARD_SHA256=''
rm -rf "$STAGE_FILES"
if [ -n "$EXTRA_FILES" ] || [ -n "$ADGUARD_BIN" ]; then
  mkdir -p "$STAGE_FILES"
  USE_FILES=1
  if [ -n "$EXTRA_FILES" ]; then
    cp -a "$EXTRA_FILES"/. "$STAGE_FILES"/
    log "staged extra files from $EXTRA_FILES"
  fi
  if [ -n "$ADGUARD_BIN" ]; then
    mkdir -p "$STAGE_FILES/opt/AdGuardHome"
    rm -f "$STAGE_FILES/opt/AdGuardHome/AdGuardHome"
    cp "$ADGUARD_BIN" "$STAGE_FILES/opt/AdGuardHome/AdGuardHome"
    chmod 0755 "$STAGE_FILES/opt/AdGuardHome/AdGuardHome"
    ADGUARD_SHA256="$(sha256_of_file "$STAGE_FILES/opt/AdGuardHome/AdGuardHome")"
    log "staged /opt/AdGuardHome/AdGuardHome in /rom FILES/ (sha256=$ADGUARD_SHA256)"
  fi
fi

set -- \
  -C "$IB_DIR" \
  image \
  "PROFILE=$IMMORTALWRT_PROFILE" \
  "PACKAGES=$FINAL_PACKAGES" \
  "BIN_DIR=$OUT_BIN_DIR"

if [ "$USE_FILES" = 1 ]; then
  set -- "$@" "FILES=$STAGE_FILES"
fi
if [ -n "$ROOTFS_PARTSIZE" ]; then
  set -- "$@" "ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE"
fi

log "building ImmortalWrt $IMMORTALWRT_RELEASE ($IMMORTALWRT_TARGET/$IMMORTALWRT_SUBTARGET profile=$IMMORTALWRT_PROFILE)"
attempt=1
while :; do
  rm -rf "$OUT_BIN_DIR"
  mkdir -p "$OUT_BIN_DIR"
  if make "$@"; then
    break
  fi
  if [ "$attempt" -ge "$MAKE_RETRIES" ]; then
    die "make image failed after $attempt attempt(s) (dl cache preserved at $DL_CACHE_DIR)"
  fi
  warn "make image attempt $attempt/$MAKE_RETRIES failed; retrying in ${RETRY_DELAY}s with preserved dl cache ($DL_CACHE_DIR)"
  attempt=$((attempt + 1))
  if [ "$RETRY_DELAY" -gt 0 ]; then
    sleep "$RETRY_DELAY"
  fi
done

MANIFEST_FILE="$(find "$OUT_BIN_DIR" -maxdepth 2 -type f -name '*.manifest' | sort | head -n 1 || true)"
[ -n "$MANIFEST_FILE" ] || die "ImageBuilder did not generate a .manifest file under $OUT_BIN_DIR"

INSTALLED_LIST="$OUT_DIR/.installed-pkgs.$$"
trap 'rm -f "$INSTALLED_LIST"' EXIT INT TERM
awk 'NF { print $1 }' "$MANIFEST_FILE" | sort -u > "$INSTALLED_LIST"
PKG_COUNT="$(wc -l < "$INSTALLED_LIST" | tr -d ' ')"

FORBIDDEN_HITS=''
for bad in $FORBIDDEN_NORM; do
  if grep -Fxq "$bad" "$INSTALLED_LIST"; then
    FORBIDDEN_HITS="${FORBIDDEN_HITS:+$FORBIDDEN_HITS }$bad"
  fi
done

MISSING_REQUIRED=''
for req in $REQUIRED_AUDIT_NORM; do
  if ! grep -Fxq "$req" "$INSTALLED_LIST"; then
    MISSING_REQUIRED="${MISSING_REQUIRED:+$MISSING_REQUIRED }$req"
  fi
done

OPENCLASH_VERSION="$(awk '$1 == "luci-app-openclash" { print $3; exit }' "$MANIFEST_FILE" || true)"
if [ "$OPENCLASH_VERSION" = "0.48.002" ]; then
  warn "built manifest includes feed luci-app-openclash 0.48.002 (bundles ancient Zashboard UI incompatible with Mihomo provider-only /proxies); pass --local-packages DIR with a newer luci-app-openclash-*.apk"
fi

AUDIT_FILE="$OUT_DIR/package-audit.txt"
{
  printf 'profile=%s\n' "$PROFILE_LABEL"
  printf 'release=%s\n' "$IMMORTALWRT_RELEASE"
  printf 'kernel=%s\n' "${IMMORTALWRT_KERNEL:-unknown}"
  printf 'target=%s/%s\n' "$IMMORTALWRT_TARGET" "$IMMORTALWRT_SUBTARGET"
  printf 'device_profile=%s\n' "$IMMORTALWRT_PROFILE"
  printf 'imagebuilder_sha256=%s\n' "$actual_sha256"
  printf 'kernel_partsize=%s\n' "${KERNEL_PARTSIZE:-default}"
  printf 'rootfs_partsize=%s\n' "${ROOTFS_PARTSIZE:-default}"
  if [ -n "$ADGUARD_SHA256" ]; then
    printf 'adguard_bin_embedded=yes\n'
    printf 'adguard_bin_sha256=%s\n' "$ADGUARD_SHA256"
  else
    printf 'adguard_bin_embedded=no\n'
  fi
  printf 'local_packages=%s\n' "${LOCAL_APK_LIST:-none}"
  printf 'openclash_version=%s\n' "${OPENCLASH_VERSION:-none}"
  printf 'manifest=%s\n' "$(basename -- "$MANIFEST_FILE")"
  printf 'installed_package_count=%s\n' "$PKG_COUNT"
  printf 'forbidden_hits=%s\n' "${FORBIDDEN_HITS:-none}"
  printf 'missing_required=%s\n' "${MISSING_REQUIRED:-none}"
  printf '===INSTALLED_MANIFEST===\n'
  sort "$MANIFEST_FILE"
} > "$AUDIT_FILE"

rm -f "$INSTALLED_LIST"
trap - EXIT INT TERM

[ -z "$FORBIDDEN_HITS" ] || die "forbidden packages found in built manifest: $FORBIDDEN_HITS (see $AUDIT_FILE)"
[ -z "$MISSING_REQUIRED" ] || die "required packages missing from built manifest: $MISSING_REQUIRED (see $AUDIT_FILE)"

if [ -n "$EXPECTED_IMAGE_GLOB" ]; then
  # shellcheck disable=SC2086
  expected_hit="$(find "$OUT_BIN_DIR" -maxdepth 2 -type f -name "$EXPECTED_IMAGE_GLOB" | head -n 1 || true)"
  [ -n "$expected_hit" ] || warn "expected image pattern not found under $OUT_BIN_DIR: $EXPECTED_IMAGE_GLOB"
fi

SUMS_FILE="$OUT_DIR/SHA256SUMS"
(
  cd "$OUT_DIR"
  find bin -maxdepth 2 -type f \( -name '*.img.gz' -o -name '*.img' -o -name '*.bin' -o -name '*.manifest' \) | sort \
    | while IFS= read -r rel_art; do
      hash_line "$rel_art"
    done
  hash_line package-audit.txt
) > "$SUMS_FILE"

log "build succeeded: $OUT_DIR"
log "installed packages audited: $PKG_COUNT (forbidden=0 missing_required=0)"
log "audit report: $AUDIT_FILE"
log "checksums: $SUMS_FILE"
