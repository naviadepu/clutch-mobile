import MessageUI
import Photos
import UIKit

/// Where a bouquet can go from the share card: an Instagram story, Messages,
/// the photo library, or anywhere else through the system share sheet
/// (which is also how TikTok, Snapchat and the rest pick up an image — they
/// ship share extensions rather than a public "post this image" link).
@MainActor
enum BouquetSharing {
    /// Instagram only accepts story shares from apps registered with Meta.
    /// Put the Facebook App ID in Info.plist under `FacebookAppID`; until
    /// then the Story button falls back to the share sheet.
    private static var facebookAppID: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String
        return id?.isEmpty == false ? id : nil
    }

    /// Opens Instagram's story composer with the bouquet as a sticker on the
    /// blush gradient. Returns `false` when that isn't possible (no app ID,
    /// or Instagram isn't installed) so the caller can fall back.
    static func shareToInstagramStory(_ image: UIImage) -> Bool {
        guard let appID = facebookAppID,
              let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              UIApplication.shared.canOpenURL(url),
              let sticker = image.pngData()
        else { return false }

        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.stickerImage": sticker,
                "com.instagram.sharedSticker.backgroundTopColor": "#FDF1F3",
                "com.instagram.sharedSticker.backgroundBottomColor": "#E8A9BA",
            ]],
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(url)
        return true
    }

    /// A new iMessage with the bouquet attached. Returns `false` on devices
    /// that can't send messages (including the Simulator).
    static func shareToMessages(_ image: UIImage, body: String) -> Bool {
        guard MFMessageComposeViewController.canSendText(),
              MFMessageComposeViewController.canSendAttachments(),
              let data = image.jpegData(compressionQuality: 0.92),
              let presenter = topViewController()
        else { return false }

        let composer = MFMessageComposeViewController()
        composer.body = body
        composer.addAttachmentData(data, typeIdentifier: "public.jpeg", filename: "bouquet.jpg")
        composer.messageComposeDelegate = MessageDismisser.shared
        presenter.present(composer, animated: true)
        return true
    }

    /// Saves to the photo library (add-only access). Calls back with whether
    /// it worked.
    static func saveToPhotos(_ image: UIImage, completion: @escaping @MainActor (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                Task { @MainActor in completion(success) }
            }
        }
    }

    /// The system share sheet, for TikTok and everything else.
    static func presentShareSheet(_ image: UIImage, text: String) {
        guard let presenter = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: [image, text], applicationActivities: nil)
        // iPad needs an anchor for the popover.
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0
        )
        presenter.present(sheet, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Dismisses the Messages composer when she sends or cancels.
private final class MessageDismisser: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = MessageDismisser()

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}
