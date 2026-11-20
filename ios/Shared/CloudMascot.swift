import SwiftUI

// The Clutch cloud: a plush little cloud with paws and a pup, who has come
// down from the sky to live in a cozy home. Drawn entirely in code so it
// looks the same in the app and the widget. Shared by both.

enum CloudPalette {
    static let strawberry = Color(red: 0.976, green: 0.820, blue: 0.851)
    static let matcha = Color(red: 0.514, green: 0.561, blue: 0.345)
    static let ink = Color(red: 0.23, green: 0.18, blue: 0.16)
    static let blush = Color(red: 0.96, green: 0.62, blue: 0.70)
    static let fluff = Color(red: 1.0, green: 0.995, blue: 1.0)
    static let fluffShade = Color(red: 0.84, green: 0.81, blue: 0.95)
    static let eye = Color(red: 0.16, green: 0.14, blue: 0.30)
    static let pup = Color(red: 0.72, green: 0.55, blue: 0.40)

    static let wall = [Color(red: 0.99, green: 0.93, blue: 0.93), Color(red: 0.97, green: 0.87, blue: 0.89)]
    static let nightWall = [Color(red: 0.42, green: 0.38, blue: 0.56), Color(red: 0.33, green: 0.30, blue: 0.47)]
    static let floor = Color(red: 0.88, green: 0.76, blue: 0.70)
    static let sofa = [Color(red: 0.66, green: 0.71, blue: 0.50), Color(red: 0.51, green: 0.56, blue: 0.35)]
    static let wood = [Color(red: 0.86, green: 0.70, blue: 0.58), Color(red: 0.74, green: 0.57, blue: 0.45)]

    static func sky(_ sky: MascotScene.Sky) -> [Color] {
        switch sky {
        case .dawn: [Color(red: 1.0, green: 0.88, blue: 0.80), strawberry]
        case .day: [Color(red: 0.78, green: 0.88, blue: 0.98), Color(red: 0.96, green: 0.90, blue: 0.96)]
        case .dusk: [Color(red: 0.90, green: 0.66, blue: 0.76), Color(red: 1.0, green: 0.82, blue: 0.70)]
        case .night: [Color(red: 0.17, green: 0.17, blue: 0.33), Color(red: 0.36, green: 0.31, blue: 0.50)]
        }
    }
}

// MARK: - The cloud

/// The cloud on its own, any size: plush body, glossy eyes, blush, and
/// (optionally) two paws resting in front.
struct FuzzyCloud: View {
    enum Face { case happy, sleepy, soft, focused }

    var face: Face = .happy
    /// Greyer on drizzly days.
    var gloomy = false
    var paws = true

    var body: some View {
        Canvas { context, size in
            // A margin so the outermost fur isn't clipped by the canvas.
            let m = size.width * CloudPaws.margin
            context.translateBy(x: m, y: m)
            let w = size.width - 2 * m, h = size.height - 2 * m
            let light = gloomy ? Color(red: 0.86, green: 0.87, blue: 0.92) : CloudPalette.fluff
            let shade = gloomy ? Color(red: 0.66, green: 0.68, blue: 0.78) : CloudPalette.fluffShade

            let puffs: [CGRect] = [
                CGRect(x: w * 0.03, y: h * 0.30, width: w * 0.42, height: h * 0.50),
                CGRect(x: w * 0.20, y: h * 0.02, width: w * 0.60, height: h * 0.72),
                CGRect(x: w * 0.55, y: h * 0.26, width: w * 0.42, height: h * 0.52),
                // A lumpy bottom, so it's puffy all the way round.
                CGRect(x: w * 0.06, y: h * 0.50, width: w * 0.36, height: h * 0.40),
                CGRect(x: w * 0.30, y: h * 0.52, width: w * 0.40, height: h * 0.42),
                CGRect(x: w * 0.58, y: h * 0.50, width: w * 0.36, height: h * 0.40),
            ]
            let base = CGRect(x: w * 0.12, y: h * 0.40, width: w * 0.76, height: h * 0.40)
            var body = Path(roundedRect: base, cornerRadius: h * 0.2)
            for puff in puffs { body.addEllipse(in: puff) }

            // Ground shadow and a soft glow: the fuzz you see around plush.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: w * 0.04))
                layer.fill(Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.86, width: w * 0.76, height: h * 0.14)), with: .color(.black.opacity(0.18)))
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: w * 0.025))
                layer.fill(body, with: .color(shade.opacity(0.55)))
            }

            // The body, lit from the top left.
            context.fill(body, with: .linearGradient(
                Gradient(colors: [light, light, shade]),
                startPoint: CGPoint(x: w * 0.3, y: 0), endPoint: CGPoint(x: w * 0.6, y: h)))

            // Each puff gets its own highlight, so it reads as round.
            for puff in puffs {
                let center = CGPoint(x: puff.minX + puff.width * 0.38, y: puff.minY + puff.height * 0.32)
                context.fill(Path(ellipseIn: puff.insetBy(dx: puff.width * 0.05, dy: puff.height * 0.05)), with: .radialGradient(
                    Gradient(colors: [light, light.opacity(0)]), center: center, startRadius: 0, endRadius: puff.width * 0.5))
            }

            // Fur: soft tufts all round the outline.
            var seed: UInt64 = 11
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 1000) / 1000
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: max(0.4, w * 0.004)))
                let tuft = max(1.4, w * 0.026)
                for puff in puffs {
                    for i in 0..<44 {
                        let angle = Double(i) / 44 * 2 * .pi + Double(rand()) * 0.15
                        let x = puff.midX + cos(angle) * puff.width / 2 * (0.97 + rand() * 0.05)
                        let y = puff.midY + sin(angle) * puff.height / 2 * (0.97 + rand() * 0.05)
                        let r = tuft * (0.6 + rand() * 0.7)
                        // Fur picks up the body's shading from top to bottom.
                        let t = min(1, max(0, (y / h - 0.5) / 0.45))
                        layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                   with: .color(t > 0.5 ? shade.opacity(0.75) : light))
                    }
                }
            }

            // Ambient shade along the bottom.
            context.drawLayer { layer in
                layer.clip(to: body)
                layer.addFilter(.blur(radius: w * 0.05))
                layer.fill(Path(ellipseIn: CGRect(x: w * 0.1, y: h * 0.82, width: w * 0.8, height: h * 0.3)), with: .color(shade.opacity(0.5)))
            }

            drawFace(in: &context, w: w, h: h)
            if paws { CloudPaws.draw(in: &context, w: w, h: h, light: light, shade: shade) }
        }
        .aspectRatio(1.3, contentMode: .fit)
    }

    private func drawFace(in context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let eyeY = h * 0.45
        let eyeW = w * 0.075, eyeH = h * 0.12

        for x in [w * 0.39, w * 0.61] {
            switch face {
            case .sleepy:
                var lid = Path()
                lid.move(to: CGPoint(x: x - eyeW * 0.6, y: eyeY))
                lid.addQuadCurve(to: CGPoint(x: x + eyeW * 0.6, y: eyeY), control: CGPoint(x: x, y: eyeY + eyeH * 0.55))
                context.stroke(lid, with: .color(CloudPalette.eye), style: StrokeStyle(lineWidth: max(1, w * 0.016), lineCap: .round))
            default:
                let squint: CGFloat = face == .soft ? 0.82 : face == .focused ? 0.88 : 1
                let rect = CGRect(x: x - eyeW / 2, y: eyeY - eyeH / 2 * squint, width: eyeW, height: eyeH * squint)
                context.fill(Path(ellipseIn: rect), with: .linearGradient(
                    Gradient(colors: [CloudPalette.eye, Color(red: 0.42, green: 0.32, blue: 0.62)]),
                    startPoint: CGPoint(x: x, y: rect.minY + rect.height * 0.4), endPoint: CGPoint(x: x, y: rect.maxY)))
                // Two catchlights: the glossy look.
                let big = eyeW * 0.42, small = eyeW * 0.2
                context.fill(Path(ellipseIn: CGRect(x: x + eyeW * 0.02, y: rect.minY + rect.height * 0.12, width: big, height: big)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: x - eyeW * 0.32, y: rect.maxY - rect.height * 0.36, width: small, height: small)), with: .color(.white.opacity(0.85)))
            }
        }

        // Blush, soft-edged.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: w * 0.02))
            for x in [w * 0.29, w * 0.71] {
                layer.fill(Path(ellipseIn: CGRect(x: x - w * 0.055, y: h * 0.52, width: w * 0.11, height: h * 0.07)), with: .color(CloudPalette.blush.opacity(0.75)))
            }
        }

        var mouth = Path()
        let y = h * 0.55
        switch face {
        case .happy:
            mouth.move(to: CGPoint(x: w * 0.465, y: y))
            mouth.addQuadCurve(to: CGPoint(x: w * 0.5, y: y + h * 0.008), control: CGPoint(x: w * 0.48, y: y + h * 0.04))
            mouth.addQuadCurve(to: CGPoint(x: w * 0.535, y: y), control: CGPoint(x: w * 0.52, y: y + h * 0.04))
        case .soft:
            mouth.move(to: CGPoint(x: w * 0.475, y: y + h * 0.01))
            mouth.addQuadCurve(to: CGPoint(x: w * 0.525, y: y + h * 0.01), control: CGPoint(x: w * 0.5, y: y + h * 0.035))
        case .focused:
            mouth.move(to: CGPoint(x: w * 0.48, y: y + h * 0.015))
            mouth.addQuadCurve(to: CGPoint(x: w * 0.52, y: y + h * 0.015), control: CGPoint(x: w * 0.5, y: y + h * 0.025))
        case .sleepy:
            let r = w * 0.012
            mouth.addEllipse(in: CGRect(x: w * 0.5 - r, y: y, width: r * 2, height: r * 2.4))
        }
        context.stroke(mouth, with: .color(CloudPalette.eye), style: StrokeStyle(lineWidth: max(1, w * 0.013), lineCap: .round, lineJoin: .round))
    }
}

/// Two plush paws. Drawn inside the cloud, or on their own on top of a
/// blanket so the cloud looks tucked in.
struct CloudPaws: View {
    var gloomy = false

    var body: some View {
        Canvas { context, size in
            let light = gloomy ? Color(red: 0.86, green: 0.87, blue: 0.92) : CloudPalette.fluff
            let shade = gloomy ? Color(red: 0.66, green: 0.68, blue: 0.78) : CloudPalette.fluffShade
            // Same coordinates as inside the cloud, so a paws view the same
            // size as the cloud lines up exactly.
            let m = size.width * Self.margin
            context.translateBy(x: m, y: m)
            Self.draw(in: &context, w: size.width - 2 * m, h: size.height - 2 * m, light: light, shade: shade)
        }
        .aspectRatio(1.3, contentMode: .fit)
    }

    /// Inset shared with `FuzzyCloud`, as a share of the width.
    static let margin: CGFloat = 0.045

    static func draw(in context: inout GraphicsContext, w: CGFloat, h: CGFloat, light: Color, shade: Color) {
        for x in [w * 0.33, w * 0.67] {
            let rect = CGRect(x: x - w * 0.11, y: h * 0.66, width: w * 0.22, height: h * 0.19)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: w * 0.012))
                layer.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: h * 0.02)), with: .color(shade))
            }
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [light, light, shade]),
                center: CGPoint(x: rect.midX - rect.width * 0.1, y: rect.minY + rect.height * 0.3),
                startRadius: 0, endRadius: rect.width * 0.62))
            // Toe lines.
            for dx in [-0.16, 0.16] {
                var toe = Path()
                toe.move(to: CGPoint(x: rect.midX + rect.width * dx, y: rect.maxY - rect.height * 0.05))
                toe.addLine(to: CGPoint(x: rect.midX + rect.width * dx, y: rect.maxY - rect.height * 0.28))
                context.stroke(toe, with: .color(shade), style: StrokeStyle(lineWidth: max(0.8, w * 0.008), lineCap: .round))
            }
        }
    }
}

// MARK: - Furniture

private struct Sofa: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let fill = LinearGradient(colors: CloudPalette.sofa, startPoint: .top, endPoint: .bottom)
            ZStack {
                // Back.
                RoundedRectangle(cornerRadius: h * 0.22).fill(fill)
                    .frame(width: w * 0.86, height: h * 0.62).position(x: w / 2, y: h * 0.31)
                // Legs.
                ForEach([0.16, 0.84], id: \.self) { x in
                    Capsule().fill(CloudPalette.wood[1]).frame(width: w * 0.035, height: h * 0.12).position(x: w * x, y: h * 0.95)
                }
            }
        }
    }
}

/// The front of the sofa: seat and arms, drawn over the cloud's bottom.
private struct SofaFront: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let fill = LinearGradient(colors: CloudPalette.sofa, startPoint: .top, endPoint: .bottom)
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.12).fill(fill)
                    .frame(width: w * 0.86, height: h * 0.32).position(x: w / 2, y: h * 0.74)
                Capsule().fill(.white.opacity(0.18)).frame(width: w * 0.7, height: h * 0.04).position(x: w / 2, y: h * 0.62)
                ForEach([0.07, 0.93], id: \.self) { x in
                    RoundedRectangle(cornerRadius: w * 0.07).fill(fill)
                        .frame(width: w * 0.15, height: h * 0.55).position(x: w * x, y: h * 0.64)
                }
            }
        }
    }
}

private struct Bed: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.12)
                    .fill(LinearGradient(colors: CloudPalette.wood, startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.92, height: h * 0.7).position(x: w / 2, y: h * 0.4)
                // Pillow.
                Capsule().fill(.white.opacity(0.92)).frame(width: w * 0.5, height: h * 0.2).position(x: w / 2, y: h * 0.45)
            }
        }
    }
}

/// A fluffy duvet with a scalloped top edge, like the cloud's own fur.
private struct Duvet: View {
    var color: Color = CloudPalette.strawberry

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var top = Path(CGRect(x: 0, y: h * 0.2, width: w, height: h * 0.8))
            let bumps = 9
            for i in 0...bumps {
                let x = w * CGFloat(i) / CGFloat(bumps)
                top.addEllipse(in: CGRect(x: x - w * 0.07, y: h * 0.04, width: w * 0.14, height: h * 0.34))
            }
            context.fill(top, with: .linearGradient(Gradient(colors: [color.opacity(0.98), color.opacity(0.98), Color(red: 0.80, green: 0.72, blue: 0.88)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // Knit ribs.
            for i in 1..<12 {
                var rib = Path()
                let x = w * CGFloat(i) / 12
                rib.move(to: CGPoint(x: x, y: h * 0.35))
                rib.addLine(to: CGPoint(x: x, y: h))
                context.stroke(rib, with: .color(.white.opacity(0.28)), lineWidth: max(0.8, w * 0.006))
            }
        }
    }
}

private struct Counter: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                Rectangle().fill(LinearGradient(colors: CloudPalette.wood, startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.85).offset(y: h * 0.15)
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.97, green: 0.95, blue: 0.92))
                    .frame(width: w * 1.02, height: h * 0.17)
                ForEach([0.25, 0.75], id: \.self) { x in
                    Capsule().fill(.black.opacity(0.15)).frame(width: w * 0.12, height: max(1.5, h * 0.04))
                        .position(x: w * x, y: h * 0.45)
                }
            }
        }
    }
}

private struct Window: View {
    let sky: MascotScene.Sky
    var raining = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: CloudPalette.sky(sky), startPoint: .top, endPoint: .bottom)
                switch sky {
                case .night:
                    Image(systemName: "moon.fill").font(.system(size: w * 0.22)).foregroundStyle(.yellow.opacity(0.85))
                        .position(x: w * 0.72, y: h * 0.28)
                    ForEach([(0.2, 0.2), (0.35, 0.6), (0.6, 0.75), (0.85, 0.55)], id: \.0) { p in
                        Circle().fill(.white.opacity(0.85)).frame(width: 2, height: 2).position(x: w * p.0, y: h * p.1)
                    }
                case .dawn:
                    Circle().fill(Color.orange.opacity(0.55)).frame(width: w * 0.32).position(x: w * 0.3, y: h * 0.8)
                case .day where !raining:
                    Circle().fill(Color.yellow.opacity(0.7)).frame(width: w * 0.22).position(x: w * 0.72, y: h * 0.28)
                default:
                    EmptyView()
                }
                if raining {
                    ForEach(0..<9, id: \.self) { i in
                        Capsule().fill(Color(red: 0.55, green: 0.65, blue: 0.85).opacity(0.8))
                            .frame(width: 1.4, height: h * 0.12)
                            .rotationEffect(.degrees(12))
                            .position(x: w * (0.1 + CGFloat(i % 5) * 0.2), y: h * (0.2 + CGFloat(i / 5) * 0.4 + CGFloat(i % 2) * 0.12))
                    }
                }
                // Frame and cross bars.
                Rectangle().fill(.white).frame(width: max(2, w * 0.05)).frame(maxHeight: .infinity)
                Rectangle().fill(.white).frame(height: max(2, w * 0.05)).frame(maxWidth: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: w * 0.12, style: .continuous).strokeBorder(.white, lineWidth: max(2.5, w * 0.06)))
        }
    }
}

/// A little hot water bottle in a knit cover.
private struct HotWaterBottle: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: w * 0.12).fill(CloudPalette.blush)
                    .frame(width: w * 0.32, height: h * 0.22)
                RoundedRectangle(cornerRadius: w * 0.3).fill(CloudPalette.blush)
                    .overlay(
                        VStack(spacing: h * 0.08) {
                            ForEach(0..<3, id: \.self) { _ in Capsule().fill(.white.opacity(0.5)).frame(height: max(1, h * 0.04)) }
                        }
                        .padding(.horizontal, w * 0.18)
                    )
                    .padding(.top, h * 0.16)
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
    }
}

// MARK: - Scenes

/// One whole scene: the cloud at home (or out on the hill), with the pup
/// and whatever it's up to.
struct MascotSceneView: View {
    let scene: MascotScene
    var hasFlower = false
    var sparkle = false

    private enum Place { case sofa, bed, kitchen, outside }

    private var place: Place {
        switch scene {
        case .walk, .picnic, .fetch: .outside
        case .breakfast, .dinner: .kitchen
        case .sleep, .hotWaterNap: .bed
        case .study, .journal, .packing, .cozyTea, .cuddle, .drizzle: .sofa
        }
    }

    private var face: FuzzyCloud.Face {
        switch scene {
        case .sleep, .hotWaterNap: .sleepy
        case .study, .journal: .focused
        case .drizzle, .cozyTea, .cuddle: .soft
        default: .happy
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                switch place {
                case .outside: outside(size)
                case .sofa: sofa(size)
                case .bed: bed(size)
                case .kitchen: kitchen(size)
                }
                if sparkle {
                    ForEach([(0.16, 0.2, 0.11), (0.3, 0.1, 0.06), (0.66, 0.4, 0.07)], id: \.0) { p in
                        Image(systemName: "sparkle")
                            .font(.system(size: min(size.width, size.height) * p.2, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.45))
                            .shadow(color: .white, radius: 2)
                            .position(x: size.width * p.0, y: size.height * p.1)
                    }
                }
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(scene.line)
    }

    // MARK: Rooms

    private func room(_ size: CGSize, windowAt x: CGFloat, windowWidth: CGFloat = 0.3) -> some View {
        let night = scene.sky == .night
        return ZStack {
            LinearGradient(colors: night ? CloudPalette.nightWall : CloudPalette.wall, startPoint: .top, endPoint: .bottom)
            Window(sky: scene.sky, raining: scene == .drizzle)
                .frame(width: size.width * windowWidth, height: size.width * windowWidth * 1.1)
                .position(x: size.width * x, y: size.height * 0.26)
            Rectangle().fill(CloudPalette.floor.opacity(night ? 0.6 : 1))
                .frame(height: size.height * 0.16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            if night {
                // Lamplight.
                RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.45), .clear], center: .init(x: 0.5, y: 0.55), startRadius: 0, endRadius: size.width * 0.6)
            }
        }
    }

    private func cloud(_ size: CGSize, width: CGFloat, x: CGFloat, y: CGFloat, paws: Bool = true) -> some View {
        FuzzyCloud(face: face, gloomy: scene == .drizzle, paws: paws)
            .frame(width: size.width * width)
            .position(x: size.width * x, y: size.height * y)
    }

    private func sofa(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        let sofaFrame = CGSize(width: w * 0.98, height: h * 0.5)
        return ZStack {
            room(size, windowAt: 0.8, windowWidth: 0.26)
            Sofa().frame(width: sofaFrame.width, height: sofaFrame.height).position(x: w / 2, y: h * 0.7)
            cloud(size, width: 0.62, x: 0.5, y: 0.58, paws: scene != .cozyTea)
            SofaFront().frame(width: sofaFrame.width, height: sofaFrame.height).position(x: w / 2, y: h * 0.7)
            if scene == .cozyTea {
                Duvet().frame(width: w * 0.6, height: h * 0.2).position(x: w / 2, y: h * 0.76)
                CloudPaws().frame(width: w * 0.62).position(x: w * 0.5, y: h * 0.58)
            }
            sofaProps(size)
        }
    }

    /// Kept simple: no props in front of the cloud (they read as legs), just
    /// the pup when it's cuddle time.
    @ViewBuilder
    private func sofaProps(_ size: CGSize) -> some View {
        let w = size.width, h = size.height, s = min(w, h)
        if scene == .cuddle {
            pup(s: s * 0.95).position(x: w * 0.72, y: h * 0.62)
        }
    }

    private func bed(_ size: CGSize) -> some View {
        let w = size.width, h = size.height, s = min(w, h)
        return ZStack {
            room(size, windowAt: 0.82, windowWidth: 0.24)
            Bed().frame(width: w * 0.98, height: h * 0.6).position(x: w / 2, y: h * 0.62)
            cloud(size, width: 0.7, x: 0.5, y: 0.55, paws: false)
            Duvet(color: scene == .sleep ? Color(red: 0.86, green: 0.82, blue: 0.96) : CloudPalette.strawberry)
                .frame(width: w * 1.04, height: h * 0.36).position(x: w / 2, y: h * 0.86)
            CloudPaws().frame(width: w * 0.7).position(x: w * 0.5, y: h * 0.6)
            if scene == .sleep {
                Text("z z").font(.system(size: s * 0.09, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).position(x: w * 0.3, y: h * 0.2)
                pup(s: s * 0.75).position(x: w * 0.16, y: h * 0.74)
            }
        }
    }

    private func kitchen(_ size: CGSize) -> some View {
        let w = size.width, h = size.height, s = min(w, h)
        return ZStack {
            room(size, windowAt: 0.5, windowWidth: 0.3)
            cloud(size, width: 0.58, x: 0.5, y: 0.6, paws: true)
            Counter().frame(width: w, height: h * 0.3).position(x: w / 2, y: h * 0.86)

        }
    }

    private func outside(_ size: CGSize) -> some View {
        let w = size.width, h = size.height, s = min(w, h)
        return ZStack {
            LinearGradient(colors: CloudPalette.sky(scene.sky), startPoint: .top, endPoint: .bottom)
            Ellipse().fill(LinearGradient(colors: [CloudPalette.matcha.opacity(0.75), CloudPalette.matcha], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 1.7, height: h * 0.55).position(x: w / 2, y: h * 1.02)
            switch scene {
            case .walk:
                symbol("tree.fill", s * 0.24, CloudPalette.matcha).position(x: w * 0.88, y: h * 0.52)
                cloud(size, width: 0.56, x: 0.38, y: 0.6)
                pup(s: s).position(x: w * 0.78, y: h * 0.8)
                leash(from: CGPoint(x: w * 0.5, y: h * 0.74), to: CGPoint(x: w * 0.72, y: h * 0.78))
            case .picnic:
                symbol("sun.max.fill", s * 0.14, .yellow.opacity(0.85)).position(x: w * 0.86, y: h * 0.16)
                Ellipse().fill(CloudPalette.strawberry).frame(width: w * 0.8, height: h * 0.12).position(x: w * 0.5, y: h * 0.86)
                cloud(size, width: 0.56, x: 0.45, y: 0.64)
                symbol("basket.fill", s * 0.13, CloudPalette.pup).position(x: w * 0.82, y: h * 0.8)
            default: // fetch
                symbol("tennisball.fill", s * 0.08, Color(red: 0.85, green: 0.9, blue: 0.3)).position(x: w * 0.7, y: h * 0.3)
                cloud(size, width: 0.56, x: 0.36, y: 0.62)
                pup(s: s).position(x: w * 0.8, y: h * 0.8)
            }
        }
    }

    // MARK: Bits

    private func symbol(_ name: String, _ size: CGFloat, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }

    private func pup(s: CGFloat) -> some View {
        Image(systemName: "dog.fill")
            .font(.system(size: s * 0.15))
            .foregroundStyle(CloudPalette.pup)
            .scaleEffect(x: -1, y: 1)
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
    }

    private func leash(from a: CGPoint, to b: CGPoint) -> some View {
        Path { p in
            p.move(to: a)
            p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: max(a.y, b.y) + 6))
        }
        .stroke(CloudPalette.ink.opacity(0.5), lineWidth: 1)
    }
}
