import json
import tempfile
import unittest
from pathlib import Path

from scripts import sync_easytier_release as sync


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

    def test_find_required_assets_matches_linux_arm_archives(self):
        assets = [
            {"name": "easytier-linux-arm-v2.6.4.zip", "browser_download_url": "wrong-arm"},
            {"name": "easytier-linux-armv7-v2.6.4.zip", "browser_download_url": "arm-url"},
            {"name": "easytier-linux-aarch64-v2.6.4.zip", "browser_download_url": "arm64-url"},
        ]

        result = sync.find_required_assets(assets, "v2.6.4")

        self.assertEqual(result, {"arm": "arm-url", "arm64": "arm64-url"})

    def test_find_required_assets_reports_missing_architecture(self):
        assets = [
            {"name": "easytier-android-aarch64-v2.6.4.zip", "browser_download_url": "arm64-url"},
        ]

        with self.assertRaisesRegex(sync.ReleaseSyncError, "arm"):
            sync.find_required_assets(assets, "v2.6.4")


if __name__ == "__main__":
    unittest.main()
