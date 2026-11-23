# HomoRouter Image Builder

Declarative **ImmortalWrt 25.12.x** (`Linux 6.12 LTS`, `fw4`, `apk`) automated firmware builder for GitHub Actions.

> **Strict Public Boundary**: This repository contains only generic firmware profiles, ImageBuilder automation, and upstream update checks. No private IPs, domains, topologies, credentials, or subscriptions are stored here.

---

## Two-Repository Architecture

| Repository | Responsibility | Link |
| --- | --- | --- |
| **`HomoLand/homorouter-image`** *(this repo)* | Declarative ImmortalWrt 25.12.x profiles, ImageBuilder build/audit scripts, and firmware CI/CD pipeline | [`HomoLand/homorouter-image`](https://github.com/HomoLand/homorouter-image) |
| **`HomoLand/luci-theme-endfield`** | Standalone universal LuCI 25.12 theme (`luci-theme-endfield`) and optional `ubus` Command Console (`luci-app-endfield-console`) | [`HomoLand/luci-theme-endfield`](https://github.com/HomoLand/luci-theme-endfield) |

During firmware builds, [`.github/workflows/build.yml`](.github/workflows/build.yml) checks out [`HomoLand/luci-theme-endfield`](https://github.com/HomoLand/luci-theme-endfield) (configurable via `endfield_theme_ref`, default `main`) and runs its `scripts/stage-files.sh` to bake the Endfield theme and/or Command Console cleanly into `/rom`.

If you only want the theme or Command Console for an existing OpenWrt / ImmortalWrt 25.12 router, install directly from [`HomoLand/luci-theme-endfield`](https://github.com/HomoLand/luci-theme-endfield) — no custom firmware flash required.

---

## Supported Firmware Profiles

- **`x86_64-efi`** — Unified EFI squashfs image (`128 MiB /boot`, `1 GiB` overlay, Intel I226-V / RTL8111 / Mellanox ConnectX-3, NVMe/eMMC/SATA)
- **`r68s`** — Lunzn FastRhino R68S (`rockchip/armv8`, `1 GiB` overlay, `kmod-r8125`)

---

## Pipeline Features & Guardrails

- **Verified ImageBuilder download**: Checks official ImmortalWrt ImageBuilder archive SHA256 prior to extraction and persists the `dl/` cache across builds.
- **Fresh OpenClash dev UI**: Optionally bundles the latest `vernesong/OpenClash` `package/dev` `.apk` (with SHA256 verification) so fresh Zashboard / MetaCubeXD assets live in `/rom`.
- **Optional AdGuardHome static binary**: Optionally embeds the latest upstream `AdGuardHome` binary at `/opt/AdGuardHome/AdGuardHome` (`0755`).
- **Configurable Endfield UI embedding**: Toggle `embed_endfield_theme` (`true`), `embed_endfield_console` (`true`), and `endfield_theme_ref` (`main`, tag, or SHA) on manual workflow runs.
- **Package & Privacy Audits**: Enforces `REQUIRED_AUDIT_PACKAGES` and `FORBIDDEN_PACKAGES` on every built manifest, emitting `package-audit.txt` and `SHA256SUMS`.

---

## Local Usage

```sh
# Validate profiles without downloading ImageBuilder
sh imagebuilder/build.sh --profile x86_64-efi --dry-run
sh imagebuilder/build.sh --profile r68s --dry-run

# Check upstream ImmortalWrt / OpenClash / AdGuardHome updates
python3 imagebuilder/check-updates.py --profile x86_64-efi
```

To embed `luci-theme-endfield` and `luci-app-endfield-console` during a local firmware build:

```sh
git clone https://github.com/HomoLand/luci-theme-endfield.git /tmp/luci-theme-endfield
sh /tmp/luci-theme-endfield/scripts/stage-files.sh --with-console /tmp/extra-files
sh imagebuilder/build.sh --profile x86_64-efi --extra-files /tmp/extra-files
```
