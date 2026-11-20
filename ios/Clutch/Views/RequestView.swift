import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// "Free period products": the campus spots that keep products out for
/// anyone, nearest first once she's shared her location. Quiet cream
/// paper cards resting on an out-of-focus backdrop — calm beats dense.
/// Tapping a card opens its full details.
struct RequestView: View {
    /// Injectable so previews and screenshots can stand in for the
    /// bundled list.
    var locations: [ProductLocation] = ProductLocationStore.all

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nearby = NearbyLocationProvider()
    @StateObject private var community = SharedSpotReports()
    #if DEBUG
    /// `-showMap` opens on the map, for screenshots.
    @State private var showMap = ProcessInfo.processInfo.arguments.contains("-showMap")
    #else
    @State private var showMap = false
    #endif

    @State private var askedForLocation = false
    @State private var reported: Set<String> = []
    @State private var suggesting = false
    @State private var selected: ProductLocation?

    /// The bundled spots with what other people reported on top, nearest
    /// first once she's shared her location.
    private var sorted: [ProductLocation] {
        let current = locations.map(community.apply)
        guard let here = nearby.location else { return current }
        return ProductLocationStore.sortedByDistance(from: here, in: current)
    }

    var body: some View {
        ZStack {
            RequestBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("free period products")
                        .font(.custom("InterTight-SemiBold", size: 30))
                        .tracking(-1.2)
                        .foregroundStyle(Paper.ink)
                        .padding(.trailing, 56)
                        .accessibilityAddTraits(.isHeader)

                    if nearby.isDenied {
                        sortByClosest
                            .padding(.top, 18)
                    }

                    if !locations.isEmpty {
                        viewToggle.padding(.top, 22)
                    }

                    Group {
                        if locations.isEmpty {
                            emptyState
                        } else if showMap {
                            spotMap
                        } else {
                            spotGrid
                        }
                    }
                    .padding(.top, 24)

                    suggestFooter
                        .padding(.top, 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 76)
                .padding(.bottom, 56)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .sheet(isPresented: $suggesting) { SuggestSpotSheet() }
        .sheet(item: $selected) { location in
            SpotDetailSheet(
                location: location,
                distance: distanceText(to: location),
                justReported: reported.contains(location.id),
                onReportEmpty: { reportEmpty(location) },
                onReportStocked: { reportStocked(location) }
            )
        }
        .onAppear(perform: askForLocationOnce)
        .task { community.start() }
        .onDisappear { community.stop() }
    }

    private func card(for location: ProductLocation) -> some View {
        Button { selected = location } label: {
            SpotCard(location: location, distance: distanceText(to: location))
        }
        .buttonStyle(PressableCard())
    }

    /// Two across; each row is as tall as its taller card so the grid
    /// stays even.
    private var spotGrid: some View {
        let pairs = stride(from: 0, to: sorted.count, by: 2).map {
            Array(sorted[$0..<min($0 + 2, sorted.count)])
        }
        return Grid(horizontalSpacing: 16, verticalSpacing: 28) {
            ForEach(pairs, id: \.first?.id) { pair in
                GridRow {
                    ForEach(pair) { card(for: $0) }
                    if pair.count == 1 {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    /// Shown only after she's said no to location — a quiet way back in.
    private var sortByClosest: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location")
                    .font(.system(size: 10, weight: .light))
                SmallLabel("Sort by closest")
            }
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Paper.cream, in: Capsule())
            .shadow(color: Paper.shadow, radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Settings to turn on location")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No spots on the list yet.")
                .font(.custom(Serif.name, size: Serif.cardTitleSize))
                .foregroundStyle(Paper.ink)

            Text("We're only adding places someone has checked in person, so this stays honest. Know one that's always stocked? Tell us and it'll be the first.")
                .font(.custom("DMSans-Light", size: 13))
                .foregroundStyle(Paper.soft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .paperCard()
    }

    /// A footnote, not a header: the list is young, and this is where she
    /// can add to it.
    private var suggestFooter: some View {
        Button { suggesting = true } label: {
            VStack(spacing: 10) {
                Text("We're still adding spots.")
                    .font(.custom(Serif.name, size: Serif.cardTitleSize - 2))
                    .foregroundStyle(Paper.ink)
                SmallLabel("Suggest one we're missing  →")
                    .foregroundStyle(Paper.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .paperCard()
        }
        .buttonStyle(PressableCard())
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Paper.ink)
                .frame(width: 36, height: 36)
                .background(Paper.cream, in: Circle())
                .shadow(color: Paper.shadow, radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 24)
        .padding(.top, 16)
        .accessibilityLabel("Close")
    }

    /// Asks once, straight away — the system prompt says why, and the
    /// list works the same without it.
    private func askForLocationOnce() {
        guard !askedForLocation else { return }
        askedForLocation = true
        nearby.request()
    }

    private func distanceText(to location: ProductLocation) -> String? {
        guard let here = nearby.location else { return nil }
        let metres = here.distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude))
        let feet = metres * 3.28084
        if feet < 1000 { return "\(Int((feet / 10).rounded()) * 10) ft" }
        return String(format: "%.1f mi", feet / 5280)
    }

    private func reportEmpty(_ location: ProductLocation) {
        SpotReports.reportEmpty(location.id)
        SharedSpotReports.report(location.id, kind: .empty)
        withAnimation(.easeInOut(duration: 0.2)) { _ = reported.insert(location.id) }
    }

    private func reportStocked(_ location: ProductLocation) {
        SharedSpotReports.report(location.id, kind: .stocked)
        withAnimation(.easeInOut(duration: 0.2)) { _ = reported.insert(location.id) }
    }

    // MARK: Map

    private var viewToggle: some View {
        HStack(spacing: 8) {
            toggleChip("List", "square.grid.2x2", on: !showMap) { showMap = false }
            toggleChip("Map", "map", on: showMap) { showMap = true }
        }
    }

    private func toggleChip(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { action() } } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .light))
                SmallLabel(title)
            }
            .foregroundStyle(on ? Paper.cream : Paper.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(on ? Paper.ink : Paper.cream, in: Capsule())
            .shadow(color: Paper.shadow, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var spotMap: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(sorted) { location in
                Annotation(location.name, coordinate: location.coordinate, anchor: .bottom) {
                    Button { selected = location } label: { pin(for: location) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(location.name), \(location.stockStatus.label)")
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 460)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Paper.shadow, radius: 16, y: 8)
    }

    /// A drop on a cream tag, tinted by how stocked the spot is.
    private func pin(for location: ProductLocation) -> some View {
        let tint: Color = switch location.stockStatus {
        case .stocked: Color.matcha
        case .low: Color(hex: 0xE3A44B)
        case .empty: Color(hex: 0xB9A9A2)
        case .unknown: Color(hex: 0xE58DAA)
        }
        return VStack(spacing: 0) {
            Image(systemName: "drop.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Paper

/// Warm cream stock and ink-brown type, like a printed card.
private enum Paper {
    static let cream = Color(hex: 0xF5F1EA)
    static let ink = Color(hex: 0x3B2F2A)
    static let soft = Color(hex: 0x857469)
    static let rule = Color(hex: 0x3B2F2A).opacity(0.12)
    static let shadow = Color(hex: 0x4A3328).opacity(0.10)
}

private struct PaperCard: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(Paper.cream)
                    .overlay {
                        GrainOverlay()
                            .blendMode(.multiply)
                            .opacity(0.07)
                            .clipShape(shape)
                    }
            }
            // Low and wide, so the card rests on the backdrop rather
            // than floating above it.
            .shadow(color: Paper.shadow, radius: 30, y: 16)
            .shadow(color: Paper.shadow.opacity(0.6), radius: 2, y: 1)
    }
}

private extension View {
    func paperCard(radius: CGFloat = 18) -> some View {
        modifier(PaperCard(radius: radius))
    }
}

/// Uppercase, very small, widely spaced, light — the printed-label voice
/// for tags, hours and status.
private struct SmallLabel: View {
    let text: String
    var size: CGFloat = 9.5

    init(_ text: String, size: CGFloat = 9.5) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.custom("DMSans-Light", size: size))
            .tracking(size * 0.1)
            .lineLimit(1)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Paper.rule).frame(height: 0.5)
    }
}

// MARK: - Type choices

/// Card titles and section headings: a light, refined serif.
private enum Serif {
    static let name = "CormorantGaramond-Light"
    /// Cormorant's small x-height wants a larger size than most serifs.
    static let cardTitleSize: CGFloat = 24
}

// MARK: - Card

/// One spot as a save-the-date: a cream card slipping out of a
/// translucent pink envelope. The card carries the status, name and
/// directions; what's stocked and when it's open are printed on the
/// envelope's front pocket.
private struct SpotCard: View {
    let location: ProductLocation
    let distance: String?

    /// How far the card's lower edge sits down inside the pocket.
    private static let tuck: CGFloat = 46

    var body: some View {
        VStack(spacing: -Self.tuck) {
            card
                .padding(.horizontal, 10)
                .rotationEffect(.degrees(-1.5))
                .frame(maxHeight: .infinity, alignment: .top)

            pocket
        }
        .padding(.top, 12)
        .background(alignment: .bottom) { EnvelopeBack().padding(.top, 34) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 256)
        .compositingGroup()
        .shadow(color: Envelope.shadow, radius: 24, y: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: location.placeSymbol)
                    .font(.system(size: 13, weight: .ultraLight))
                    .foregroundStyle(Paper.soft)
                Spacer(minLength: 4)
                StatusLabel(status: location.stockStatus)
            }

            Text(location.name)
                .font(.custom(Serif.name, size: Serif.cardTitleSize))
                .foregroundStyle(Paper.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(location.directions)
                .font(.custom("DMSans-Light", size: 12))
                .foregroundStyle(Paper.soft)
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // Room below the text for the part that sits inside the pocket.
        .padding(.bottom, Self.tuck + 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperCard(radius: 6)
    }

    private var pocket: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !location.items.isEmpty {
                ItemLabels(items: location.items)
                    .foregroundStyle(Envelope.ink)
            }
            // Side by side when there's room, stacked in a narrow card.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    SmallLabel(location.hours ?? "Hours unknown").fixedSize()
                    if let distance {
                        SmallLabel("  ·  \(distance)").fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    SmallLabel(location.hours ?? "Hours unknown")
                        .minimumScaleFactor(0.8)
                    if let distance {
                        SmallLabel(distance)
                    }
                }
            }
            .foregroundStyle(Envelope.ink.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.top, EnvelopePocket.notch + 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            EnvelopePocket()
                .fill(Envelope.front)
                .overlay {
                    // A sheen across the vellum, brightest at the flap edges.
                    EnvelopePocket()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }
                .overlay { EnvelopePocket().stroke(.white.opacity(0.55), lineWidth: 0.6) }
        }
    }
}

// MARK: - Envelope

/// The translucent pink vellum of the reference envelope.
private enum Envelope {
    static let back = Color(hex: 0xF3A9C0).opacity(0.55)
    static let front = Color(hex: 0xF5B3C7).opacity(0.82)
    static let ink = Color(hex: 0x5A2E3C)
    static let shadow = Color(hex: 0x8A3F58).opacity(0.14)
}

/// The inside of the envelope with its flap open behind the card.
private struct EnvelopeBack: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Envelope.back)
            OpenFlap()
                .fill(Envelope.back)
                .frame(height: 34)
                .offset(y: -34)
        }
    }
}

/// The open flap: a soft triangle standing up off the back's top edge.
private struct OpenFlap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 4, y: rect.maxY),
            control: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY - rect.height * 0.9)
        )
        path.closeSubpath()
        return path
    }
}

/// The front pocket: the two side flaps meet in a shallow V at the top.
private struct EnvelopePocket: Shape {
    static let notch: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 10
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + Self.notch))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Detail sheet

/// Everything about one spot on a sheet of the same cream stock, with
/// the way to say it's run out.
private struct SpotDetailSheet: View {
    let location: ProductLocation
    let distance: String?
    let justReported: Bool
    let onReportEmpty: () -> Void
    let onReportStocked: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    StatusLabel(status: location.stockStatus)
                    if let distance {
                        SmallLabel("·  \(distance)")
                            .foregroundStyle(Paper.soft)
                    }
                }

                Text(location.name)
                    .font(.custom(Serif.name, size: Serif.cardTitleSize + 10))
                    .foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                VStack(alignment: .leading, spacing: 0) {
                    section("Where") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.directions)
                            if let address = location.address {
                                Text(address).foregroundStyle(Paper.soft)
                            }
                        }
                    }
                    if !location.items.isEmpty {
                        section("What") {
                            ItemLabels(items: location.items, size: 10.5)
                                .foregroundStyle(Paper.ink)
                        }
                    }
                    section("When") {
                        Text(location.hours ?? "Hours unknown")
                            .foregroundStyle(location.hours == nil ? Paper.soft : Paper.ink)
                    }
                    if let refilledBy = location.refilledBy {
                        section("Kept stocked by") { Text(refilledBy) }
                    }
                    if let notes = location.notes {
                        section("Good to know") { Text(notes) }
                    }
                    Hairline()
                }
                .font(.custom("DMSans-Light", size: 15))
                .foregroundStyle(Paper.ink)
                .padding(.top, 28)

                HStack(spacing: 8) {
                    SmallLabel(checkedText)
                        .foregroundStyle(Paper.soft)

                    Spacer(minLength: 0)

                    if justReported {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .light))
                            SmallLabel("Thanks, noted")
                        }
                        .foregroundStyle(Paper.soft.opacity(0.7))
                    } else {
                        Button(action: onReportStocked) {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.thumbsup").font(.system(size: 10, weight: .light))
                                SmallLabel("It's stocked")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Paper.soft)
                        Button(action: onReportEmpty) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.bubble").font(.system(size: 10, weight: .light))
                                SmallLabel("Report empty")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Paper.soft)
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground {
            Paper.cream
                .overlay { GrainOverlay().blendMode(.multiply).opacity(0.07) }
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                SmallLabel(label)
                    .foregroundStyle(Paper.soft)
                    .frame(width: 92, alignment: .leading)
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 18)
        }
    }

    private var checkedText: String {
        guard let verified = location.lastVerified else { return "Not checked in person yet" }
        return "Last checked \(verified.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

// MARK: - Small pieces

/// A small dot and the status in label type: green for stocked, amber
/// for low.
private struct StatusLabel: View {
    let status: ProductLocation.StockStatus

    private var color: Color {
        switch status {
        case .stocked: Color(hex: 0x6F9A68)
        case .low: Color(hex: 0xD29A48)
        case .empty: Color(hex: 0xB8665A)
        case .unknown: Color(hex: 0xB9AEA6)
        }
    }

    private var text: String {
        switch status {
        case .stocked: "Stocked"
        case .low: "Low"
        case .empty: "Empty"
        case .unknown: "Unchecked"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            SmallLabel(text, size: 8.5)
                .foregroundStyle(Paper.soft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
    }
}

private extension ProductLocation {
    /// An outlined glyph for the kind of place, guessed from its name.
    var placeSymbol: String {
        let name = name.lowercased()
        if name.contains("library") { return "books.vertical" }
        if name.contains("rec") || name.contains("gym") || name.contains("fitness") { return "dumbbell" }
        switch category {
        case .clinic: return "cross.case"
        case .partnerStore: return "bag"
        case .campusRestroom, .campusBuilding: return "building.2"
        }
    }
}

/// What's stocked as printed labels — no pills, just letter-spaced words
/// with thin rules between them, wrapping when a card runs out of room.
private struct ItemLabels: View {
    let items: [ProductLocation.Item]
    var size: CGFloat = 9.5

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Paper.rule)
                        .frame(width: 0.5, height: size + 2)
                        .layoutValue(key: FlowSeparator.self, value: true)
                }
                SmallLabel(item.label, size: size)
            }
        }
    }
}

/// Marks a subview as a separator, which the flow drops wherever it
/// would start or end a line.
private struct FlowSeparator: LayoutValueKey {
    static let defaultValue = false
}

/// Lays children left to right, wrapping to a new line when the next one
/// won't fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, width: bounds.width)
        let shown = Set(rows.flatMap(\.indices))
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let dy = (row.height - size.height) / 2
                subviews[index].place(at: CGPoint(x: x, y: y + dy), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
        // Dropped separators still need placing; give them no size.
        for index in subviews.indices where !shown.contains(index) {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: .zero)
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(_ index: Int, size: CGSize, spacing: CGFloat) {
            width = indices.isEmpty ? size.width : width + spacing + size.width
            height = max(height, size.height)
            indices.append(index)
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var pendingSeparator: Int?

        for index in subviews.indices {
            if subviews[index][FlowSeparator.self] {
                // Only kept if the next item lands on the same line.
                pendingSeparator = current.indices.isEmpty ? nil : index
                continue
            }
            let size = subviews[index].sizeThatFits(.unspecified)
            var needed = current.width + size.width
            if let separator = pendingSeparator {
                needed += subviews[separator].sizeThatFits(.unspecified).width + spacing * 2
            } else if !current.indices.isEmpty {
                needed += spacing
            }
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            } else if let separator = pendingSeparator {
                current.append(separator, size: subviews[separator].sizeThatFits(.unspecified), spacing: spacing)
            }
            pendingSeparator = nil
            current.append(index, size: size, spacing: spacing)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Suggest a spot

/// A small form for a spot the list is missing. Saved on the device until
/// there's somewhere to send it.
private struct SuggestSpotSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var directions = ""
    @State private var sent = false

    private var canSend: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sent ? "Thank you." : "Know a spot?")
                .font(.custom(Serif.name, size: Serif.cardTitleSize + 10))
                .foregroundStyle(Paper.ink)

            Text(sent
                 ? "We'll check it out and add it once someone's seen it stocked."
                 : "Tell us where it is and how to find it inside.")
                .font(.custom("DMSans-Light", size: 14))
                .foregroundStyle(Paper.soft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if !sent {
                VStack(alignment: .leading, spacing: 0) {
                    Hairline()
                    field("Building", text: $name, prompt: "Sparks Hall")
                    Hairline()
                    field("How to find it", text: $directions, prompt: "2nd floor, restroom by the elevators")
                    Hairline()
                }
                .padding(.top, 32)

                Button {
                    SpotReports.suggest(name: name, directions: directions)
                    withAnimation(.easeInOut(duration: 0.25)) { sent = true }
                } label: {
                    SmallLabel("Send it in", size: 10.5)
                        .foregroundStyle(Paper.ink)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .overlay(Capsule().strokeBorder(Paper.ink.opacity(0.4), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)
                .padding(.top, 28)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Paper.cream
                .overlay { GrainOverlay().blendMode(.multiply).opacity(0.07) }
                .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.top, 16)
            .accessibilityLabel("Close")
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallLabel(label)
                .foregroundStyle(Paper.soft)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Paper.soft.opacity(0.6)))
                .font(.custom("DMSans-Light", size: 16))
                .foregroundStyle(Paper.ink)
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Background

/// The landing video, still moving, washed toward a soft neutral so it
/// reads as a backdrop and the cards stay the focus.
/// The blush gradient sits underneath — what shows if the video can't
/// load, and all that shows when Reduce Motion is on. The dancer glows
/// on top, fixed while the cards scroll past.
private struct RequestBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    private var hasVideo: Bool {
        Bundle.main.url(forResource: "background-1", withExtension: "mp4") != nil
    }

    var body: some View {
        ZStack {
            BlushGradient()

            if hasVideo && !reduceMotion {
                LoopingVideoPlayer(resourceName: "background-1", resourceExtension: "mp4")
            }

            // Softened and drained of some colour, but light enough that
            // the footage still visibly drifts.
            Color(hex: 0xE6DDD6).opacity(0.32)

            GlowingDancer()
                .containerRelativeFrame(.vertical) { height, _ in height * 0.72 }
                .offset(x: 70, y: floating ? -100 : -82)
                .opacity(0.9)

            GrainOverlay()
                .blendMode(.overlay)
                .opacity(0.1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

/// The dancer from the reference poster, lit from within: a warm core
/// that whitens toward the middle, a soft halo that fades into the
/// background, and no hard edge anywhere.
private struct GlowingDancer: View {
    private var dancer: some View {
        Image("dancer")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }

    var body: some View {
        ZStack {
            // Wide, warm halo.
            dancer
                .foregroundStyle(Color(hex: 0xFFC7B4))
                .blur(radius: 44)
            dancer
                .foregroundStyle(Color(hex: 0xFFE2D4))
                .blur(radius: 24)
            // Tighter white bloom hugging the body.
            dancer
                .foregroundStyle(.white)
                .blur(radius: 12)
                .opacity(0.85)
            // The body: warm at the rim, white at the core.
            dancer
                .foregroundStyle(Color(hex: 0xFFEEE6))
                .overlay {
                    dancer
                        .foregroundStyle(.white)
                        .blur(radius: 5)
                        .mask(dancer)
                }
        }
        .compositingGroup()
    }
}

#Preview {
    RequestView()
}
