import SwiftUI
import PencilKit

/// Second screen: the tulip photo *is* the canvas. We ask for the person's name
/// and let them write straight onto the photo, with a vertical rail of pen types
/// and ink colors down the left edge.
struct NameEntryView: View {
    @State private var canvasView = PKCanvasView()
    @State private var tool: ScribbleTool = .marker
    @State private var ink: Color = Self.inks[0]

    private static let inks: [Color] = [
        .matcha,
        .strawberry,
        .white,
        Color(red: 0.10, green: 0.10, blue: 0.12),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("tulip-flower")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // The scribble surface: transparent, sitting directly on the photo.
            DrawingCanvas(canvasView: canvasView, tool: tool, ink: ink)
                .ignoresSafeArea()

            // Keeps the heading legible over the brightest part of the photo.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 320)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Text("Tell us your name.\nScribble it however you'd like.")
                .font(.custom("PlayfairDisplay-SemiBold", size: 24))
                .tracking(0.2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.65), radius: 5, y: 1)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 0)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 28)
                .allowsHitTesting(false)

            toolRail
                .padding(.leading, 16)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var toolRail: some View {
        VStack(spacing: 16) {
            ForEach(ScribbleTool.allCases) { option in
                railButton(symbol: option.symbol, selected: option == tool) {
                    tool = option
                }
            }

            Divider()
                .frame(width: 26)
                .overlay(Color.white.opacity(0.5))

            ForEach(Array(Self.inks.enumerated()), id: \.offset) { _, color in
                Button {
                    ink = color
                    if tool == .eraser { tool = .marker }
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(.white, lineWidth: color == ink ? 3 : 1.5)
                        )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(width: 26)
                .overlay(Color.white.opacity(0.5))

            Button {
                canvasView.drawing = PKDrawing()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private func railButton(
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.white)
                .frame(width: 38, height: 38)
                .background(
                    selected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.18)),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }
}

/// The pen types offered on the rail.
enum ScribbleTool: String, CaseIterable, Identifiable {
    case pencil, pen, marker, eraser

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .pencil: "pencil"
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .eraser: "eraser"
        }
    }

    func pkTool(ink: UIColor) -> PKTool {
        switch self {
        case .pencil: PKInkingTool(.pencil, color: ink, width: 4)
        case .pen: PKInkingTool(.pen, color: ink, width: 6)
        case .marker: PKInkingTool(.marker, color: ink, width: 20)
        case .eraser: PKEraserTool(.bitmap)
        }
    }
}

/// Thin SwiftUI wrapper around `PKCanvasView` so the scribble surface can live
/// inside our layout while we drive its active tool from state.
struct DrawingCanvas: UIViewRepresentable {
    let canvasView: PKCanvasView
    let tool: ScribbleTool
    let ink: Color

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = tool.pkTool(ink: UIColor(ink))
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = tool.pkTool(ink: UIColor(ink))
    }
}

#Preview {
    NameEntryView()
}
