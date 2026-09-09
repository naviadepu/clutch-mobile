import SwiftUI
import PencilKit

/// Second screen: the soft pink backdrop *is* the canvas. We ask for the
/// person's name and let them write straight onto it, with a vertical rail
/// of pen types and ink colors down the left edge.
struct NameEntryView: View {
    @State private var canvasView = PKCanvasView()
    @State private var tool: ScribbleTool = .marker
    @State private var ink: Color = Self.inks[0]
    @State private var goToAge = false

    private static let inks: [Color] = [
        .matcha,
        .strawberry,
        .white,
        Color(red: 0.10, green: 0.10, blue: 0.12),
    ]

    var body: some View {
        // A plain Color base (rather than overlaying directly on the scaled
        // image) keeps this view's *reported* layout size sane — `scaledToFill`
        // on a portrait photo computes an oversized intrinsic frame to cover a
        // taller screen, and chaining `.overlay` straight onto it throws off
        // the alignment math for the tool rail below (it lands off-screen).
        Color.clear
            .background {
                Image("pink-bg")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                VStack(spacing: 4) {
                    // TODO: swap to the PF Pixelscript font once the licensed
                    // file is added to Resources/Fonts and registered in
                    // Info.plist.
                    Text("Your name")
                        .font(.custom("PinyonScript-Regular", size: 44))
                        .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.12))

                    Text("scribble as you want")
                        .font(.custom("PlayfairDisplay-SemiBold", size: 15))
                        .tracking(0.3)
                        .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.55))
                }
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .allowsHitTesting(false)
            }
            .overlay {
                // The scribble surface: transparent, sitting directly on the backdrop.
                DrawingCanvas(canvasView: canvasView, tool: tool, ink: ink)
            }
            .overlay(alignment: .leading) {
                toolRail
                    .padding(.leading, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    goToAge = true
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(red: 0.10, green: 0.10, blue: 0.12), in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .padding(24)
            }
            .navigationDestination(isPresented: $goToAge) {
                AgeEntryView()
                    .toolbar(.hidden, for: .navigationBar)
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
                .overlay(Color.black.opacity(0.15))

            ForEach(Array(Self.inks.enumerated()), id: \.offset) { _, color in
                Button {
                    ink = color
                    if tool == .eraser { tool = .marker }
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(.black.opacity(0.3), lineWidth: color == ink ? 3 : 1.5)
                        )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(width: 26)
                .overlay(Color.black.opacity(0.15))

            Button {
                canvasView.drawing = PKDrawing()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.black.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private func railButton(
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color(red: 0.10, green: 0.10, blue: 0.12))
                .frame(width: 38, height: 38)
                .background(
                    selected ? AnyShapeStyle(Color(red: 0.10, green: 0.10, blue: 0.12)) : AnyShapeStyle(.black.opacity(0.08)),
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
