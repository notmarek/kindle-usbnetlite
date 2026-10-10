"""Behavior regressions for Wi-Fi-only SSH using real source script copies."""

import io
import os
import re
import shlex
import tarfile
import unittest

from kindle_fixture import (
    DAEMON_DIAGNOSTIC, EXTENSION, KindleFixture, PASSWORD, USB_COMMANDS,
    WINDOW_SIZE, write,
)


class WifiSSHTests(unittest.TestCase):
    def setUp(self):
        self.kindle = KindleFixture()
        self.addCleanup(self.kindle.close)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_no_usb(self):
        self.assertEqual([event for event in self.kindle.events()
                          if event["command"] in USB_COMMANDS], [])

    def assert_no_secrets(self, result):
        output = result.stdout + result.stderr
        for path in self.kindle.root.rglob("*.log"):
            output += path.read_text()
        self.assertNotIn(PASSWORD, output)
        self.assertNotIn(WINDOW_SIZE.strip(), output)
        self.assertNotIn(DAEMON_DIAGNOSTIC, output)

    def upstart_section(self, job, section):
        content = (EXTENSION / job).read_text()
        match = re.search(rf"^{section} script\n(.*?)^end script$", content, re.M | re.S)
        self.assertIsNotNone(match)
        return write(self.kindle.root / "upstart-section", self.kindle.rewrite(match.group(1)))

    def test_start_before_dhcp_uses_direct_multicall_and_intact_arguments(self):
        k = self.kindle
        # wlan0 exists, but no address, lease, or legacy /usr/bin/dropbear does.
        self.assertFalse((k.root / "usr/bin/dropbear").exists())
        self.assertEqual(list(k.wlan.iterdir()), [])
        result = k.run(None, "start")
        self.assert_ok(result)
        invocations = k.events("dropbearmulti")
        self.assertEqual(len(invocations), 1)
        self.assertEqual(invocations[0]["args"], [
            "dropbear", "-P", str(k.pidfile), "-K", "15", "-R", "-H",
            str(k.root / "mnt/us"), "-p", "2222", "-l", "wlan0",
            "-Y", PASSWORD, "-W", WINDOW_SIZE,
        ])
        self.assertNotIn("-E", invocations[0]["args"])
        self.assert_no_secrets(result)
        self.assert_no_usb()
        self.assertEqual(k.events("sleep"), [])

    def test_start_stop_are_idempotent_including_firewall(self):
        k = self.kindle
        for old_iptables in (False, True):
            with self.subTest(old_iptables=old_iptables):
                k.options(old_iptables=old_iptables)
                before = len(k.events("dropbearmulti"))
                for _ in range(2):
                    self.assert_ok(k.run(None, "start"))
                self.assertEqual(len(k.events("dropbearmulti")), before + 1)
                self.assertEqual(k.rules(), [["INPUT", "-i", "wlan0", "-p", "tcp", "--dport", "2222", "-j", "ACCEPT"]])
                self.assert_ok(k.run(None, "status"))
                for _ in range(2):
                    self.assert_ok(k.run(None, "stop"))
                self.assertEqual(k.rules(), [])
                self.assertFalse(k.pidfile.exists())
                self.assertNotEqual(k.run(None, "status").returncode, 0)
        signals = [event for event in k.events("kill") if event["args"][0] != "-0"]
        self.assertEqual([event["args"] for event in signals], [["-TERM", "515151"]] * 2)
        self.assert_no_usb()

    def test_stale_pid_never_kills_unrelated_live_process(self):
        k = self.kindle
        pid = k.process(executable=k.root / "usr/bin/unrelated")
        self.assertNotEqual(k.run(None, "status").returncode, 0)
        self.assert_ok(k.run(None, "stop"))
        self.assertTrue((k.root / f"proc/{pid}/alive").exists())
        self.assertFalse(k.pidfile.exists())
        self.assertEqual([event for event in k.events("kill") if event["args"][0] != "-0"], [])
        write(k.pidfile, str(pid) + "\n")
        self.assert_ok(k.run(None, "start"))
        self.assertTrue((k.root / f"proc/{pid}/alive").exists())

    def test_start_stop_succeed_with_closed_stdout_or_broken_pipe(self):
        k = self.kindle
        for mode in ("closed", "broken_pipe"):
            with self.subTest(stdout=mode):
                for action in ("start", "stop"):
                    with self.subTest(action=action):
                        result = k.run(None, action, stdout_mode=mode)
                        self.assert_ok(result)
                        self.assertEqual(result.stdout, "")
                        self.assertEqual(result.stderr, "")
                        self.assertFalse((k.root / "tmp/usbnetlite-sshd.lock").exists())
                        self.assertEqual((k.root / "proc/515151/alive").exists(), action == "start")
                        self.assertEqual(k.pidfile.exists(), action == "start")
                        self.assertEqual(len(k.rules()), int(action == "start"))
                        self.assert_no_secrets(result)
        self.assertEqual(len(k.events("dropbearmulti")), 2)
        self.assert_no_usb()

    def test_multicall_dbclient_cannot_be_mistaken_for_server(self):
        k = self.kindle
        for suffix in ([], ["printf", "-P", str(k.pidfile)]):
            with self.subTest(remote_command=suffix):
                pid = 424242 + len(suffix)
                k.process(pid, argv=[str(k.daemon), "dbclient", "user@example.invalid"] + suffix)
                status = k.run(None, "status")
                stop = k.run(None, "stop")
                self.assert_ok(stop)
                self.assertTrue((k.root / f"proc/{pid}/alive").exists(),
                                "stop signaled a dbclient process using the same multicall executable")
                self.assertNotEqual(status.returncode, 0, "dbclient was reported as an SSH server")

    def test_start_rejects_missing_wlan_and_disabled_wifi(self):
        k = self.kindle
        k.wlan.rmdir()
        self.assertNotEqual(k.run(None, "start").returncode, 0)
        k.wlan.mkdir()
        k.configure(USE_WIFI="false")
        self.assertNotEqual(k.run(None, "start").returncode, 0)
        self.assertEqual(k.events("dropbearmulti"), [])
        self.assertEqual(k.rules(), [])

    def test_unconfirmed_pid_has_bounded_wait_and_no_firewall_rule(self):
        k = self.kindle
        k.options(missing_pid=True)
        result = k.run(None, "start")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PID was not confirmed", result.stderr)
        self.assertEqual([event["args"] for event in k.events("sleep")], [["1"]] * 5)
        self.assertEqual(k.rules(), [])
        self.assert_no_secrets(result)

    def test_firewall_failure_stops_the_new_daemon(self):
        k = self.kindle
        k.options(firewall_exit=1)
        self.assertNotEqual(k.run(None, "start").returncode, 0)
        self.assertFalse((k.root / "proc/515151/alive").exists())
        self.assertEqual(k.rules(), [])

    def test_boot_waits_for_userstore_then_wlan_without_an_ip(self):
        k = self.kindle
        k.wlan.rmdir()
        (k.root / "mnt/us").rename(k.root / "hidden-userstore")
        k.options(userstore_after=2, wlan_after=4)
        result = k.run(k.boot)
        self.assert_ok(result)
        self.assertEqual([event["args"] for event in k.events("sleep")], [["2"]] * 4)
        events = k.events()
        start_index = next(i for i, event in enumerate(events) if event["command"] == "dropbearmulti")
        self.assertEqual(sum(event["command"] == "sleep" for event in events[:start_index]), 4)
        self.assertEqual(len(k.events("dropbearmulti")), 1)
        self.assertIn("BOOT_ID=fixture-boot-id", k.log.read_text())
        self.assertIn("BOOT_RESULT=STARTED", k.log.read_text())
        self.assert_no_secrets(result)
        self.assert_no_usb()

    def test_boot_skips_when_auto_absent_or_wifi_only_disabled(self):
        k = self.kindle
        for mode, auto, marker in (("true", False, "DISABLED"), ("false", True, "USB_MODE")):
            with self.subTest(mode=mode, auto=auto):
                k.configure(USE_WIFI_SSHD_ONLY=mode)
                if auto:
                    (k.base / "auto").touch()
                else:
                    (k.base / "auto").unlink()
                self.assert_ok(k.run(k.boot))
                self.assertIn("BOOT_RESULT=" + marker, k.log.read_text())
                self.assertEqual(k.events("dropbearmulti"), [])
                self.assertEqual(k.events("sleep"), [])
                self.assertEqual(k.rules(), [])

    def test_boot_missing_resources_fails_after_bounded_wait(self):
        k = self.kindle
        k.wlan.rmdir()
        result = k.run(k.boot)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["args"] for event in k.events("sleep")], [["2"]] * 60)
        self.assertIn("BOOT_RESULT=RESOURCES_NOT_READY", k.log.read_text())
        self.assertEqual(k.events("dropbearmulti"), [])

    def test_boot_failed_start_and_timeout_log_failure_without_secrets(self):
        k = self.kindle
        for options, expected in (({"daemon_exit": 23}, 1), ({"timeout_exit": 137}, 137)):
            with self.subTest(options=options):
                k.options(**options)
                result = k.run(k.boot)
                self.assertEqual(result.returncode, expected)
                self.assertEqual(k.events("timeout")[-1]["args"][:3], ["-s", "KILL", "30"])
                self.assertIn("BOOT_RESULT=FAILED", k.log.read_text())
                self.assertEqual(k.events("sleep"), [])
                self.assert_no_secrets(result)

    def test_wifi_only_usbnetwork_routes_before_usb_mutations(self):
        k = self.kindle
        write(k.base / "bin/libkh5", "\n".join([
            f"USBNETLITE_BINDIR={shlex.quote(str(k.base / 'bin'))}",
            f"USBNETLITE_IFCONFIG={shlex.quote(str(k.base / 'etc/config'))}",
            'kh_msg() { printf "%s\\n" "$1"; }',
        ]))
        router = k.copy_script("usbnetlite/bin/usbnetwork", k.base / "bin/usbnetwork")
        for action in ("start", "status", "usbms"):
            self.assert_ok(k.run(router, action))
        self.assertEqual(len(k.events("dropbearmulti")), 1)
        self.assertFalse(k.pidfile.exists())
        self.assert_no_usb()

    def test_legacy_upstart_guards_skip_usb_paths(self):
        k = self.kindle
        k.link_stub(k.base / "bin/usbnet-link")
        write(k.base / "bin/usbnetwork", '#!/bin/sh\nexec legacy-usbnetwork "$@"\n', executable=True)
        for job in ("usbnetlite.conf", "usbnetlite-preinit.conf"):
            for section in ("pre-start", "post-stop"):
                with self.subTest(job=job, section=section):
                    script = self.upstart_section(job, section)
                    before = len(k.events())
                    self.assert_ok(k.run(script, source=True))
                    self.assertEqual([event for event in k.events()[before:]
                                      if event["command"] in USB_COMMANDS], [],
                                     "Wi-Fi-only Upstart section reached a legacy USB action")

    def test_upstart_post_stop_tears_down_ssh_after_boot_helper_exits(self):
        k = self.kindle
        k.link_stub(k.base / "bin/usbnet-link")
        write(k.base / "bin/usbnetwork", '#!/bin/sh\nexec legacy-usbnetwork "$@"\n', executable=True)
        self.assert_ok(k.run(k.boot))
        self.assertIn("BOOT_RESULT=STARTED", k.log.read_text())
        self.assert_ok(k.run(None, "status"))
        (k.base / "auto").unlink()  # Teardown must also work after disabling auto.

        preinit = self.upstart_section("usbnetlite-preinit.conf", "post-stop")
        self.assert_ok(k.run(preinit, source=True))
        self.assertTrue((k.root / "proc/515151/alive").exists())
        self.assertEqual(len(k.rules()), 1)

        teardown = self.upstart_section("usbnetlite.conf", "post-stop")
        for _ in range(2):
            self.assert_ok(k.run(teardown, source=True))
            self.assertFalse((k.root / "proc/515151/alive").exists())
            self.assertFalse(k.pidfile.exists())
            self.assertEqual(k.rules(), [])
            self.assertFalse((k.root / "tmp/usbnetlite-sshd.lock").exists())
        signals = [event["args"] for event in k.events("kill") if event["args"][0] != "-0"]
        self.assertEqual(signals, [["-TERM", "515151"]])
        self.assertEqual(len(k.events("dropbearmulti")), 1)
        self.assert_no_usb()

    def test_installer_preserves_custom_config_keys_and_installs_wifi_boot(self):
        k = self.kindle
        stage = k.root / "installer"
        stage.mkdir()
        preserved = {
            "etc/config": (k.base / "etc/config").read_bytes(),
            "etc/dropbear/authorized_keys": b"fixture-public-key-allowlist\n",
            "etc/dropbear/dropbear_rsa_host_key": b"fixture-existing-host-key\n",
        }
        for relative, data in preserved.items():
            path = k.base / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        # A real, small tar stream; xzdec only supplies that stream unchanged.
        defaults = {"etc/config": b"USE_WIFI=false\n", "etc/dropbear/authorized_keys": b""}
        for name in "dropbearmulti usbnet-link usbnetwork libkh5 usbnetwork.sh sftp-server sshd-control".split():
            defaults["bin/" + name] = b"#!/bin/sh\nexit 0\n"
        with tarfile.open(stage / "usbnetlite.tar.xz", "w") as archive:
            for relative, data in defaults.items():
                entry = tarfile.TarInfo("build/mntus_package/usbnetlite/" + relative)
                entry.size, entry.mode = len(data), 0o644
                archive.addfile(entry, io.BytesIO(data))
        write(stage / "xzdec", '#!/bin/sh\ncat "$1"\n', executable=True)
        write(stage / "libotautils5", 'otautils_update_progressbar() { :; }\nlogmsg() { :; }\n')
        root_assets = ("usbnetlite.conf", "usbnetlite-preinit.conf", "usbnetlite-wifi", "usbnetlite-wifi.conf")
        for name in root_assets:
            write(stage / name, (EXTENSION / name).read_text())
        installer = k.copy_script("install.sh", stage / "install.sh")
        result = k.run(installer, source=True, cwd=stage)
        self.assert_ok(result)
        for relative, data in preserved.items():
            self.assertEqual((k.base / relative).read_bytes(), data, relative)
        self.assertEqual((k.base / "etc/config.default").read_bytes(), defaults["etc/config"])
        self.assertTrue(os.access(k.controller, os.X_OK))
        self.assertEqual(k.boot.read_bytes(), (EXTENSION / "usbnetlite-wifi").read_bytes())
        job = k.root / "etc/upstart/usbnetlite-wifi.conf"
        self.assertEqual(job.read_bytes(), (EXTENSION / "usbnetlite-wifi.conf").read_bytes())
        self.assertEqual(k.boot.stat().st_mode & 0o777, 0o755)
        self.assertEqual(job.stat().st_mode & 0o777, 0o644)
        self.assert_no_usb()


if __name__ == "__main__":
    unittest.main()
