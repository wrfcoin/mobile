"""Stdlib-only checks for the commands actually wired into mobile CI."""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MobileSmokePolicy(unittest.TestCase):
    def test_smoke_runs_flutter_and_wallet_case(self):
        workflow = (ROOT / ".github/workflows/testnet-smoke.yml").read_text()
        self.assertIn("bash scripts/run_mobile_smoke.sh", workflow)
        self.assertNotIn("dart test ", workflow)
        command = (ROOT / "scripts/run_mobile_smoke.sh").read_text()
        self.assertIn("flutter test --no-pub --concurrency=2", command)
        self.assertIn("test/integration/testnet_smoke_probe_test.dart", command)
        self.assertIn("test/integration/testnet_smoke_wallet_send_test.dart", command)
        self.assertNotIn("live_testnet_send_check", command)

    def test_pr_smoke_does_not_inherit_live_target(self):
        workflow = (ROOT / ".github/workflows/testnet-smoke.yml").read_text()
        self.assertNotIn("vars.TESTNET_SMOKE", workflow)
        command = (ROOT / "scripts/run_mobile_smoke.sh").read_text()
        self.assertIn("export TESTNET_SMOKE_BASE_URL=''", command)
        probe = (ROOT / "test/integration/testnet_smoke_probe_test.dart").read_text()
        self.assertNotIn("Platform.environment", probe)
        self.assertIn("HttpServer.bind(InternetAddress.loopbackIPv4, 0)", probe)

    def test_both_pr_workflows_bound_workers_and_supersession(self):
        policy = "cancel-in-progress: ${{ github.event_name == 'pull_request' }}"
        for name in ("ci.yml", "testnet-smoke.yml"):
            with self.subTest(workflow=name):
                workflow = (ROOT / ".github/workflows" / name).read_text()
                self.assertIn(policy, workflow)
                self.assertIn("format('run-{0}', github.run_id)", workflow)
                self.assertIn("python3 -m unittest discover -s scripts/tests", workflow)
                self.assertIn("bash scripts/ci_pub_get.sh", workflow)
                # Hosted SDK/cache actions cannot simply be copied to a self-hosted runner.
                self.assertNotIn("runs-on: [self-hosted", workflow)
                self.assertNotIn("runs-on: self-hosted", workflow)
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("flutter test --no-pub --concurrency=2", ci)
        self.assertIn("flutter analyze --no-pub", ci)

    def test_real_smoke_wrapper_clears_targets_and_runs_named_suites(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "argv.json"
            flutter = root / "flutter"
            flutter.write_text("#!/usr/bin/env python3\nimport json,os,sys\n"
                               "json.dump({'argv':sys.argv[1:],'target':os.environ.get('TESTNET_SMOKE_BASE_URL'),"
                               "'live':os.environ.get('WRFCOIN_LIVE_SEND_CHECK'),'e2e':os.environ.get('WRFCOIN_E2E_BASE_URL')},"
                               "open(os.environ['SMOKE_ARGV_LOG'],'w'))\n")
            flutter.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       SMOKE_ARGV_LOG=str(log), TESTNET_SMOKE_BASE_URL="https://example.invalid/api",
                       WRFCOIN_LIVE_SEND_CHECK="1", WRFCOIN_E2E_BASE_URL="https://example.invalid/api")
            result = subprocess.run(["bash", str(ROOT / "scripts/run_mobile_smoke.sh")],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            observed = json.loads(log.read_text())
            self.assertEqual(observed['target'], '')
            self.assertIsNone(observed['live'])
            self.assertIsNone(observed['e2e'])
            self.assertEqual(observed['argv'], ["test", "--no-pub", "--concurrency=2",
                "test/integration/testnet_smoke_probe_test.dart", "test/integration/testnet_smoke_widget_test.dart",
                "test/integration/testnet_smoke_wallet_send_test.dart"])

    def test_cache_miss_never_fetches_on_self_hosted_or_unknown_runner(self):
        for runner in ('self-hosted', '', 'github-hosted'):
            with self.subTest(runner=runner), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                log = root / "calls"
                flutter = root / "flutter"
                flutter.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$PUB_CALL_LOG"\n'
                                   'case "$*" in *--offline*) exit 42;; esac\nexit 0\n')
                flutter.chmod(0o755)
                env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                           RUNNER_ENVIRONMENT=runner, PUB_CALL_LOG=str(log))
                result = subprocess.run(["bash", str(ROOT / "scripts/ci_pub_get.sh")],
                                        env=env, capture_output=True, text=True, timeout=10)
                calls = log.read_text().splitlines()
                self.assertEqual(calls[0], 'pub get --offline --enforce-lockfile')
                if runner == 'github-hosted':
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(calls[1:], ['pub get --enforce-lockfile'])
                else:
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(len(calls), 1)
                    self.assertIn('PUB_CACHE_REQUIRED', result.stderr)

    def test_warm_cache_has_no_fallback_even_on_hosted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "calls"
            flutter = root / "flutter"
            flutter.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$PUB_CALL_LOG"\nexit 0\n')
            flutter.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "scripts/ci_pub_get.sh")],
                                    env=dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                                             RUNNER_ENVIRONMENT='github-hosted', PUB_CALL_LOG=str(log)),
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(log.read_text().splitlines(), ['pub get --offline --enforce-lockfile'])


if __name__ == "__main__":
    unittest.main()
