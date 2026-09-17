#!/usr/bin/env python3
"""Exercise the actual Linux serial adapter and CLI against a pseudo-terminal."""
import errno
import json
import os
import pty
import select
import subprocess
import sys
import threading
import time


class Device:
    def __init__(self):
        self.master, slave = pty.openpty()
        self.path = os.ttyname(slave)
        os.close(slave)
        self.stop = threading.Event()
        self.hello = threading.Event()
        self.commands = []
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        pending = b""
        buttons_sent = False
        while not self.stop.is_set():
            try:
                if not select.select([self.master], [], [], 0.05)[0]:
                    continue
                pending += os.read(self.master, 4096)
                while b"\n" in pending:
                    raw, pending = pending.split(b"\n", 1)
                    line = raw.decode().strip()
                    self.commands.append(line)
                    if line == "H|1":
                        self.hello.set()
                        os.write(self.master, b"ESP-ROM:test\r\nQ|1|0.2.")
                        time.sleep(0.02)
                        os.write(self.master, b"2|Q-PTY\r\n")
                    elif line.startswith("S|"):
                        os.write(self.master, b"A|scene\r\n")
                    elif line == "P|1" and not buttons_sent:
                        buttons_sent = True
                        os.write(self.master, b"C|heartbeat\nB|single\nB|double\nB|triple\nB|long\nB|long-release\n")
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                time.sleep(0.02)  # Slave has not opened yet, or was closed.

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)
        os.close(self.master)


def run(*args):
    device = Device()
    try:
        result = subprocess.run([sys.argv[1], *args, "--port", device.path], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, (args, result.stdout, result.stderr)
        return result, device.commands
    finally:
        device.close()


status, _ = run("status")
assert json.loads(status.stdout)["id"] == "Q-PTY"
watch, commands = run("watch", "--seconds", "1.2")
assert {json.loads(line)["gesture"] for line in watch.stdout.splitlines()} == {
    "singlePress", "doublePress", "triplePress", "longPress", "longPressEnded"
}
assert commands.count("P|1") >= 3  # initial heartbeat, challenge, periodic
_, commands = run("lights", "traffic", "--seconds", "0.3")
scenes = [line for line in commands if line.startswith("S|")]
assert len(scenes) == 2, scenes  # requested scene, then acknowledged off
assert all(segment.split(",")[4] == "0" for segment in scenes[-1].split("|")[1:])

device = Device()
first = subprocess.Popen([sys.argv[1], "watch", "--seconds", "3", "--port", device.path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    assert device.hello.wait(timeout=5)
    second = subprocess.run([sys.argv[1], "status", "--port", device.path], capture_output=True, text=True, timeout=5)
    assert second.returncode != 0, "A second process acquired the busy port"
    first.communicate(timeout=10)
    assert first.returncode == 0
finally:
    if first.poll() is None:
        first.kill()
        first.communicate()
    device.close()

print("Linux PTY integration passed: fragmented handshake, all gestures, heartbeat, scenes, cleanup and exclusive access")
