import UIKit
import UniformTypeIdentifiers

/// Entry point for the Lijster Share Extension.
/// Receives a URL or image from the share sheet, hands it off to the main app
/// via the `lijster://` URL scheme, and immediately closes.
final class ShareViewController: UIViewController {

    private let appGroupID = "group.com.bvanriessen.listapp"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processSharedContent()
    }

    // MARK: - Processing

    private func processSharedContent() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first
        else {
            completeAndReturn()
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            loadURL(from: provider)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadImage(from: provider)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            loadPlainText(from: provider)
        } else {
            completeAndReturn()
        }
    }

    // MARK: - Loaders

    private func loadURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] rawValue, _ in
            DispatchQueue.main.async {
                if let url = rawValue as? URL {
                    self?.openMainApp(webURL: url)
                } else {
                    self?.completeAndReturn()
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] rawValue, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let imageURL = rawValue as? URL {
                    self.copyImageToAppGroup(imageURL)
                } else if let image = rawValue as? UIImage {
                    self.saveImageToAppGroup(image)
                } else {
                    self.completeAndReturn()
                }
            }
        }
    }

    private func loadPlainText(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] rawValue, _ in
            DispatchQueue.main.async {
                if let text = rawValue as? String,
                   let url = URL(string: text),
                   url.scheme == "https" || url.scheme == "http" {
                    self?.openMainApp(webURL: url)
                } else {
                    self?.completeAndReturn()
                }
            }
        }
    }

    // MARK: - Image helpers

    private func copyImageToAppGroup(_ sourceURL: URL) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            completeAndReturn()
            return
        }
        let dest = container.appendingPathComponent("pendingShareImage.jpg")
        try? FileManager.default.removeItem(at: dest)
        if (try? FileManager.default.copyItem(at: sourceURL, to: dest)) != nil {
            openMainApp(imageFilePath: dest.path)
        } else {
            completeAndReturn()
        }
    }

    private func saveImageToAppGroup(_ image: UIImage) {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
            let data = image.jpegData(compressionQuality: 0.9)
        else {
            completeAndReturn()
            return
        }
        let dest = container.appendingPathComponent("pendingShareImage.jpg")
        do {
            try data.write(to: dest)
            openMainApp(imageFilePath: dest.path)
        } catch {
            completeAndReturn()
        }
    }

    // MARK: - Open main app

    private func openMainApp(webURL: URL) {
        guard let encoded = webURL.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "lijster://import?url=\(encoded)")
        else {
            completeAndReturn()
            return
        }
        extensionContext?.open(appURL) { [weak self] _ in
            self?.completeAndReturn()
        }
    }

    private func openMainApp(imageFilePath: String) {
        guard let encoded = imageFilePath
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "lijster://import?file=\(encoded)")
        else {
            completeAndReturn()
            return
        }
        extensionContext?.open(appURL) { [weak self] _ in
            self?.completeAndReturn()
        }
    }

    // MARK: - Dismissal

    private func completeAndReturn() {
        extensionContext?.completeRequest(returningItems: [])
    }
}
