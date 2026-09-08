import SwiftUI

struct QBrandMark: View {
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2.2

    var body: some View {
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
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
