import SwiftUI

/// The frame every full-page feature screen shares: the aura, a big title,
/// a scrolling column of cards, and a round close button.
struct ClutchPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.custom("InterTight-SemiBold", size: 30))
                            .tracking(-1.2)
                            .foregroundStyle(Color.cardInk)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 15, design: .serif).italic())
                                .foregroundStyle(Color.cardInk.opacity(0.7))
                        }
                    }
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.cardInk)
                    .frame(width: 36, height: 36)
                    .background(Color.cream, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 12)
            .accessibilityLabel("Close")
        }
    }
}

/// A full-width pill button in the details style.
struct PagePrimaryButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.custom("DMSans-Regular", size: 15))
            .foregroundStyle(Color.cardInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.strawberry, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The round icon-and-word button used across the feature screens, so
/// every action reads as a picture first. Wrap it in a Button, Link or
/// ShareLink.
struct IconBubble: View {
    let symbol: String
    let title: String
    var filled = false
    var size: CGFloat = 58

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .regular))
                .foregroundStyle(Color.cardInk)
                .frame(width: size, height: size)
                .background(filled ? Color.strawberry : Color.cream, in: Circle())
                .shadow(color: Color(hex: 0x4A3328).opacity(0.10), radius: 12, y: 6)
            Text(title)
                .font(.custom("DMSans-Regular", size: 12))
                .foregroundStyle(Color.cardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// A plain cream panel: a card without a title, for content that speaks
/// for itself.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: 0x4A3328).opacity(0.08), radius: 20, y: 10)
    }
}
