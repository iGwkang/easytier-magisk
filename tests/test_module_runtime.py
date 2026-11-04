import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = REPO_ROOT / "easytier-magisk"
COMMON_SH = MODULE_DIR / "common.sh"


def run_sh(
    script: str,
    env: dict[str, str],
    cwd: Path,
    args: list[str] | None = None,
) -> subprocess.CompletedProcess:
    merged = os.environ.copy()
    merged.update(env)
    command = ["sh", "-c", script]
    if args:
        command += ["sh", *args]
    return subprocess.run(
        command,
        cwd=str(cwd),
        env=merged,
        capture_output=True,
        text=True,
    )


class CommandArgsTokenizerTest(unittest.TestCase):
    def tokenize(self, content: str) -> list[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            data_dir = base / "data"
            data_dir.mkdir()
            args_file = data_dir / "command_args"
            args_file.write_text(content, encoding="utf-8")
            result = run_sh(
                '. "$COMMON_SH"; command_args_tokens',
                {"ET_DATA_DIR": str(data_dir), "COMMON_SH": str(COMMON_SH)},
                base,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.splitlines()

    def test_splits_whitespace_and_ignores_comments(self):
        tokens = self.tokenize(
            "# comment --ignored\n"
            "--config-server udp://1.2.3.4:22020/admin\n"
            "\n"
            "  --machine-id android-phone  \n"
        )
        self.assertEqual(
            tokens,
            ["--config-server", "udp://1.2.3.4:22020/admin", "--machine-id", "android-phone"],
        )

    def test_keeps_quoted_values_with_spaces(self):
        tokens = self.tokenize(
            '-c "/data/adb/a b.toml"\n'
            "-c '/data/adb/c d.toml'\n"
            "--esc=a\\ b\n"
        )
        self.assertEqual(
            tokens,
            ["-c", "/data/adb/a b.toml", "-c", "/data/adb/c d.toml", "--esc=a b"],
        )

    def test_handles_crlf(self):
        tokens = self.tokenize("--no-tun\r\n-c /data/adb/a.toml\r\n")
        self.assertEqual(tokens, ["--no-tun", "-c", "/data/adb/a.toml"])


class OptionMatcherTest(unittest.TestCase):
    def check(self, *args: str) -> bool:
        with tempfile.TemporaryDirectory() as temp_dir:
            result = run_sh(
                '. "$COMMON_SH"; args_contain_any "$@"',
                {"COMMON_SH": str(COMMON_SH), "ET_DATA_DIR": temp_dir},
                Path(temp_dir),
                args=list(args),
            )
            self.assertIn(result.returncode, (0, 1), result.stderr)
            return result.returncode == 0

    def test_matches_plain_and_equals_form(self):
        self.assertTrue(self.check("--file-log-dir", "--file-log-dir", "/tmp"))
        self.assertTrue(self.check("--file-log-dir", "--file-log-dir=/tmp"))

    def test_does_not_match_option_text_inside_value(self):
        self.assertFalse(self.check("--file-log-dir", "-c", "/tmp/a --file-log-dir b"))

    def test_short_flag_match(self):
        self.assertTrue(self.check("-r", "-r", "127.0.0.1:15888"))
        self.assertFalse(self.check("-r", "--relay-network-whitelist", "*"))


class IpRuleTest(unittest.TestCase):
    def run_with_stub(self, script: str, rule_output: str) -> tuple[str, subprocess.CompletedProcess]:
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            bin_dir = base / "bin"
            bin_dir.mkdir()
            calls = base / "ip.calls"
            stub = bin_dir / "ip"
            stub.write_text(
                "#!/bin/sh\n"
                'echo "$@" >> "$IP_CALLS"\n'
                'case "$*" in\n'
                '  *"rule show"*) printf "%b" "$IP_RULE_OUTPUT" ;;\n'
                "esac\n"
                "exit 0\n",
                encoding="utf-8",
            )
            stub.chmod(0o755)
            result = run_sh(
                script,
                {
                    "COMMON_SH": str(COMMON_SH),
                    "IP_CALLS": str(calls),
                    "IP_RULE_OUTPUT": rule_output,
                    "ET_DATA_DIR": str(base / "data"),
                    "PATH": bin_dir.as_posix() + ":" + os.environ.get("PATH", ""),
                },
                base,
            )
            recorded = calls.read_text(encoding="utf-8") if calls.exists() else ""
            return recorded, result

    def test_adds_pref_30000_rule_before_android_unreachable(self):
        calls, result = self.run_with_stub(
            '. "$COMMON_SH"; ensure_ip_rule', "32000:\tfrom all unreachable\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rule add pref 30000 from all lookup main", calls)
        self.assertIn("-6 rule add pref 30000 from all lookup main", calls)

    def test_skips_existing_rules(self):
        calls, result = self.run_with_stub(
            '. "$COMMON_SH"; ensure_ip_rule',
            "30000:\tfrom all lookup main\n32000:\tfrom all unreachable\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("rule add", calls)

    def test_does_not_treat_legacy_32766_rule_as_present(self):
        calls, result = self.run_with_stub(
            '. "$COMMON_SH"; ensure_ip_rule',
            "32766:\tfrom all lookup main\n32000:\tfrom all unreachable\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rule add pref 30000 from all lookup main", calls)

    def test_remove_ip_rule(self):
        calls, result = self.run_with_stub('. "$COMMON_SH"; remove_ip_rule', "")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rule del pref 30000 from all lookup main", calls)
        self.assertIn("-6 rule del pref 30000 from all lookup main", calls)


if __name__ == "__main__":
    unittest.main()
