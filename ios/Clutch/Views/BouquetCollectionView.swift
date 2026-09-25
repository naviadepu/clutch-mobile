import SwiftUI

/// Every bouquet she's collected, newest first, with her current streak —
/// laid out like a florist's catalogue: each bunch on its own card on warm
/// off-white. Tapping one opens its share card.
struct BouquetCollectionView: View {
    let bouquets: [CollectedBouquet]
    let streak: Int

    @Environment(\.dismiss) private var dismiss
    @State private var sharing: CollectedBouquet?
    private let signature = SignatureStore.load()

    private static let backdrop = Color(hex: 0xEFEBE6)
    private static let card = Color(hex: 0xF7F4F0)
    private static let ink = Color.ink

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            Self.backdrop.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if bouquets.isEmpty {
                        Text("Finish today's cards, or tap \u{201C}Nothing today\u{201D}, to collect your first bouquet.")
                            .font(.custom("Quicksand-Regular", size: 16))
                            .foregroundStyle(Self.ink.opacity(0.7))
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(bouquets) { bouquet in
                                Button { share(bouquet) } label: {
                                    tile(for: bouquet)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Bouquet from \(bouquet.day.formatted(date: .long, time: .omitted))")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }

            if sharing != nil {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { closeShare() }
                    .overlay {
                        PolaroidCard(flowers: sharing?.flowers ?? [], style: sharing?.style ?? .plain, signature: signature, caption: caption(for: sharing), onClose: closeShare)
                    }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.ink)
                    .frame(width: 34, height: 34)
                    .background(Self.card, in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your bouquets")
                .font(.custom("HelveticaNeue-Medium", size: 30))
                .tracking(-1)
                .foregroundStyle(Self.ink)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(streak)")
                    .font(.custom("DotoRounded-Medium", size: 56))
                Text("day streak")
                    .font(.custom("Quicksand-Regular", size: 16))
                Spacer()
                Text(bouquets.count == 1 ? "1 collected" : "\(bouquets.count) collected")
                    .font(.custom("Quicksand-Light", size: 14))
                    .opacity(0.75)
            }
            .foregroundStyle(Self.ink)
        }
    }

    private func tile(for bouquet: CollectedBouquet) -> some View {
        VStack(spacing: 6) {
            Bouquet(flowers: bouquet.flowers, reduceMotion: true, animatesIn: false, signature: signature, style: bouquet.style)
                .scaleEffect(0.26, anchor: .bottom)
                .frame(width: 140, height: 160, alignment: .bottom)
                .clipped()

            Text(bouquet.day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundStyle(Self.ink.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
    }

    private func caption(for bouquet: CollectedBouquet?) -> String {
        guard let bouquet else { return "" }
        return "Bloomed \(bouquet.day.formatted(date: .long, time: .omitted))"
    }

    private func share(_ bouquet: CollectedBouquet) {
        withAnimation(.easeInOut(duration: 0.25)) { sharing = bouquet }
    }

    private func closeShare() {
        withAnimation(.easeInOut(duration: 0.25)) { sharing = nil }
    }
}
