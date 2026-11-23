#!/usr/bin/env python3
"""Check upstream ImmortalWrt 25.12.x, OpenClash (dev), and AdGuardHome updates.

Designed for both:
  1. Weekly k3s CronJob (read-only release watch + deduplicated Bark alerts).
  2. Workstation one-command custom image builds (--build --profile x86_64-efi).

Uses zero-rate-limit upstream endpoints (no unauthenticated api.github.com calls)
and pure Python 3 stdlib so it runs identically in minimal python:3.13-slim pods.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

USER_AGENT = "homorouter-image-watch/1.0"
IMMORTALWRT_RELEASES_URL = "https://downloads.immortalwrt.org/releases/"
OPENCLASH_VERSION_URLS = {
    "dev": (
        "https://raw.githubusercontent.com/vernesong/OpenClash/package/dev/version",
        "https://testingcf.jsdelivr.net/gh/vernesong/OpenClash@package/dev/version",
    ),
    "master": (
        "https://raw.githubusercontent.com/vernesong/OpenClash/package/master/version",
        "https://testingcf.jsdelivr.net/gh/vernesong/OpenClash@package/master/version",
    ),
}
ADGUARD_LATEST_URL = "https://github.com/AdguardTeam/AdGuardHome/releases/latest"


def normalize_version(raw: str) -> str:
    return (raw or "").strip().lstrip("vV")


def parse_version_tuple(raw: str) -> tuple[int, ...]:
    cleaned = normalize_version(raw)
    m = re.match(r"^(\d+(?:\.\d+)*)", cleaned)
    if not m:
        return ()
    return tuple(int(part) for part in m.group(1).split("."))


def is_newer(latest: str, current: str) -> bool:
    lt = parse_version_tuple(latest)
    ct = parse_version_tuple(current)
    if not lt or not ct:
        return False
    return lt > ct


def http_get_text(url: str, timeout: float = 20.0) -> tuple[str, str]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        final_url = resp.geturl()
        body = resp.read().decode("utf-8", errors="replace")
        return final_url, body


def http_download(url: str, dest: Path, timeout: float = 120.0) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    part = dest.with_suffix(dest.suffix + ".part")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp, part.open("wb") as out:
            shutil.copyfileobj(resp, out)
        if not part.stat().st_size:
            raise RuntimeError(f"downloaded empty file from {url}")
        os.replace(part, dest)
    except Exception:
        if part.exists():
            part.unlink()
        raise


def parse_immortalwrt_releases(html: str, series: str = "25.12") -> list[str]:
    prefix = re.escape(series.strip("."))
    matches = set(re.findall(rf'href="({prefix}\.\d+)/?"', html or ""))
    return sorted(matches, key=parse_version_tuple)


def parse_imagebuilder_sha256(sha_text: str, archive_name: str) -> str:
    for line in (sha_text or "").splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            digest = parts[0].lower()
            name = parts[-1].lstrip("*")
            if name == archive_name and re.fullmatch(r"[0-9a-f]{64}", digest):
                return digest
    return ""


def parse_openclash_version(text: str) -> str:
    for line in (text or "").splitlines():
        m = re.search(r"v?(\d+\.\d+\.\d+)", line.strip())
        if m:
            return m.group(1)
    return ""


def parse_profile_conf(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r'^([A-Z0-9_]+)="([^"]*)"\s*$', line.strip())
        if m:
            result[m.group(1)] = m.group(2)
    return result


def fetch_latest_immortalwrt(series: str = "25.12", timeout: float = 20.0) -> dict[str, object]:
    _, html = http_get_text(IMMORTALWRT_RELEASES_URL, timeout=timeout)
    releases = parse_immortalwrt_releases(html, series=series)
    if not releases:
        raise RuntimeError(f"no ImmortalWrt {series}.x releases found")
    latest = releases[-1]
    targets = {
        "x86_64-efi": (
            "x86/64",
            f"immortalwrt-imagebuilder-{latest}-x86-64.Linux-x86_64.tar.zst",
        ),
        "r68s": (
            "rockchip/armv8",
            f"immortalwrt-imagebuilder-{latest}-rockchip-armv8.Linux-x86_64.tar.zst",
        ),
    }
    ib_info: dict[str, dict[str, str]] = {}
    for prof, (subtarget, archive) in targets.items():
        sums_url = f"{IMMORTALWRT_RELEASES_URL}{latest}/targets/{subtarget}/sha256sums"
        try:
            _, sums_text = http_get_text(sums_url, timeout=timeout)
            digest = parse_imagebuilder_sha256(sums_text, archive)
        except Exception:
            digest = ""
        ib_info[prof] = {
            "archive": archive,
            "url": f"{IMMORTALWRT_RELEASES_URL}{latest}/targets/{subtarget}/{archive}",
            "sha256": digest,
        }
    return {
        "series": series,
        "latest": latest,
        "releases": releases,
        "imagebuilders": ib_info,
    }


def fetch_latest_openclash(branch: str = "dev", timeout: float = 20.0) -> dict[str, str]:
    urls = OPENCLASH_VERSION_URLS.get(branch)
    if not urls:
        raise ValueError(f"unsupported OpenClash branch: {branch}")
    last_err: Exception | None = None
    ver = ""
    source_url = ""
    for url in urls:
        try:
            _, text = http_get_text(url, timeout=timeout)
            ver = parse_openclash_version(text)
            if ver:
                source_url = url
                break
        except Exception as exc:
            last_err = exc
    if not ver:
        raise RuntimeError(f"failed to resolve OpenClash ({branch}) version: {last_err}")
    apk_name = f"luci-app-openclash-{ver}.apk"
    apk_url = f"https://raw.githubusercontent.com/vernesong/OpenClash/package/{branch}/{apk_name}"
    mirror_url = f"https://testingcf.jsdelivr.net/gh/vernesong/OpenClash@package/{branch}/{apk_name}"
    return {
        "branch": branch,
        "latest": ver,
        "apk_name": apk_name,
        "apk_url": apk_url,
        "mirror_url": mirror_url,
        "source": source_url,
    }


def fetch_latest_adguard(timeout: float = 20.0) -> dict[str, str]:
    final_url, _ = http_get_text(ADGUARD_LATEST_URL, timeout=timeout)
    tag = final_url.rstrip("/").split("/")[-1]
    ver = normalize_version(tag)
    if not parse_version_tuple(ver):
        raise RuntimeError(f"unexpected AdGuardHome release tag from redirect: {tag}")
    return {
        "tag": tag,
        "latest": ver,
        "amd64_url": f"https://github.com/AdguardTeam/AdGuardHome/releases/download/{tag}/AdGuardHome_linux_amd64.tar.gz",
        "arm64_url": f"https://github.com/AdguardTeam/AdGuardHome/releases/download/{tag}/AdGuardHome_linux_arm64.tar.gz",
    }


def compare_updates(
    current: dict[str, str],
    latest: dict[str, str],
    watch: tuple[str, ...] = ("immortalwrt", "openclash", "adguardhome"),
) -> dict[str, dict[str, object]]:
    report: dict[str, dict[str, object]] = {}
    for comp in ("immortalwrt", "openclash", "adguardhome"):
        cur = normalize_version(current.get(comp, ""))
        lat = normalize_version(latest.get(comp, ""))
        has_update = bool(comp in watch and cur and lat and is_newer(lat, cur))
        report[comp] = {
            "current": cur,
            "latest": lat,
            "watched": comp in watch,
            "update_available": has_update,
        }
    return report


def load_state(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(path: Path, state: dict[str, object]) -> None:
    os.umask(0o077)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def pending_notifications(
    report: dict[str, dict[str, object]],
    state: dict[str, object],
    force: bool = False,
) -> dict[str, dict[str, object]]:
    notified = state.get("notified")
    if not isinstance(notified, dict):
        notified = {}
    pending: dict[str, dict[str, object]] = {}
    for comp, info in report.items():
        if not info.get("update_available"):
            continue
        lat = str(info.get("latest") or "")
        if force or notified.get(comp) != lat:
            pending[comp] = info
    return pending


def format_bark_message(pending: dict[str, dict[str, object]]) -> tuple[str, str]:
    labels = {
        "immortalwrt": "ImmortalWrt",
        "openclash": "OpenClash",
        "adguardhome": "AdGuardHome",
    }
    lines = []
    for comp in ("immortalwrt", "openclash", "adguardhome"):
        if comp in pending:
            info = pending[comp]
            lines.append(f"{labels[comp]}: {info['current']} -> {info['latest']}")
    title = "HomoRouter 发现可用更新"
    body = "\n".join(lines) + "\n维护窗口可执行 check-updates.py --build 构镜并用 sysupgrade-rollout.sh 升级。"
    return title, body


def send_bark(
    bark_url: str,
    title: str,
    body: str,
    group: str = "router-firmware",
    level: str = "active",
    ttl: int = 86400,
    timeout: float = 15.0,
) -> bool:
    parsed = urllib.parse.urlparse((bark_url or "").strip())
    if parsed.scheme != "https" or not parsed.netloc:
        return False
    payload = json.dumps(
        {
            "title": title,
            "body": body,
            "group": group,
            "level": level,
            "ttl": ttl,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        parsed.geturl(),
        data=payload,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            if not raw:
                return resp.status == 200
            data = json.loads(raw)
            return isinstance(data, dict) and data.get("code") == 200
    except Exception:
        return False


def build_updated_image(
    repo_root: Path,
    profile_name: str,
    im_info: dict[str, object],
    oc_info: dict[str, str],
    ag_info: dict[str, str],
    out_dir: str,
    work_dir: str,
    extra_files: str,
) -> None:
    build_sh = repo_root / "imagebuilder" / "build.sh"
    base_profile = repo_root / "imagebuilder" / "profiles" / f"{profile_name}.conf"
    if not build_sh.is_file() or not base_profile.is_file():
        raise RuntimeError(f"missing build.sh or profile {profile_name} under {repo_root / 'imagebuilder'}")

    arch_key = "arm64_url" if profile_name == "r68s" else "amd64_url"
    ib_map = im_info.get("imagebuilders") or {}
    ib_target = ib_map.get(profile_name) if isinstance(ib_map, dict) else None
    if not isinstance(ib_target, dict) or not ib_target.get("sha256"):
        raise RuntimeError(f"missing verified ImmortalWrt ImageBuilder SHA256 for profile {profile_name}")

    with tempfile.TemporaryDirectory(prefix="rk-fw-autobuild-") as td:
        td_path = Path(td)
        # 1. Stage updated profile if latest ImmortalWrt release differs from checked-in profile.
        prof_text = base_profile.read_text(encoding="utf-8")
        latest_rel = str(im_info["latest"])
        prof_text = re.sub(r'^IMMORTALWRT_RELEASE="[^"]*"', f'IMMORTALWRT_RELEASE="{latest_rel}"', prof_text, flags=re.M)
        prof_text = re.sub(r'^IMAGEBUILDER_ARCHIVE="[^"]*"', f'IMAGEBUILDER_ARCHIVE="{ib_target["archive"]}"', prof_text, flags=re.M)
        prof_text = re.sub(r'^IMAGEBUILDER_URL="[^"]*"', f'IMAGEBUILDER_URL="{ib_target["url"]}"', prof_text, flags=re.M)
        prof_text = re.sub(r'^IMAGEBUILDER_SHA256="[^"]*"', f'IMAGEBUILDER_SHA256="{ib_target["sha256"]}"', prof_text, flags=re.M)
        staged_profile = td_path / f"{profile_name}.conf"
        staged_profile.write_text(prof_text, encoding="utf-8")

        # 2. Download latest OpenClash .apk into --local-packages directory.
        local_pkgs = td_path / "local-apks"
        local_pkgs.mkdir(parents=True, exist_ok=True)
        apk_dest = local_pkgs / oc_info["apk_name"]
        try:
            http_download(oc_info["apk_url"], apk_dest)
        except Exception:
            http_download(oc_info["mirror_url"], apk_dest)

        # 3. Download and extract latest AdGuardHome static binary.
        ag_tgz = td_path / "adguardhome.tar.gz"
        http_download(ag_info[arch_key], ag_tgz)
        ag_bin = td_path / "AdGuardHome"
        with tarfile.open(ag_tgz, "r:gz") as tf:
            member = next((m for m in tf.getmembers() if m.isfile() and m.name.endswith("/AdGuardHome")), None)
            if member is None:
                raise RuntimeError("AdGuardHome binary not found in downloaded release archive")
            src = tf.extractfile(member)
            if src is None:
                raise RuntimeError("failed to extract AdGuardHome binary")
            with src, ag_bin.open("wb") as out:
                shutil.copyfileobj(src, out)
        os.chmod(ag_bin, 0o755)

        cmd = [
            "sh",
            str(build_sh),
            "--profile",
            str(staged_profile),
            "--adguard-bin",
            str(ag_bin),
            "--local-packages",
            str(local_pkgs),
        ]
        if work_dir:
            cmd.extend(["--work-dir", work_dir])
        if out_dir:
            cmd.extend(["--out-dir", out_dir])
        if extra_files:
            cmd.extend(["--extra-files", extra_files])
        subprocess.run(cmd, check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check ImmortalWrt 25.12.x, OpenClash, and AdGuardHome updates.")
    parser.add_argument("--series", default=os.environ.get("IMMORTALWRT_SERIES", "25.12"))
    parser.add_argument("--openclash-branch", default=os.environ.get("OPENCLASH_BRANCH", "dev"))
    parser.add_argument("--current-immortalwrt", default=os.environ.get("CURRENT_IMMORTALWRT", ""))
    parser.add_argument("--current-openclash", default=os.environ.get("CURRENT_OPENCLASH", "0.48.016"))
    parser.add_argument("--current-adguard", default=os.environ.get("CURRENT_ADGUARD", "v0.107.77"))
    parser.add_argument(
        "--watch",
        default=os.environ.get("WATCH_COMPONENTS", "immortalwrt,openclash,adguardhome"),
        help="Comma-separated components to alert on (default: immortalwrt,openclash,adguardhome)",
    )
    parser.add_argument("--state-file", default=os.environ.get("FIRMWARE_WATCH_STATE", ""))
    parser.add_argument("--bark", action="store_true", help="Send Bark notification via BARK_URL env when new updates appear.")
    parser.add_argument("--force-notify", action="store_true", help="Send Bark even if already notified for this version.")
    parser.add_argument("--seed-state", action="store_true", help="Record current latest versions in state file without sending Bark.")
    parser.add_argument("--json", action="store_true", help="Emit structured JSON output.")
    parser.add_argument("--build", action="store_true", help="Download latest OpenClash APK & AdGuardHome and run imagebuilder/build.sh.")
    parser.add_argument("--profile", default="x86_64-efi", choices=("x86_64-efi", "r68s"))
    parser.add_argument("--out-dir", default="")
    parser.add_argument("--work-dir", default="")
    parser.add_argument("--extra-files", default="")
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parent.parent
    cur_im = args.current_immortalwrt
    if not cur_im:
        prof_data = parse_profile_conf(repo_root / "imagebuilder" / "profiles" / f"{args.profile}.conf")
        cur_im = prof_data.get("IMMORTALWRT_RELEASE", "25.12.2")

    watch_tuple = tuple(c.strip().lower() for c in args.watch.split(",") if c.strip())

    im_info = fetch_latest_immortalwrt(series=args.series)
    oc_info = fetch_latest_openclash(branch=args.openclash_branch)
    ag_info = fetch_latest_adguard()

    current_map = {
        "immortalwrt": cur_im,
        "openclash": args.current_openclash,
        "adguardhome": args.current_adguard,
    }
    latest_map = {
        "immortalwrt": str(im_info["latest"]),
        "openclash": str(oc_info["latest"]),
        "adguardhome": str(ag_info["latest"]),
    }
    report = compare_updates(current_map, latest_map, watch=watch_tuple)

    state_path = Path(args.state_file) if args.state_file else None
    state = load_state(state_path) if state_path else {}
    pending = pending_notifications(report, state, force=args.force_notify)

    bark_sent = False
    if args.seed_state and state_path:
        notified = state.get("notified")
        if not isinstance(notified, dict):
            notified = {}
        for comp, info in report.items():
            if info.get("update_available"):
                notified[comp] = info["latest"]
        state["notified"] = notified
        state["last_checked_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        state["latest"] = latest_map
        save_state(state_path, state)
    elif args.bark and pending:
        title, body = format_bark_message(pending)
        bark_url = os.environ.get("BARK_URL", "")
        bark_sent = send_bark(bark_url, title, body)
        if state_path and bark_sent:
            notified = state.get("notified")
            if not isinstance(notified, dict):
                notified = {}
            for comp, info in pending.items():
                notified[comp] = info["latest"]
            state["notified"] = notified
            state["last_notified_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            state["last_checked_utc"] = state["last_notified_utc"]
            state["latest"] = latest_map
            save_state(state_path, state)
    elif state_path:
        state["last_checked_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        state["latest"] = latest_map
        save_state(state_path, state)

    result = {
        "checked_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "components": report,
        "immortalwrt": im_info,
        "openclash": oc_info,
        "adguardhome": ag_info,
        "pending_notifications": list(pending.keys()),
        "bark_sent": bark_sent,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for comp in ("immortalwrt", "openclash", "adguardhome"):
            info = report[comp]
            flag = "UPDATE" if info["update_available"] else "ok"
            print(f"{comp:12s} current={info['current']:10s} latest={info['latest']:10s} [{flag}]")
        if pending:
            print(f"pending_notify={','.join(pending.keys())} bark_sent={bark_sent}")
        else:
            print("pending_notify=none")

    if args.build:
        build_updated_image(
            repo_root=repo_root,
            profile_name=args.profile,
            im_info=im_info,
            oc_info=oc_info,
            ag_info=ag_info,
            out_dir=args.out_dir,
            work_dir=args.work_dir,
            extra_files=args.extra_files,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
