import QCore
import SwiftUI

struct VirtualQView: View {
    @ObservedObject var device: VirtualQDevice

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: 38, height: 4)
                .padding(.top, 16)

            VStack(spacing: 25) {
                ForEach(Array(device.currentScene.leds.enumerated()), id: \.offset) { index, led in
                    VirtualLEDView(
                        state: led,
                        index: index,
                        ledCount: QScene.ledCount,
                        sceneAppliedAt: device.sceneAppliedAt
                    )
                }

                VirtualButtonView(device: device)
                    .padding(.top, 5)

                Text("Q")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.5))
                    .shadow(color: .white.opacity(0.07), radius: 0, x: 0, y: 1)
                    .padding(.top, -3)
            }
            .padding(.top, 23)
            .padding(.bottom, 28)
        }
        .frame(width: 224, height: 604)
        .background {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.20, blue: 0.22),
                            Color(red: 0.075, green: 0.08, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5), radius: 28, y: 16)
        }
        .padding(30)
        .animation(.easeInOut(duration: 0.28), value: device.currentScene)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Virtual Q device")
    }
}

private struct VirtualLEDView: View {
    let state: QLEDState
    let index: Int
    let ledCount: Int
    let sceneAppliedAt: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let intensity = animationIntensity(at: timeline.date)
            let lightColor = renderedColor(at: timeline.date)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, Color(white: 0.82)],
                            center: .topLeading,
                            startRadius: 3,
                            endRadius: 56
                        )
                    )
                    .overlay {
                        Circle().stroke(.black.opacity(0.22), lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 5)

                if state.isEnabled && intensity > 0.001 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    lightColor,
                                    lightColor.opacity(0.82)
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .opacity(intensity * state.brightness)
                        .shadow(
                            color: lightColor.opacity(intensity * state.brightness * 0.95),
                            radius: 20
                        )
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.27), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(5)
            }
            .frame(width: 108, height: 108)
            .accessibilityLabel("LED \(index + 1)")
            .accessibilityValue(state.isEnabled ? "On, \(state.color.hex)" : "Off")
        }
    }

    private func animationIntensity(at date: Date) -> Double {
        guard state.isEnabled else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate * state.animationSpeed
            + (state.phaseOffset ?? 0)
        let fraction = phase - floor(phase)

        switch state.animation {
        case .solid:
            return 1
        case .blink:
            return fraction < 0.5 ? 1 : 0
        case .pulse:
            return 0.18 + 0.82 * ((sin(phase * 2 * .pi - .pi / 2) + 1) / 2)
        case .flash:
            return fraction < 0.13 ? 1 : 0.04
        case .flashThenSolid:
            let elapsed = date.timeIntervalSince(sceneAppliedAt)
            guard elapsed < 1.4 else { return 1 }
            return Int(floor(elapsed * 7)) % 2 == 0 ? 1 : 0.05
        case .fadeInOut:
            return (sin(phase * 2 * .pi - .pi / 2) + 1) / 2
        case .chaseUp:
            return chaseIntensity(activeIndex: Int(floor(phase * Double(ledCount))) % ledCount)
        case .chaseDown:
            let active = (ledCount - 1) - (Int(floor(phase * Double(ledCount))) % ledCount)
            return chaseIntensity(activeIndex: active)
        case .bounce:
            let path = Array(0..<ledCount) + Array((1..<(ledCount - 1)).reversed())
            let active = path[Int(floor(phase * Double(path.count))) % path.count]
            return chaseIntensity(activeIndex: active)
        case .progress:
            let progress = (sin(phase * 2 * .pi - .pi / 2) + 1) / 2
            let threshold = Double(index + 1) / Double(ledCount)
            return progress + 0.01 >= threshold ? 1 : 0.08
        case .alternating:
            let group = Int(floor(phase * 2)) % 2
            return index % 2 == group ? 1 : 0.08
        case .gradientShift, .rainbow:
            return 1
        }
    }

    private func renderedColor(at date: Date) -> Color {
        let phase = date.timeIntervalSinceReferenceDate * state.animationSpeed
            + (state.phaseOffset ?? 0)
        let fraction = phase - floor(phase)

        switch state.animation {
        case .rainbow:
            return Color(hue: fraction, saturation: 0.78, brightness: 1)
        case .gradientShift:
            let wave = (sin(phase * 2 * .pi) + 1) / 2
            return Color(
                red: min(1, state.color.red + wave * 0.2),
                green: min(1, state.color.green + (1 - wave) * 0.16),
                blue: min(1, state.color.blue + wave * 0.12)
            )
        default:
            return Color(state.color)
        }
    }

    private func chaseIntensity(activeIndex: Int) -> Double {
        activeIndex == index ? 1 : 0.08
    }
}

private struct VirtualButtonView: View {
    @ObservedObject var device: VirtualQDevice

    @State private var isPressed = false
    @State private var pressStartedAt: Date?
    @State private var pendingSinglePress: Task<Void, Never>?

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: isPressed
                        ? [Color(white: 0.07), Color(white: 0.15)]
                        : [Color(white: 0.24), Color(white: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Circle().stroke(.white.opacity(isPressed ? 0.06 : 0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.8), radius: isPressed ? 2 : 7, y: isPressed ? 1 : 5)
            .frame(width: 68, height: 68)
            .scaleEffect(isPressed ? 0.96 : 1)
            .contentShape(Circle())
            .gesture(pressGesture)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .onDisappear {
                pendingSinglePress?.cancel()
            }
            .accessibilityLabel("Q button")
            .accessibilityHint("Click, double-click, or press and hold")
            .accessibilityAddTraits(.isButton)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStartedAt == nil else { return }
                pressStartedAt = .now
                isPressed = true
            }
            .onEnded { _ in
                let duration = Date.now.timeIntervalSince(pressStartedAt ?? .now)
                pressStartedAt = nil
                isPressed = false

                if duration >= 0.65 {
                    pendingSinglePress?.cancel()
                    pendingSinglePress = nil
                    device.sendButtonEvent(.longPress)
                } else {
                    registerShortPress()
                }
            }
    }

    private func registerShortPress() {
        if pendingSinglePress != nil {
            pendingSinglePress?.cancel()
            pendingSinglePress = nil
            device.sendButtonEvent(.doublePress)
            return
        }

        pendingSinglePress = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            device.sendButtonEvent(.singlePress)
            pendingSinglePress = nil
        }
    }
}

extension Color {
    init(_ color: QColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}
