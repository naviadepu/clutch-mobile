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

        // A full-screen 9:16 background, so the story isn't cropped.
        UIPasteboard.general.setItems(
            [[
                "com.instagram.sharedSticker.backgroundImage": sticker,
            ]],
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(url)
        return true
    }

    static var hasInstagram: Bool {
        URL(string: "instagram://app").map(UIApplication.shared.canOpenURL) ?? false
    }

    /// Story: straight into Instagram's story composer when the app is
    /// registered with Meta; otherwise saves the image and opens the story
    /// camera, where it's the newest photo. Without Instagram, the share
    /// sheet.
    static func shareStory(_ image: UIImage, text: String, saved: @escaping @MainActor (Bool) -> Void) {
        if shareToInstagramStory(image) { return }
        guard hasInstagram, let camera = URL(string: "instagram://story-camera") else {
            presentShareSheet(image, text: text)
            return
        }
        saveToPhotos(image) { ok in
            saved(ok)
            guard ok else { return }
            UIApplication.shared.open(camera) { opened in
                if !opened { presentShareSheet(image, text: text) }
            }
        }
    }

    /// Post: saves the image and opens Instagram's new-post screen with it
    /// selected. Without Instagram, the share sheet.
    static func shareToInstagramPost(_ image: UIImage, text: String, saved: @escaping @MainActor (Bool) -> Void) {
        guard hasInstagram else {
            presentShareSheet(image, text: text)
            return
        }
        saveToPhotosReturningID(image) { id in
            saved(id != nil)
            guard let id,
                  let url = URL(string: "instagram://library?LocalIdentifier=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)")
            else {
                presentShareSheet(image, text: text)
                return
            }
            UIApplication.shared.open(url) { opened in
                if !opened { presentShareSheet(image, text: text) }
            }
        }
    }

    /// Instagram has no link for sending an image to a chat, so DMs go
    /// through the share sheet, where Instagram's share option sends it.
    static func shareToInstagramMessage(_ image: UIImage) {
        presentShareSheet(items: [image])
    }

    /// Saves and hands back the new photo's identifier.
    static func saveToPhotosReturningID(_ image: UIImage, completion: @escaping @MainActor (String?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in completion(nil) }
                return
            }
            let created = CreatedAssetID()
            PHPhotoLibrary.shared().performChanges {
                created.value = PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, _ in
                let id = success ? created.value : nil
                Task { @MainActor in completion(id) }
            }
        }
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
        presentShareSheet(items: [image, text])
    }

    /// The system share sheet for anything — the doctor summary PDF too.
    static func presentShareSheet(items: [Any]) {
        guard let presenter = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
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

/// Carries the new photo's identifier out of the Photos change block,
/// which runs before its completion handler on Photos' own queue.
private final class CreatedAssetID: @unchecked Sendable {
    var value: String?
}
