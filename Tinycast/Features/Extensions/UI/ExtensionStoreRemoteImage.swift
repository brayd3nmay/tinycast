import SwiftUI

/// A store image at its own size — an avatar or a screenshot — with a tile until it lands.
struct ExtensionStoreRemoteImage: View {
    @Environment(\.metrics) private var metrics
    let url: URL
    var shape: AnyShape?
    @State private var image: NSImage?

    private var clip: AnyShape {
        shape ?? AnyShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.Colors.iconPlaceholder
            }
        }
        .clipShape(clip)
        .task(id: url) {
            image = await ExtensionIconCache.loadRemoteAsync(url, asIcon: false)
        }
    }
}

/// A contributor's face, or the store's coloured initials tile when none was uploaded.
struct ExtensionStoreAvatar: View {
    let person: ExtensionStoreDetail.Person
    let size: CGFloat

    var body: some View {
        Group {
            if let url = person.avatarURL {
                ExtensionStoreRemoteImage(url: url, shape: AnyShape(Circle()))
            } else {
                Circle()
                    .fill(placeholderColor)
                    .overlay(
                        Text(person.initials)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// `#RRGGBB` from the store; the app's control surface when it sent none.
    private var placeholderColor: Color {
        guard let hex = person.placeholderColorHex?.dropFirst(), hex.count == 6,
            let value = UInt32(hex, radix: 16)
        else { return Theme.Colors.controlSurface }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
