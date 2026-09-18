#!/usr/bin/env python3
"""Real packaged engine + Linux termios + stdio + persistence, no Swift SDK needed."""
import errno
import json
import os
import pty
import queue
import select
import subprocess
import sys
import tempfile
import threading
import time

master, slave = pty.openpty()
port = os.ttyname(slave)
os.close(slave)
commands = []
stop = threading.Event()

def emulate():
    pending = b''
    while not stop.is_set():
        try:
            if not select.select([master], [], [], .05)[0]:
                continue
            pending += os.read(master, 4096)
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                commands.append(line.decode().strip())
                if line.strip() == b'H|1':
                    os.write(master, b'Q|1|0.2.2|Q-DESKTOP\n')
                elif line.startswith(b'S|'):
                    os.write(master, b'A|scene\n')
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            time.sleep(.02)

thread = threading.Thread(target=emulate, daemon=True)
thread.start()
process = None
try:
    with tempfile.TemporaryDirectory() as directory:
        settings = os.path.join(directory, 'settings.json')
        snapshots = queue.Queue()
        process = subprocess.Popen([sys.argv[1], 'serve', '--settings', settings, '--port', port], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        def receive():
            for line in process.stdout:
                snapshots.put(json.loads(line))
        threading.Thread(target=receive, daemon=True).start()
        def wait_for(predicate, timeout=12):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                value = snapshots.get(timeout=max(.01, end - time.monotonic()))
                if predicate(value):
                    return value
            raise AssertionError('No matching engine snapshot')
        def send(operation, **values):
            process.stdin.write(json.dumps(dict(operation=operation, **values)) + '\n')
            process.stdin.flush()
        wait_for(lambda x: x['connected'] and x['applied'])
        send('setState', stateID='busy')
        value = wait_for(lambda x: x['stateID'] == 'busy' and x['applied'])
        assert value['leds'][0]['color'] == '#FF1F1F', value
        send('setBrightness', brightness=.42)
        value = wait_for(lambda x: x['brightness'] == .42 and x['applied'])
        assert abs(value['leds'][0]['brightness'] - .42) < .00001
        assert json.load(open(settings))['brightness'] == .42
        os.write(master, b'B|single\n')
        wait_for(lambda x: x['stateID'] == 'available' and x['gesture'] == 'singlePress')
        send('setState', stateID='away')
        wait_for(lambda x: x['stateID'] == 'away')
        send('press')
        wait_for(lambda x: x['stateID'] == 'available')
        send('setBrightness', brightness=-1)
        value = wait_for(lambda x: bool(x['error']))
        assert value['brightness'] == .42
        send('test')
        wait_for(lambda x: x['testing'] and x['testColor'] == 'red' and x['applied'])
        send('cancelTest')
        wait_for(lambda x: not x['testing'] and x['applied'])
        process.stdin.close()
        process.wait(timeout=8)
        assert process.returncode == 0, process.stderr.read()
        scenes = [line for line in commands if line.startswith('S|')]
        assert all(segment.split(',')[4] == '0' for segment in scenes[-1].split('|')[1:])
        assert commands.count('P|1') >= 3
        assert os.path.exists(settings + '.bak')
finally:
    if process and process.poll() is None:
        process.kill(); process.wait()
    stop.set(); thread.join(timeout=2); os.close(master)
print('Desktop engine passed: real serial I/O, state/brightness, button rules, test/restore, persistence, invalid commands and EOF cleanup')
