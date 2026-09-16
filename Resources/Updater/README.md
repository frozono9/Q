# Q updater payload

- `Q-Firmware-0.2.3.bin` is the complete ESP32-C3 flash image built from
  `Firmware/` (bootloader, partition table and Q application). SHA-256:
  `9e72835a33bfeb65a4c2f27bbf533635905d6987da7a769cad7249f5d711388f`.
- `espflash` is a universal macOS binary made from the official espflash 4.5.0
  arm64 and x86_64 release assets. The downloaded archives were verified
  against GitHub's published SHA-256 digests before combining them with
  `lipo`. Universal binary SHA-256:
  `eb68537a6557bd6d74d008cb6889bf082475a4dbaa53bff5abc296e71192136f`.

The app only invokes the updater for the serial port which has completed Q's
protocol handshake. It reconnects after flashing and verifies firmware 0.2.3
before reporting success.
