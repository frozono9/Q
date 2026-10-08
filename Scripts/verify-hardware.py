#!/usr/bin/env python3
"""Check the frozen Status Light package and its firmware routing (stdlib only)."""
import csv
import hashlib
import json
from pathlib import Path
import re
import zipfile

REPO = Path(__file__).resolve().parents[1]
HW = REPO / 'Hardware/Status-Light'
RAW = HW / 'Original-Exports'


def require(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)


def read_csv(name):
    with (HW / name).open(encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


manifest = json.loads((HW / 'SHA256.json').read_text())
actual_files = {str(p.relative_to(HW)) for p in HW.rglob('*')
                if p.is_file() and p.name != 'SHA256.json'}
require(actual_files == set(manifest), 'manifest must cover every hardware file')
for name, expected in manifest.items():
    require(hashlib.sha256((HW / name).read_bytes()).hexdigest() == expected,
            'checksum mismatch: ' + name)
for path in RAW.iterdir():
    if path.suffix in ('.zip', '.epro2'):
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None, 'damaged archive: ' + path.name)
with zipfile.ZipFile(RAW / 'Gerber_PCB1_2026-10-08.zip') as archive:
    require({'Gerber_TopLayer.GTL', 'Gerber_BottomLayer.GBL',
             'Gerber_BoardOutlineLayer.GKO', 'Drill_PTH_Through.DRL',
             'Drill_NPTH_Through.DRL'} <= set(archive.namelist()),
            'missing fabrication layers')
bom = read_csv('BOM-readable.csv')
cpl = read_csv('CPL-readable.csv')
assembly_bom = read_csv('BOM-JLCPCB-top-SMD.csv')
assembly_cpl = read_csv('CPL-JLCPCB-top-SMD.csv')
require(sum(int(r['Quantity']) for r in bom) == 14, 'expected 14 total parts')
require(len(cpl) == 14, 'expected 14 placement records')
require({r['Designator'] for r in cpl if r['Layer'] == 'B'} == {'U1'},
        'expected only U1 on the bottom')
expected_smd = {r['Designator'] for r in cpl if r['SMD'] == 'Yes'}
require(len(expected_smd) == 13, 'expected 13 SMD parts')
require({x for r in assembly_bom for x in r['Designator'].split(',')}
        == {r['Designator'] for r in assembly_cpl} == expected_smd,
        'assembly BOM and CPL references must match original SMD references')
require(len(assembly_cpl) == 13, 'duplicate or missing assembly placement')
original = {r['Designator']: r for r in cpl}
for row in assembly_cpl:
    ref = original[row['Designator']]
    require(row['Layer'] == 'top', 'assembly must be top-side only')
    for key in ('Mid X', 'Mid Y', 'Rotation'):
        require(float(row[key]) == float(ref[key].removesuffix('mm')),
                row['Designator'] + ': changed coordinate/rotation ' + key)

netlist = (RAW / 'Netlist_PCB1_2026-10-08.tel').read_text()
nets = [set(line.split(';', 1)[1].split()) for line in netlist.splitlines()
        if line.startswith("'") and ';' in line]

def connected(*pins):
    return any(set(pins) <= net for net in nets)

# Physical XIAO ESP32-C3 pad numbers -> GPIOs, as used by its D0-D10 pins.
gpios = {1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 21, 8: 20, 9: 8, 11: 10}
routing = []
for led in range(1, 4):
    channels = []
    require(connected(f'LED{led}.1', 'U1.12'), 'LED anode must connect to 3V3')
    for pad in (2, 3, 4):
        led_net = next(n for n in nets if f'LED{led}.{pad}' in n)
        resistor_pad = next(p for p in led_net if re.fullmatch(r'R\d+\.[12]', p))
        resistor, endpoint = resistor_pad.split('.')
        other = resistor + '.' + ('2' if endpoint == '1' else '1')
        mcu_net = next(n for n in nets if other in n)
        mcu_pad = next(p for p in mcu_net if p.startswith('U1.'))
        channels.append(gpios[int(mcu_pad.split('.')[1])])
    routing.append(channels)
firmware = (REPO / 'Firmware/src/main.cpp').read_text()
block = re.search(r'kPins\[kLedCount\]\[kChannelCount\]\s*=\s*\{(.*?)\n\};',
                  firmware, re.S)
require(block is not None, 'cannot locate firmware routing table')
fw_routing = [[int(v) for v in match] for match in
              re.findall(r'\{\s*(\d+),\s*(\d+),\s*(\d+)\s*\}', block.group(1))]
require(routing == fw_routing, 'PCB routing differs from firmware')
button = re.search(r'kButtonPin\s*=\s*(\d+)', firmware)
require(button is not None and int(button.group(1)) == gpios[9]
        and connected('SW2.1', 'SW2.2', 'U1.9')
        and connected('SW2.3', 'SW2.4', 'U1.13'), 'button routing mismatch')
print('PASS: checksums, archives, fabrication layers, 14 parts, 13 matching SMD placements, LED/button firmware routing')
