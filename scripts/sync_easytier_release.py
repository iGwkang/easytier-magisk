from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


UPSTREAM_REPOSITORY = "EasyTier/EasyTier"
DEFAULT_REPOSITORY = "iGwkang/easytier-magisk"
MODULE_DIR = Path("easytier-magisk")
CHANGELOG_PATH = Path("CHANGELOG.md")
UPDATE_JSON_PATH = Path("update.json")
MODULE_PROP_PATH = MODULE_DIR / "module.prop"
EASYTIER_DIR = MODULE_DIR / "easytier"
ARCHIVE_PREFIX = "easytier-magisk"
ARCHIVE_EXCLUDES = {".git", ".github", ".agents", ".codex", "tests", "scripts"}
EASYTIER_BINARIES = ("easytier-cli", "easytier-core", "easytier-web", "easytier-web-embed")


class ReleaseSyncError(RuntimeError):
    """Raised when release synchronization cannot continue safely."""


@dataclass(frozen=True)
class ReleaseIdentity:
    module_version: str
    version_code: int
    release_tag: str
    zip_name: str
    zip_url: str


def build_release_identity(upstream_tag: str, date: str, repository: str) -> ReleaseIdentity:
    if not re.fullmatch(r"\d{8}", date):
        raise ReleaseSyncError(f"date must use yyyymmdd format, got {date!r}")
    module_version = upstream_tag if upstream_tag.startswith("v") else f"v{upstream_tag}"
    version_code = int(date)
    release_tag = f"{module_version}-{date}"
    zip_name = f"{ARCHIVE_PREFIX}-{release_tag}.zip"
    zip_url = f"https://github.com/{repository}/releases/download/{release_tag}/{zip_name}"
    return ReleaseIdentity(
        module_version=module_version,
        version_code=version_code,
        release_tag=release_tag,
        zip_name=zip_name,
        zip_url=zip_url,
    )


def update_update_json(path: Path, identity: ReleaseIdentity) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    data["version"] = identity.module_version
    data["versionCode"] = identity.version_code
    data["zipUrl"] = identity.zip_url
    path.write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")


def update_module_prop(path: Path, identity: ReleaseIdentity) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    updated: list[str] = []
    seen = {"version": False, "versionCode": False}
    for line in lines:
        if line.startswith("version="):
            updated.append(f"version={identity.module_version}")
            seen["version"] = True
        elif line.startswith("versionCode="):
            updated.append(f"versionCode={identity.version_code}")
            seen["versionCode"] = True
        else:
            updated.append(line)
    missing = [key for key, found in seen.items() if not found]
    if missing:
        raise ReleaseSyncError(f"module.prop missing required field(s): {', '.join(missing)}")
    path.write_text("\n".join(updated) + "\n", encoding="utf-8")


def find_required_assets(assets: list[dict[str, Any]], tag_name: str) -> dict[str, str]:
    version = tag_name if tag_name.startswith("v") else f"v{tag_name}"
    patterns = {
        "arm": re.compile(rf"^easytier-linux-armv7-{re.escape(version)}\.zip$"),
        "arm64": re.compile(rf"^easytier-linux-aarch64-{re.escape(version)}\.zip$"),
    }
    found: dict[str, str] = {}
    for asset in assets:
        name = str(asset.get("name", ""))
        url = str(asset.get("browser_download_url", ""))
        for arch, pattern in patterns.items():
            if pattern.fullmatch(name):
                found[arch] = url
    missing = sorted(set(patterns) - set(found))
    if missing:
        asset_names = ", ".join(str(asset.get("name", "")) for asset in assets)
        raise ReleaseSyncError(
            f"missing required EasyTier release asset(s): {', '.join(missing)}. Available assets: {asset_names}"
        )
    return found


def fetch_json(url: str, token: str | None = None) -> dict[str, Any]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "easytier-magisk-release-sync",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ReleaseSyncError(f"GitHub API request failed: {exc.code} {exc.reason}: {body}") from exc


def download_file(url: str, destination: Path, token: str | None = None) -> None:
    headers = {"User-Agent": "easytier-magisk-release-sync"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(request, timeout=300) as response:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)


def copy_arch_binaries(archive_path: Path, destination_dir: Path) -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        extract_dir = Path(temp_dir)
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(extract_dir)
        binaries = {}
        for binary in EASYTIER_BINARIES:
            matches = [path for path in extract_dir.rglob(binary) if path.is_file()]
            if not matches:
                raise ReleaseSyncError(f"{archive_path.name} does not contain required binary {binary}")
            binaries[binary] = matches[0]
        destination_dir.mkdir(parents=True, exist_ok=True)
        for binary, source in binaries.items():
            destination = destination_dir / binary
            shutil.copy2(source, destination)
            destination.chmod(destination.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def sync_binaries(asset_urls: dict[str, str], token: str | None = None) -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        download_dir = Path(temp_dir)
        for arch, url in asset_urls.items():
            archive_path = download_dir / f"{arch}.zip"
            download_file(url, archive_path, token=token)
            copy_arch_binaries(archive_path, EASYTIER_DIR / arch)


def write_changelog(path: Path, release_body: str) -> None:
    path.write_text(release_body.rstrip() + "\n", encoding="utf-8")


def create_module_zip(module_dir: Path, output_path: Path) -> None:
    if output_path.exists():
        output_path.unlink()
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(module_dir.rglob("*")):
            if path == output_path or path.name.endswith(".zip"):
                continue
            if path.is_file():
                archive.write(path, path.relative_to(module_dir).as_posix())


def get_current_version(path: Path) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    version = str(data.get("version", ""))
    if not version:
        raise ReleaseSyncError("update.json missing version")
    return version


def today_yyyymmdd() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d")


def sync_release(repository: str, date: str, dry_run: bool = False) -> ReleaseIdentity | None:
    token = os.environ.get("GITHUB_TOKEN")
    latest = fetch_json(f"https://api.github.com/repos/{UPSTREAM_REPOSITORY}/releases/latest", token=token)
    upstream_tag = str(latest.get("tag_name", ""))
    if not upstream_tag:
        raise ReleaseSyncError("upstream latest release does not include tag_name")

    current_version = get_current_version(UPDATE_JSON_PATH)
    upstream_version = upstream_tag if upstream_tag.startswith("v") else f"v{upstream_tag}"
    if current_version == upstream_version:
        print(f"EasyTier is already up to date: {current_version}")
        return None

    identity = build_release_identity(upstream_tag, date, repository)
    if dry_run:
        print(f"New EasyTier release detected: {current_version} -> {identity.module_version}")
        return identity

    asset_urls = find_required_assets(list(latest.get("assets", [])), identity.module_version)
    sync_binaries(asset_urls, token=token)
    write_changelog(CHANGELOG_PATH, str(latest.get("body", "")))
    update_module_prop(MODULE_PROP_PATH, identity)
    update_update_json(UPDATE_JSON_PATH, identity)
    create_module_zip(MODULE_DIR, MODULE_DIR / identity.zip_name)
    print(f"Prepared {identity.release_tag}")
    return identity


def write_github_output(identity: ReleaseIdentity | None) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    values = {
        "updated": "true" if identity else "false",
        "release_tag": identity.release_tag if identity else "",
        "zip_name": identity.zip_name if identity else "",
        "zip_path": str(MODULE_DIR / identity.zip_name) if identity else "",
    }
    with Path(output_path).open("a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync easytier-magisk with the latest EasyTier release.")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPOSITORY))
    parser.add_argument("--date", default=os.environ.get("RELEASE_DATE", today_yyyymmdd()))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(list(argv or sys.argv[1:]))
    try:
        identity = sync_release(repository=args.repository, date=args.date, dry_run=args.dry_run)
        write_github_output(identity)
        return 0
    except ReleaseSyncError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
