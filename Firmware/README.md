# Q firmware

This is the firmware for the production Q PCB with a Seeed Studio XIAO
ESP32-C3, three TUOZHAN common-anode RGB LEDs, and one active-low button.

## Flash

Install PlatformIO, connect the XIAO over USB-C, then run:

```sh
cd Firmware
pio run --target upload
pio device monitor
```

The macOS app discovers the resulting `/dev/cu.*` USB serial port automatically,
sends its current three-LED scene, and receives single-, double-, and long-press
events. No Wi-Fi, pairing, API key, or manual port selection is required.

The app sends a heartbeat once per second from a dedicated serial queue. After
eight seconds without app traffic, firmware keeps the current scene visible and
sends heartbeat challenges every two seconds. Q only returns to its red waiting
pulse if the app remains silent for the full 30-second challenge window. A live
app responds immediately, while a genuinely restarted app performs a new
handshake and triggers the three green pulses.

The handshake response includes protocol version, firmware version, and a
stable device identifier, for example `Q|1|0.2.1|Q-E8F60A143570`.

## Hardware mapping

| LED | Red | Green | Blue |
| --- | --- | --- | --- |
| LED1 | GPIO3 / D1 | GPIO4 / D2 | GPIO5 / D3 |
| LED2 | GPIO6 / D4 | GPIO7 / D5 | GPIO21 / D6 |
| LED3 | GPIO20 / D7 | GPIO2 / D0 | GPIO10 / D10 |

The button is GPIO8 / D8 with the XIAO's internal pull-up enabled. LED outputs
are active-low because pin 1 of every RGB package is a common 3.3 V anode. That
electrical detail is isolated inside `serviceSoftwarePwm()`; all app and protocol
values retain normal brightness semantics.

The ESP32-C3 exposes six hardware LEDC channels, fewer than Q's nine color
channels. The firmware therefore uses a hardware-timer-driven, roughly 390 Hz
software PWM engine. The timer keeps LED timing stable while animation, USB
parsing, and button handling continue independently in the main loop.

`kChannelCalibration` contains conservative first-unit color correction. Once an
assembled Q is available, those three values can be tuned visually without any
PCB change.
