# Build the Q Status Light PCB

This guide covers the exported 24 × 57 mm, two-layer Status Light carrier for
**Seeed Studio XIAO ESP32-C3**. The editable source is preserved in
[Original-Exports](Original-Exports). The source introduction’s ESP32-S3 wording is
outdated; the actual device, footprint and firmware are ESP32-C3.

## 1. Choose how to assemble it

For a bare board, use
[Gerber_PCB1_2026-10-08.zip](Original-Exports/Gerber_PCB1_2026-10-08.zip), then obtain
the parts in [BOM-readable.csv](BOM-readable.csv). The RGB LEDs are small SMD
packages, so assembly service is an option if you do not have suitable soldering
equipment.

For top-side assembly service, use these three files together:

| Purpose | File |
|---|---|
| PCB copper, masks, outline and drills | [Original Gerber ZIP](Original-Exports/Gerber_PCB1_2026-10-08.zip) |
| 13 top-side SMD parts | [BOM-JLCPCB-top-SMD.csv](BOM-JLCPCB-top-SMD.csv) |
| Positions in mm, side and rotation | [CPL-JLCPCB-top-SMD.csv](CPL-JLCPCB-top-SMD.csv) |

The assembly BOM includes LED1–LED3, R1–R9 and SW2. It excludes U1 deliberately:
the EasyEDA source places the XIAO on the bottom and marks it non-SMD. Obtain one
XIAO ESP32-C3 separately and fit it after the carrier’s SMD assembly. Do not mix
these top-side files with the full placement export when requesting that service.

## 2. Review the fabrication preview

Confirm the outline is 24 × 57 mm and there are two copper layers. Check that the
holes and cutouts, solder-mask openings and silk labels appear correctly.
Board thickness, finish and manufacturing tolerances for the existing enclosure
have not been recovered from the original order; confirm them against the real
unit before ordering another batch. Do not interpret a supplier’s defaults as
the original print or fabrication settings.

In the assembly preview, inspect all three LED polarities and rotations against
the schematic and the exact manufacturer package drawing. Inspect the switch
orientation and the resistor positions. The CSV rotations are original EasyEDA
values; no assembly-house rotation correction has been assumed.

The fresh PCB DRC reported zero incidences under the saved project rules. This
does not replace the manufacturer’s preview or the polarity review.

## 3. Inspect and mount the XIAO

Inspect the carrier for solder bridges, missing parts and damaged pads before
mounting U1. The three LEDs and switch face the front; U1 sits on the opposite
side. Match U1’s 3V3, GND and D0–D10 pads with the schematic and PCB markings.
Use the original unit to confirm the mounting height and connector orientation;
the enclosure fastening and spacer details are not yet documented here.

Solder the XIAO using the mounting arrangement used by the real build. With the
board disconnected from USB, check for unintended shorts between 3V3 and GND and
between neighbouring solder joints. Correct bridges before applying power.

## 4. Flash and check the electronics before closing the case

Connect a USB-C **data** cable and follow [the firmware upload instructions](../../Firmware/README.md).
Install/build the [macOS app](../../README.md#install-q) and run its first-run setup.

Check the three LEDs individually with red, green and blue scenes. Confirm that
the top, middle and bottom LEDs correspond to LED1, LED2 and LED3. Check single,
double and held button actions using the contextual action shown by the app.
If channels are swapped, inspect the LED package and routing before changing
firmware pin assignments. If the button reads pressed continuously, inspect SW2
and the D8-to-ground path.

## 5. Fit the enclosure

Only close the case after the LED and button checks pass. Verify that the
three diffusers line up, the button moves freely, and the USB connector remains
accessible without stressing U1. Recheck the button after closing the case.

The eight printable enclosure files, print settings, fastening details and a
real assembly photo/video sequence still need to be integrated into this repo.
The STEP export is useful for viewing the board, but automatically generated
component bodies have not been checked for enclosure fit.

## Verify the download

From the repository root, run `python3 Scripts/verify-hardware.py` to check the
hardware manifest, archives, component counts, matching assembly designators and
PCB netlist against the firmware pin declarations. This is a file consistency
check, not a physical electrical test.
