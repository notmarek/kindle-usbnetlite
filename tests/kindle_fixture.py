"""Small fake Kindle for executing the shipped shell scripts without privileges.

Only fixture copies are rewritten: Kindle paths, PATH, and the shell's kill
builtin (redirected to a fake command). No production test hooks are needed.
The command journal contains synthetic test arguments, never real credentials.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parents[1]
EXTENSION = REPO / "extension"
PASSWORD = "fixture only: 'double\" $HOME `id` ; * end"
# Whitespace makes loss of argument quoting observable (synthetic config only).
WINDOW_SIZE = "6291456 "
DAEMON_DIAGNOSTIC = "synthetic-password-hash-must-not-be-logged"
USB_COMMANDS = {
    "ifconfig", "ip", "dhclient", "udhcpc", "lipc-set-prop", "lipc-send-event",
    "lipc-get-prop", "mntroot", "mount", "umount", "modprobe", "rmmod",
    "insmod", "lsmod", "kdb", "start-stop-daemon", "killall", "usbnet-link",
    "legacy-usbnetwork", "wall",
}


def write(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if executable:
        path.chmod(0o755)
    return path


def fake_process(root, pid, executable, argv):
    proc = root / "proc" / str(pid)
    proc.mkdir(parents=True, exist_ok=True)
    (proc / "alive").touch()
    (proc / "exe").unlink(missing_ok=True)
    (proc / "exe").symlink_to(executable)
    (proc / "cmdline").write_bytes(b"\0".join(os.fsencode(a) for a in argv) + b"\0")


class KindleFixture:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix="usbnetlite-test-")
        # macOS aliases /var to /private/var; proc/exe comparisons need one form.
        self.root = Path(self.temp.name).resolve()
        self.bin = self.root / "commands"
        self.bin.mkdir()
        self.base = self.root / "mnt/us/usbnetlite"
        self.controller = self.base / "bin/sshd-control"
        self.daemon = self.base / "bin/dropbearmulti"
        self.pidfile = self.base / "run/sshd.pid"
        self.wlan = self.root / "sys/class/net/wlan0"
        self.log = self.root / "var/local/usbnetlite/wifi-boot.log"
        for directory in ("tmp", "usr/bin", "usr/sbin", "usr/local/bin", "etc/upstart"):
            (self.root / directory).mkdir(parents=True)
        write(self.root / "proc/sys/kernel/random/boot_id", "fixture-boot-id\n")
        # PATH has no fallback to arbitrary host commands. These utilities only
        # operate on rewritten fixture paths; device/network commands are stubs.
        for command in "cat mkdir rm rmdir tr awk grep chmod cp ln tar date".split():
            target = shutil.which(command)
            if target is None:
                raise RuntimeError(f"Required local utility missing: {command}")
            (self.bin / command).symlink_to(target)
        self.stub = write(
            self.bin / "_stub",
            f"#!{sys.executable}\n" + Path(__file__).read_text(),
            executable=True,
        )
        for command in USB_COMMANDS | {"id", "kill", "readlink", "sleep", "timeout", "iptables", "sed", "md5sum"}:
            self.link_stub(self.bin / command)
        self.link_stub(self.root / "sbin/start-stop-daemon")
        self.copy_script("usbnetlite/bin/sshd-control", self.controller)
        self.boot = self.copy_script("usbnetlite-wifi", self.root / "usr/local/bin/usbnetlite-wifi")
        shutil.copyfile(self.stub, self.daemon)
        self.daemon.chmod(0o755)
        self.configure()
        (self.base / "auto").touch()
        self.wlan.mkdir(parents=True)
        self.env = {
            "PATH": str(self.bin), "HOME": str(self.root), "LC_ALL": "C",
            "KINDLE_FIXTURE": str(self.root), "PYTHONDONTWRITEBYTECODE": "1",
        }

    def close(self):
        self.temp.cleanup()

    def link_stub(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to(self.stub)

    def rewrite(self, source):
        # Match literal absolute roots, not suffixes such as $BASE/etc/config.
        source = re.sub(
            r"(?<![\w}/])/(?:mnt|sys|proc|tmp|var|usr|etc|sbin)(?=/)",
            lambda match: str(self.root) + match.group(), source,
        )
        source = re.sub(r"^PATH=.*$", "PATH=" + shlex.quote(str(self.bin)), source, flags=re.M)
        # kill is a shell builtin, so PATH alone cannot safely intercept it.
        return re.sub(r"(?<![\w/-])kill(?=\s+-)", str(self.bin / "kill"), source)

    def copy_script(self, relative, destination):
        return write(destination, self.rewrite((EXTENSION / relative).read_text()), executable=True)

    def configure(self, **overrides):
        config = dict(
            USE_WIFI="true", USE_WIFI_SSHD_ONLY="true", PORT="2222",
            ALLOW_PASSWORD_LOGIN="true", PASSWORD_OVERRIDE_ENABLED="true",
            PASSWORD=PASSWORD, WINDOW_SIZE=WINDOW_SIZE,
        )
        config.update(overrides)
        write(self.base / "etc/config", "".join(f"{key}={shlex.quote(value)}\n" for key, value in config.items()))

    def options(self, **options):
        write(self.root / "options.json", json.dumps(options))

    def events(self, command=None):
        path = self.root / "calls.jsonl"
        events = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [event for event in events if command is None or event["command"] == command]

    def rules(self):
        path = self.root / "rules.json"
        return json.loads(path.read_text()) if path.exists() else []

    def process(self, pid=424242, executable=None, argv=None):
        executable = str(executable or self.daemon)
        argv = argv or [executable, "dropbear", "-P", str(self.pidfile)]
        fake_process(self.root, pid, executable, argv)
        write(self.pidfile, str(pid) + "\n")
        return pid

    def run(self, script=None, *args, source=False, cwd=None, stdout_mode="capture"):
        script = script or self.controller
        # Bash supports the legacy Kindle ash 'source' and '==' extensions.
        command = (["/bin/bash", "-c", '. "$1"', "fixture", str(script)] if source
                   else ["/bin/sh", str(script)])
        command += list(args)
        stdout = subprocess.PIPE
        pipe_writer = None
        if stdout_mode == "closed":
            command = ["/bin/sh", "-c", 'exec 1>&-; exec "$@"', "closed-stdout"] + command
        elif stdout_mode == "broken_pipe":
            reader, pipe_writer = os.pipe()
            os.close(reader)  # No reader exists before the child starts writing.
            stdout = pipe_writer
        elif stdout_mode != "capture":
            raise ValueError(f"Unknown stdout mode: {stdout_mode}")
        try:
            result = subprocess.run(command, cwd=cwd or self.root, env=self.env,
                                    stdout=stdout, stderr=subprocess.PIPE, text=True, timeout=15)
            result.stdout = result.stdout or ""
            return result
        finally:
            if pipe_writer is not None:
                os.close(pipe_writer)


def stub_main():
    root = Path(os.environ["KINDLE_FIXTURE"])
    command, args = Path(sys.argv[0]).name, sys.argv[1:]
    with (root / "calls.jsonl").open("a") as journal:
        journal.write(json.dumps({"command": command, "args": args}) + "\n")
    options_path = root / "options.json"
    options = json.loads(options_path.read_text()) if options_path.exists() else {}
    if command == "id":
        print("0")
    elif command == "kill":
        alive = root / "proc" / args[-1] / "alive"
        if not alive.exists():
            return 1
        if args[0] != "-0":
            alive.unlink()
    elif command == "readlink":
        path = Path(args[-1])
        print(path.resolve() if "-f" in args else os.readlink(path))
    elif command == "dropbearmulti":
        print(PASSWORD)
        print(DAEMON_DIAGNOSTIC, file=sys.stderr)
        if options.get("daemon_exit"):
            return options["daemon_exit"]
        if not options.get("missing_pid"):
            pidfile = Path(args[args.index("-P") + 1])
            fake_process(root, 515151, sys.argv[0], [sys.argv[0]] + args)
            write(pidfile, "515151\n")
    elif command == "iptables":
        path = root / "rules.json"
        rules = json.loads(path.read_text()) if path.exists() else []
        action = args[0]
        rule = args[1:]
        if action == "-I":
            rule = [args[1]] + args[3:]
        if action == "-C":
            return 2 if options.get("old_iptables") else int(rule not in rules)
        if action == "-S":
            for entry in rules:
                print("-A " + " ".join(entry).replace("-p tcp", "-p tcp -m tcp"))
        elif action in ("-I", "-A"):
            if options.get("firewall_exit"):
                return options["firewall_exit"]
            rules.append(rule)
        elif action == "-D":
            if rule not in rules:
                return 1
            rules.remove(rule)
        write(path, json.dumps(rules))
    elif command == "sleep":
        path = root / "sleep-count"
        count = int(path.read_text()) + 1 if path.exists() else 1
        write(path, str(count))
        if count == options.get("userstore_after"):
            (root / "hidden-userstore").rename(root / "mnt/us")
        if count == options.get("wlan_after"):
            (root / "sys/class/net/wlan0").mkdir(parents=True)
    elif command == "timeout":
        if options.get("timeout_exit"):
            return options["timeout_exit"]
        if args[:3] != ["-s", "KILL", "30"]:
            return 98
        return subprocess.run(args[3:], timeout=10).returncode
    elif command == "sed":
        # The legacy router only uses sed to normalize its config's CRLF.
        if "-i" not in args:
            return 98
        path = Path(args[-1])
        path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n"))
    elif command == "md5sum":
        print(hashlib.md5(Path(args[0]).read_bytes()).hexdigest(), args[0])
    else:
        # Every USB, network, mount, or legacy daemon command is a tripwire.
        print(f"Forbidden fixture command: {command}", file=sys.stderr)
        return 97
    return 0


if __name__ == "__main__":
    sys.exit(stub_main())
