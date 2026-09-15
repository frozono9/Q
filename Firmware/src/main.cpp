#include <Arduino.h>
#include <math.h>
#include <soc/gpio_struct.h>

namespace {

constexpr uint8_t kLedCount = 3;
constexpr uint8_t kChannelCount = 3;
constexpr uint8_t kButtonPin = 8;

// PCB routing, expressed as ESP32-C3 GPIO numbers. Each row is R, G, B.
// The LEDs are common-anode: HIGH is off and LOW is on.
constexpr uint8_t kPins[kLedCount][kChannelCount] = {
    {3, 4, 5},    // LED1: D1, D2, D3
    {6, 7, 21},   // LED2: D4, D5, D6
    {20, 2, 10},  // LED3: D7, D0, D10
};

// Starting point only. These compensate for the green die being much brighter
// than red/blue in the fitted LED. They are intentionally easy to tune after
// seeing the first assembled unit.
constexpr float kChannelCalibration[kChannelCount] = {0.55f, 0.20f, 1.0f};
// A hardware timer advances the 128-level software PWM every 20 us. This keeps
// the refresh at about 391 Hz without timing jitter from USB or rendering work.
constexpr uint8_t kPwmLevels = 128;
constexpr uint32_t kPwmStepMicros = 20;
constexpr uint32_t kRenderIntervalMs = 16;
constexpr uint32_t kDebounceMs = 25;
constexpr uint32_t kDoublePressMs = 260;
constexpr uint32_t kLongPressMs = 650;
constexpr uint32_t kConnectedPulsePeriodMs = 700;
constexpr uint8_t kConnectedPulseCount = 3;
// A missed heartbeat starts an invisible challenge/response grace period. Q
// keeps showing the active scene while it asks the app to prove it is alive,
// and only shows its red waiting state after the entire grace period expires.
constexpr uint32_t kAppHeartbeatTimeoutMs = 8000;
constexpr uint32_t kAppChallengeIntervalMs = 2000;
constexpr uint32_t kAppChallengeGraceMs = 30000;
constexpr char kFirmwareVersion[] = "0.2.1";

enum Animation : uint8_t {
  Solid = 0,
  Blink = 1,
  Pulse = 2,
  Flash = 3,
  FlashThenSolid = 4,
  FadeInOut = 5,
  ChaseUp = 6,
  ChaseDown = 7,
  Bounce = 8,
  Progress = 9,
  Alternating = 10,
  GradientShift = 11,
  Rainbow = 12,
};

struct LedState {
  uint8_t red = 0;
  uint8_t green = 0;
  uint8_t blue = 0;
  uint8_t brightness = 0;
  bool enabled = false;
  uint8_t animation = Solid;
  float speed = 1.0f;
  float phaseOffset = 0.0f;
};

LedState states[kLedCount];
volatile uint8_t rendered[kLedCount][kChannelCount] = {};
portMUX_TYPE pwmMux = portMUX_INITIALIZER_UNLOCKED;
hw_timer_t *pwmTimer = nullptr;
uint32_t sceneStartedAt = 0;

enum ConnectionState : uint8_t {
  AwaitingApp = 0,
  ConfirmingApp = 1,
  AppConnected = 2,
};

ConnectionState connectionState = AwaitingApp;
uint32_t connectionStateStartedAt = 0;
uint32_t lastAppContactAt = 0;
bool awaitingHeartbeatResponse = false;
uint32_t heartbeatChallengeStartedAt = 0;
uint32_t lastHeartbeatChallengeAt = 0;

char serialLine[256];
size_t serialLength = 0;

bool rawButtonDown = false;
bool stableButtonDown = false;
bool longPressSent = false;
bool shortPressPending = false;
uint32_t rawButtonChangedAt = 0;
uint32_t pressStartedAt = 0;
uint32_t shortPressReleasedAt = 0;

float clamp01(float value) {
  return fminf(1.0f, fmaxf(0.0f, value));
}

float fraction(float value) {
  return value - floorf(value);
}

float animationIntensity(const LedState &state, uint8_t ledIndex, uint32_t now) {
  if (!state.enabled || state.brightness == 0) return 0.0f;

  const float elapsed = static_cast<float>(now - sceneStartedAt) / 1000.0f;
  const float phase = elapsed * state.speed + state.phaseOffset;
  const float cycle = fraction(phase);

  switch (state.animation) {
    case Solid:
      return 1.0f;
    case Blink:
      return cycle < 0.5f ? 1.0f : 0.0f;
    case Pulse:
      return 0.18f + 0.82f * ((sinf(phase * TWO_PI - HALF_PI) + 1.0f) / 2.0f);
    case Flash:
      return cycle < 0.13f ? 1.0f : 0.04f;
    case FlashThenSolid:
      if (elapsed >= 1.4f) return 1.0f;
      return (static_cast<int>(floorf(elapsed * 7.0f)) % 2 == 0) ? 1.0f : 0.05f;
    case FadeInOut:
      return (sinf(phase * TWO_PI - HALF_PI) + 1.0f) / 2.0f;
    case ChaseUp: {
      const uint8_t active = static_cast<uint8_t>(floorf(phase * kLedCount)) % kLedCount;
      return active == ledIndex ? 1.0f : 0.08f;
    }
    case ChaseDown: {
      const uint8_t active = (kLedCount - 1) -
          (static_cast<uint8_t>(floorf(phase * kLedCount)) % kLedCount);
      return active == ledIndex ? 1.0f : 0.08f;
    }
    case Bounce: {
      constexpr uint8_t path[] = {0, 1, 2, 1};
      const uint8_t active = path[static_cast<uint8_t>(floorf(phase * 4.0f)) % 4];
      return active == ledIndex ? 1.0f : 0.08f;
    }
    case Progress: {
      const float progress = (sinf(phase * TWO_PI - HALF_PI) + 1.0f) / 2.0f;
      const float threshold = static_cast<float>(ledIndex + 1) / kLedCount;
      return progress + 0.01f >= threshold ? 1.0f : 0.08f;
    }
    case Alternating: {
      const uint8_t group = static_cast<uint8_t>(floorf(phase * 2.0f)) % 2;
      return ledIndex % 2 == group ? 1.0f : 0.08f;
    }
    case GradientShift:
    case Rainbow:
      return 1.0f;
    default:
      return 1.0f;
  }
}

void hsvToRgb(float hue, float saturation, float value, float &red, float &green, float &blue) {
  const float h = fraction(hue) * 6.0f;
  const int sector = static_cast<int>(floorf(h));
  const float f = h - sector;
  const float p = value * (1.0f - saturation);
  const float q = value * (1.0f - saturation * f);
  const float t = value * (1.0f - saturation * (1.0f - f));

  switch (sector % 6) {
    case 0: red = value; green = t; blue = p; break;
    case 1: red = q; green = value; blue = p; break;
    case 2: red = p; green = value; blue = t; break;
    case 3: red = p; green = q; blue = value; break;
    case 4: red = t; green = p; blue = value; break;
    default: red = value; green = p; blue = q; break;
  }
}

uint8_t correctedLevel(float component, float brightness, float intensity, uint8_t channel) {
  const float linear = clamp01(component * brightness * intensity);
  const float gammaCorrected = powf(linear, 2.2f);
  return static_cast<uint8_t>(roundf(
      kPwmLevels * gammaCorrected * kChannelCalibration[channel]));
}

void updateRenderedLevels(uint32_t now);

void renderConnectionStatus(uint32_t now) {
  float red = 0.0f;
  float green = 0.0f;
  float intensity = 0.0f;

  if (connectionState == AwaitingApp) {
    const float elapsed = static_cast<float>(now - connectionStateStartedAt) / 1000.0f;
    const float wave = (sinf(elapsed * TWO_PI / 1.35f - HALF_PI) + 1.0f) / 2.0f;
    red = 1.0f;
    intensity = 0.12f + 0.88f * wave;
  } else {
    const uint32_t elapsed = now - connectionStateStartedAt;
    const uint32_t totalDuration = kConnectedPulsePeriodMs * kConnectedPulseCount;
    if (elapsed >= totalDuration) {
      connectionState = AppConnected;
      sceneStartedAt = now;
      updateRenderedLevels(now);
      return;
    }

    const float cycle = static_cast<float>(elapsed % kConnectedPulsePeriodMs) /
        static_cast<float>(kConnectedPulsePeriodMs);
    const float envelope = sinf(cycle * PI);
    green = 1.0f;
    intensity = envelope * envelope;
  }

  const uint8_t redLevel = correctedLevel(red, 1.0f, intensity, 0);
  const uint8_t greenLevel = correctedLevel(green, 1.0f, intensity, 1);
  portENTER_CRITICAL(&pwmMux);
  for (uint8_t led = 0; led < kLedCount; ++led) {
    rendered[led][0] = redLevel;
    rendered[led][1] = greenLevel;
    rendered[led][2] = 0;
  }
  portEXIT_CRITICAL(&pwmMux);
}

void updateRenderedLevels(uint32_t now) {
  if (connectionState != AppConnected) {
    renderConnectionStatus(now);
    return;
  }

  uint8_t nextRendered[kLedCount][kChannelCount] = {};
  const float elapsed = static_cast<float>(now - sceneStartedAt) / 1000.0f;
  for (uint8_t led = 0; led < kLedCount; ++led) {
    const LedState &state = states[led];
    float red = state.red / 255.0f;
    float green = state.green / 255.0f;
    float blue = state.blue / 255.0f;
    const float phase = elapsed * state.speed + state.phaseOffset;

    if (state.animation == Rainbow) {
      hsvToRgb(fraction(phase), 0.78f, 1.0f, red, green, blue);
    } else if (state.animation == GradientShift) {
      const float wave = (sinf(phase * TWO_PI) + 1.0f) / 2.0f;
      red = clamp01(red + wave * 0.2f);
      green = clamp01(green + (1.0f - wave) * 0.16f);
      blue = clamp01(blue + wave * 0.12f);
    }

    const float intensity = animationIntensity(state, led, now);
    const float brightness = state.brightness / 255.0f;
    nextRendered[led][0] = correctedLevel(red, brightness, intensity, 0);
    nextRendered[led][1] = correctedLevel(green, brightness, intensity, 1);
    nextRendered[led][2] = correctedLevel(blue, brightness, intensity, 2);
  }

  portENTER_CRITICAL(&pwmMux);
  memcpy((void *)rendered, nextRendered, sizeof(rendered));
  portEXIT_CRITICAL(&pwmMux);
}

void ARDUINO_ISR_ATTR serviceSoftwarePwm() {
  static uint8_t phase = 0;
  uint32_t turnOnMask = 0;
  uint32_t turnOffMask = 0;

  for (uint8_t led = 0; led < kLedCount; ++led) {
    for (uint8_t channel = 0; channel < kChannelCount; ++channel) {
      const uint32_t pinMask = 1UL << kPins[led][channel];
      if (rendered[led][channel] > phase) {
        turnOnMask |= pinMask;
      } else {
        turnOffMask |= pinMask;
      }
    }
  }

  // Common-anode inversion: clearing an output turns that channel on. Direct
  // register writes update all nine channels together and avoid digitalWrite
  // latency inside the timer interrupt.
  GPIO.out_w1tc.val = turnOnMask;
  GPIO.out_w1ts.val = turnOffMask;
  phase = (phase + 1) & (kPwmLevels - 1);
}

bool parseLed(char *text, LedState &state) {
  int red, green, blue, brightness, enabled, animation, speedMilli, phaseMilli;
  if (sscanf(text, "%d,%d,%d,%d,%d,%d,%d,%d", &red, &green, &blue,
             &brightness, &enabled, &animation, &speedMilli, &phaseMilli) != 8) {
    return false;
  }
  state.red = constrain(red, 0, 255);
  state.green = constrain(green, 0, 255);
  state.blue = constrain(blue, 0, 255);
  state.brightness = constrain(brightness, 0, 255);
  state.enabled = enabled != 0;
  state.animation = constrain(animation, 0, 12);
  state.speed = fmaxf(0.05f, speedMilli / 1000.0f);
  state.phaseOffset = phaseMilli / 1000.0f;
  return true;
}

void sendDeviceInfo() {
  const uint64_t chipID = ESP.getEfuseMac();
  Serial.printf(
      "Q|1|%s|Q-%04X%08X\n",
      kFirmwareVersion,
      static_cast<uint16_t>(chipID >> 32),
      static_cast<uint32_t>(chipID));
}

void noteAppContact(uint32_t now) {
  lastAppContactAt = now;
  awaitingHeartbeatResponse = false;
}

void processSerialLine(char *line) {
  char *save = nullptr;
  char *command = strtok_r(line, "|", &save);
  if (!command) return;

  if (strcmp(command, "H") == 0) {
    sendDeviceInfo();
    connectionState = ConfirmingApp;
    connectionStateStartedAt = millis();
    noteAppContact(connectionStateStartedAt);
    return;
  }
  if (strcmp(command, "P") == 0) {
    noteAppContact(millis());
    if (connectionState == AwaitingApp) {
      // A late heartbeat means the existing app session was delayed, not newly
      // connected. Restore its scene silently; only a fresh H handshake earns
      // the three-pulse green connection confirmation.
      connectionState = AppConnected;
      sceneStartedAt = lastAppContactAt;
    }
    return;
  }
  if (strcmp(command, "S") != 0) return;

  LedState pending[kLedCount];
  for (uint8_t led = 0; led < kLedCount; ++led) {
    char *segment = strtok_r(nullptr, "|", &save);
    if (!segment || !parseLed(segment, pending[led])) {
      Serial.println("E|scene");
      return;
    }
  }
  memcpy(states, pending, sizeof(states));
  sceneStartedAt = millis();
  noteAppContact(sceneStartedAt);
  Serial.println("A|scene");
}

void serviceSerial() {
  while (Serial.available() > 0) {
    const char incoming = static_cast<char>(Serial.read());
    if (incoming == '\n') {
      serialLine[serialLength] = '\0';
      processSerialLine(serialLine);
      serialLength = 0;
    } else if (incoming != '\r') {
      if (serialLength < sizeof(serialLine) - 1) {
        serialLine[serialLength++] = incoming;
      } else {
        serialLength = 0;
        Serial.println("E|length");
      }
    }
  }
}

void emitButton(const char *event) {
  Serial.print("B|");
  Serial.println(event);
}

void serviceButton(uint32_t now) {
  const bool down = digitalRead(kButtonPin) == LOW;
  if (down != rawButtonDown) {
    rawButtonDown = down;
    rawButtonChangedAt = now;
  }

  if (rawButtonDown != stableButtonDown &&
      static_cast<uint32_t>(now - rawButtonChangedAt) >= kDebounceMs) {
    stableButtonDown = rawButtonDown;
    if (stableButtonDown) {
      pressStartedAt = now;
      longPressSent = false;
    } else if (!longPressSent) {
      if (shortPressPending &&
          static_cast<uint32_t>(now - shortPressReleasedAt) <= kDoublePressMs) {
        shortPressPending = false;
        emitButton("double");
      } else {
        shortPressPending = true;
        shortPressReleasedAt = now;
      }
    }
  }

  if (stableButtonDown && !longPressSent &&
      static_cast<uint32_t>(now - pressStartedAt) >= kLongPressMs) {
    longPressSent = true;
    shortPressPending = false;
    emitButton("long");
  }

  if (shortPressPending && !stableButtonDown &&
      static_cast<uint32_t>(now - shortPressReleasedAt) > kDoublePressMs) {
    shortPressPending = false;
    emitButton("single");
  }
}

void serviceAppConnection(uint32_t now) {
  if (connectionState == AwaitingApp) return;

  if (!awaitingHeartbeatResponse) {
    if (static_cast<uint32_t>(now - lastAppContactAt) <= kAppHeartbeatTimeoutMs) return;

    awaitingHeartbeatResponse = true;
    heartbeatChallengeStartedAt = now;
    lastHeartbeatChallengeAt = now;
    Serial.println("C|heartbeat");
    return;
  }

  if (static_cast<uint32_t>(now - heartbeatChallengeStartedAt) <= kAppChallengeGraceMs) {
    if (static_cast<uint32_t>(now - lastHeartbeatChallengeAt) >= kAppChallengeIntervalMs) {
      lastHeartbeatChallengeAt = now;
      Serial.println("C|heartbeat");
    }
    return;
  }

  connectionState = AwaitingApp;
  connectionStateStartedAt = now;
  awaitingHeartbeatResponse = false;
}

}  // namespace

void setup() {
  // Put every common-anode channel in its safe off state immediately.
  for (uint8_t led = 0; led < kLedCount; ++led) {
    for (uint8_t channel = 0; channel < kChannelCount; ++channel) {
      digitalWrite(kPins[led][channel], HIGH);
      pinMode(kPins[led][channel], OUTPUT);
    }
  }
  pinMode(kButtonPin, INPUT_PULLUP);

  pwmTimer = timerBegin(0, 80, true);  // 80 MHz / 80 = one tick per microsecond.
  timerAttachInterrupt(pwmTimer, &serviceSoftwarePwm, true);
  timerAlarmWrite(pwmTimer, kPwmStepMicros, true);
  timerAlarmEnable(pwmTimer);

  Serial.begin(115200);
  sceneStartedAt = millis();
  connectionStateStartedAt = sceneStartedAt;
  sendDeviceInfo();
}

void loop() {
  const uint32_t now = millis();
  static uint32_t previousRenderAt = 0;
  if (static_cast<uint32_t>(now - previousRenderAt) >= kRenderIntervalMs) {
    previousRenderAt = now;
    updateRenderedLevels(now);
  }

  serviceSerial();
  serviceAppConnection(now);
  serviceButton(now);
}
