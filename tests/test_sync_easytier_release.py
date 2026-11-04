import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts import sync_easytier_release as sync

REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = REPO_ROOT / "easytier-magisk"


class SyncEasyTierReleaseTest(unittest.TestCase):
    def test_release_identity_uses_upstream_version_and_date(self):
        identity = sync.build_release_identity(
            upstream_tag="v2.6.4",
            date="20260628",
            repository="iGwkang/easytier-magisk",
        )

        self.assertEqual(identity.module_version, "v2.6.4")
        self.assertEqual(identity.version_code, 20260628)
        self.assertEqual(identity.release_tag, "v2.6.4-20260628")
        self.assertEqual(identity.zip_name, "easytier-magisk-v2.6.4-20260628.zip")
        self.assertEqual(
            identity.zip_url,
            "https://github.com/iGwkang/easytier-magisk/releases/download/v2.6.4-20260628/easytier-magisk-v2.6.4-20260628.zip",
        )

    def test_update_json_preserves_changelog_url_and_updates_release_fields(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            update_json = Path(temp_dir) / "update.json"
            update_json.write_text(
                json.dumps(
                    {
                        "version": "v2.3.2",
                        "versionCode": 20250707,
                        "zipUrl": "old",
                        "changelog": "https://example.test/CHANGELOG.md",
                    }
                ),
                encoding="utf-8",
            )
            identity = sync.build_release_identity("v2.6.4", "20260628", "iGwkang/easytier-magisk")

            sync.update_update_json(update_json, identity)

            data = json.loads(update_json.read_text(encoding="utf-8"))
            self.assertEqual(
                data,
                {
                    "version": "v2.6.4",
                    "versionCode": 20260628,
                    "zipUrl": identity.zip_url,
                    "changelog": "https://example.test/CHANGELOG.md",
                },
            )

    def test_module_prop_updates_only_version_fields(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            module_prop = Path(temp_dir) / "module.prop"
            module_prop.write_text(
                "\n".join(
                    [
                        "id=easytier-magisk",
                        "name=EasyTier for Magisk",
                        "version=v2.3.2",
                        "versionCode=20250707",
                        "author=Gwkang",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            identity = sync.build_release_identity("v2.6.4", "20260628", "iGwkang/easytier-magisk")

            sync.update_module_prop(module_prop, identity)

            self.assertEqual(
                module_prop.read_text(encoding="utf-8"),
                "id=easytier-magisk\n"
                "name=EasyTier for Magisk\n"
                "version=v2.6.4\n"
                "versionCode=20260628\n"
                "author=Gwkang\n",
            )

    def test_find_required_assets_matches_linux_archives(self):
        assets = [
            {"name": "easytier-linux-arm-v2.6.4.zip", "browser_download_url": "wrong-arm"},
            {"name": "easytier-linux-armv7-v2.6.4.zip", "browser_download_url": "arm-url"},
            {"name": "easytier-linux-aarch64-v2.6.4.zip", "browser_download_url": "arm64-url"},
            {"name": "easytier-linux-x86_64-v2.6.4.zip", "browser_download_url": "x64-url"},
        ]

        result = sync.find_required_assets(assets, "v2.6.4")

        self.assertEqual(result, {"arm": "arm-url", "arm64": "arm64-url", "x64": "x64-url"})

    def test_find_required_assets_reports_missing_architecture(self):
        assets = [
            {"name": "easytier-linux-aarch64-v2.6.4.zip", "browser_download_url": "arm64-url"},
            {"name": "easytier-linux-x86_64-v2.6.4.zip", "browser_download_url": "x64-url"},
        ]

        with self.assertRaisesRegex(sync.ReleaseSyncError, "arm"):
            sync.find_required_assets(assets, "v2.6.4")

    def test_find_required_assets_reports_missing_x64(self):
        assets = [
            {"name": "easytier-linux-armv7-v2.6.4.zip", "browser_download_url": "arm-url"},
            {"name": "easytier-linux-aarch64-v2.6.4.zip", "browser_download_url": "arm64-url"},
        ]

        with self.assertRaisesRegex(sync.ReleaseSyncError, "x64"):
            sync.find_required_assets(assets, "v2.6.4")


class ModuleLayoutTest(unittest.TestCase):
    def test_shell_scripts_parse(self):
        scripts = [
            "common.sh",
            "run.sh",
            "service.sh",
            "action.sh",
            "hotspot_nat.sh",
            "customize.sh",
            "uninstall.sh",
        ]
        for script in scripts:
            with self.subTest(script=script):
                subprocess.run(
                    ["sh", "-n", str(MODULE_DIR / script)],
                    check=True,
                    capture_output=True,
                    text=True,
                )

    def test_default_config_has_official_sections(self):
        try:
            import tomllib
        except ModuleNotFoundError:  # pragma: no cover - Python < 3.11
            self.skipTest("tomllib requires Python 3.11+")

        config = tomllib.loads((MODULE_DIR / "config" / "config.toml").read_text(encoding="utf-8"))

        self.assertEqual(config["instance_name"], "default")
        self.assertIn("listeners", config)
        self.assertIn("network_identity", config)
        self.assertIn("peer", config)
        self.assertIn("flags", config)

    def test_every_supported_arch_ships_all_binaries(self):
        for arch in ("arm", "arm64", "x64"):
            for binary in sync.EASYTIER_BINARIES:
                with self.subTest(arch=arch, binary=binary):
                    path = MODULE_DIR / "easytier" / arch / binary
                    self.assertTrue(path.is_file(), f"missing {path}")
                    self.assertGreater(path.stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
