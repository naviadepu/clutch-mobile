import UIKit

/// Keeps her onboarding scribble on disk, so the Garden, the bouquet tag
/// and shares can show it after the app relaunches.
enum SignatureStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "signature.png")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data, scale: UIScreen.main.scale)
    }

    /// `nil` clears a saved signature.
    static func save(_ image: UIImage?) {
        guard let image, let data = image.pngData() else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
