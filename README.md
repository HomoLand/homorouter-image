# HomoRouter Image Builder & `luci-theme-endfield`

Declarative **ImmortalWrt 25.12.x** (`Linux 6.12 LTS`, `fw4`, `apk`) automated firmware builder for GitHub Actions, bundled with **`luci-theme-endfield`** — a universal, zero-CDN, dual-mode industrial theme for LuCI 25.12 inspired by *Arknights: Endfield*.

> **Strict Public Boundary**: This repository contains only generic firmware profiles, build scripts, and the universal LuCI theme. No private IPs, domains, topologies, credentials, or subscriptions are stored here.

---

## Features

### 1. `luci-theme-endfield` (Universal LuCI 25.12 Theme)
- **Zero view overrides**: Pure LuCI 25.12 shell (`header.ut` / `footer.ut` / `sysauth.ut`), dynamic sidebar (`menu-endfield.js`), and pure CSS (`cascade.css` / `mobile.css`). Works out of the box on any OpenWrt / ImmortalWrt 25.12 device regardless of installed plugins.
- **Dual industrial palette**:
  - **Titanium Charcoal (Dark)**: Deep anodized charcoal grid + signature Endfield Yellow (`#FFE600`) structural highlights & chamfered primary actions.
  - **Industrial Matte (Light)**: Architectural matte concrete grid + obsidian structural plates (`#14171D`) with high-contrast Endfield Yellow accents.
- **Dynamic navigation & `Ctrl+K` Command Palette**: Automatically indexes every installed LuCI route from `ui.menu.load()` for instant keyboard navigation (`Ctrl+K` quick jump, `[` collapsible sidebar).
- **Native OpenClash `0.48.x` `.oc` CSS-variable bridge**: Automatically harmonizes OpenClash's modern UI with Endfield Light & Dark modes when OpenClash is on its default `classic` theme, while still respecting explicit user theme overrides inside OpenClash.
- **Zero external CDN dependencies**: Instant offline/LAN loading with crisp 4K HiDPI typography and tabular numerals.

### 2. GitHub Actions Automated Firmware Pipeline
- **Supported profiles**:
  - `x86_64-efi` — Unified EFI squashfs image (`128 MiB /boot`, `1 GiB` overlay, Intel I226-V / RTL8111 / Mellanox ConnectX-3, NVMe/eMMC/SATA)
  - `r68s` — Lunzn FastRhino R68S (`rockchip/armv8`, `1 GiB` overlay, `kmod-r8125`)
- **Automated freshness & guardrails**:
  - Verifies official ImmortalWrt ImageBuilder archive SHA256 before extraction.
  - Optionally bundles the latest `vernesong/OpenClash` `package/dev` `.apk` (with SHA256 verification) so fresh Zashboard / MetaCubeXD assets are baked directly into `/rom`.
  - Optionally pre-embeds the latest upstream `AdGuardHome` binary at `/opt/AdGuardHome/AdGuardHome`.
  - Enforces `REQUIRED_AUDIT_PACKAGES` and `FORBIDDEN_PACKAGES` on every built manifest and emits `package-audit.txt` + `SHA256SUMS`.

---

## Quick Install (`luci-theme-endfield` Standalone)

### Option A: Native `.apk` (from GitHub Releases)
```sh
apk add --allow-untrusted luci-theme-endfield-*.apk
```

### Option B: Universal Tarball (any OpenWrt / ImmortalWrt 25.12 router)
```sh
tar -xzf luci-theme-endfield-*.tar.gz
sh luci-theme-endfield-*/scripts/install.sh          # registers Endfield without changing default theme
# or:
sh luci-theme-endfield-*/scripts/install.sh --set-default
```

Then select **Endfield** (auto), **EndfieldDark**, or **EndfieldLight** under **System → System → Language and Style**.

To uninstall cleanly (automatically reverts to Bootstrap if active):
```sh
sh luci-theme-endfield-*/scripts/uninstall.sh
```

---

## Local ImageBuilder Dry-Run

```sh
sh imagebuilder/build.sh --profile x86_64-efi --dry-run
sh imagebuilder/build.sh --profile r68s --dry-run
python3 imagebuilder/check-updates.py --profile x86_64-efi
```
