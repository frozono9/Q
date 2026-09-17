import AppKit
import SwiftUI

@MainActor
enum QBrandAssets {
    static let logo = image(named: "QLogo", extension: "png")
    static let menuBarImage = image(named: "QMenuBarTemplate", extension: "png")
    static let appIcon = image(named: "AppIcon", extension: "icns")

    private static func image(named name: String, extension fileExtension: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct QBrandMark: View {
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2.2

    var body: some View {
        Group {
            if let logo = QBrandAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackMark: some View {
        Canvas { context, canvasSize in
            let inset = lineWidth / 2 + 1
            let ringSize = min(canvasSize.width, canvasSize.height) * 0.74
            let ringRect = CGRect(x: inset, y: inset, width: ringSize, height: ringSize)

            var ring = Path()
            ring.addEllipse(in: ringRect)
            context.stroke(
                ring,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            var tail = Path()
            tail.move(to: CGPoint(x: canvasSize.width * 0.58, y: canvasSize.height * 0.58))
            tail.addLine(to: CGPoint(x: canvasSize.width - inset, y: canvasSize.height - inset))
            context.stroke(
                tail,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
