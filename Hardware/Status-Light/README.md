# Q — Status Light PCB

Exported from Alex’s existing **Status Light** project in EasyEDA Pro 3.2.149 on 8 October 2026. The cloud design was not modified. Board: PCB1 / Board1, two layers, estimated outline 24 × 57 mm (EasyEDA export dialog).

See [BUILD.md](BUILD.md) for fabrication, assembly and first-power checks.

## Files

- `Original-Exports/Gerber_PCB1_2026-10-08.zip`: untouched Gerber, paste-mask and drill exports. Upload this ZIP as the PCB artwork.
- `Original-Exports/ProPrj_Status Light_2026-10-08.epro2`: editable EasyEDA Pro V3 project, including schematic, PCB, symbols, footprints and panel document. Open/import it with EasyEDA Pro V3.
- `Original-Exports/SCH_Schematic1_2026-10-08.pdf` and `SCH_Schematic1_1-P1_2026-10-08.svg`: schematic for reading or embedding in the tutorial.
- `Original-Exports/3D_PCB1_2026-10-08.step`: exported board model. EasyEDA generates fallback geometry for components without a bound STEP model; this is not a dimensionally verified enclosure-fit reference.
- `Original-Exports/Netlist_PCB1_2026-10-08.tel`: Allegro netlist used to inspect connectivity. EasyEDA warned that footprint names contain characters Allegro does not support; do not assume a clean Allegro import.
- `BOM-readable.csv` and `CPL-readable.csv`: full exports converted to ordinary UTF-8 comma-separated CSV. Originals use UTF-16 and tabs despite their .csv extension.
- `BOM-JLCPCB-top-SMD.csv` and `CPL-JLCPCB-top-SMD.csv`: derived matching set for the 13 top-side SMD parts, using millimetres. Coordinates and rotations are preserved from EasyEDA. **U1 is excluded** because the source marks it bottom-side and non-SMD; fit the XIAO separately. The full BOM includes U1.
- `SHA256.json`: checksums of this package’s files.

## Component inventory

| Reference | Quantity | Part | LCSC code |
|---|---:|---|---|
| LED1–LED3 | 3 | TUOZHAN P4-1615G2B2R4TS2-06T-001-24 | C7496855 |
| R1–R9 | 9 | 330 Ω, 0603, Viking CR-03JL7--330R | C279996 |
| SW2 | 1 | SHOU HAN TS3320A | C2681475 |
| U1 | 1 | XIAO ESP32C3 | C19189385 |

## Connectivity cross-check

The PCB netlist routes LED pins 2 / 3 / 4 through individual resistors to these XIAO pins. These match the firmware’s declared R / G / B routing; this check does not independently certify the LED library’s colour-to-pad assignment.

| LED | XIAO pin sequence | Firmware GPIO sequence |
|---|---|---|
| LED1 | D1 / D2 / D3 | 3 / 4 / 5 |
| LED2 | D4 / D5 / D6 | 6 / 7 / 21 |
| LED3 | D7 / D0 / D10 | 20 / 2 / 10 |

All three LED pin 1 anodes connect to U1 pin 12 (3V3). SW2 pins 1+2 connect to U1 pin 9 (D8 / GPIO8); pins 3+4 connect to U1 pin 13 (GND). Firmware enables an internal pull-up.

## Review notes

The project’s introduction metadata says “XIAO ESP32-S3 — Rev A”. The actual U1 device, footprint, BOM and current firmware specify **ESP32-C3**. Preserve the original source, but use ESP32-C3 in the tutorial.

Checked: archive integrity, presence of copper/outline/drill layers, four BOM groups totalling 14 parts, 14 placement records, and matching 13-part reference sets in the derived assembly files. The original CPL puts U1 on the bottom and the other 13 parts on top.

EasyEDA’s PCB DRC completed on 8 October 2026 with **All (0)** under the project’s existing rules; see [the saved result](DRC-2026-10-08.jpg). The rule coverage has not been audited. A fresh schematic ERC, fabrication preview, component polarity/rotation review, supplier stock check and physical build test have not been performed for this export. Review those before ordering; this package records the existing design rather than certifying a new fabrication run. No order has been placed.
