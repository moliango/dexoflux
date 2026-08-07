import Social
import UIKit
import UniformTypeIdentifiers

/// Share sheet: send a topic URL / text into DexoFlux via `dexo://` deep link.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await processShare() }
    }

    private func processShare() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var collectedText = ""
        var collectedURL: URL?

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURL(provider) {
                        collectedURL = url
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await loadText(provider) {
                        collectedText += text
                        collectedText += "\n"
                    }
                }
            }
        }

        let raw = collectedURL?.absoluteString ?? collectedText
        let deepLink = makeDeepLink(from: raw) ?? URL(string: "dexo://read-later")!
        _ = openURL(deepLink)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func makeDeepLink(from raw: String) -> URL? {
        // Prefer /t/{id}/{floor?} → dexo://topic/{id}/{floor}
        let patterns = [
            #"/t/(\d+)(?:/(\d+))?"#,
            #"/t/[^/]+/(\d+)(?:/(\d+))?"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               match.numberOfRanges >= 2,
               let idRange = Range(match.range(at: 1), in: raw),
               let topicId = Int(raw[idRange]), topicId > 0 {
                var path = "dexo://topic/\(topicId)"
                if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound,
                   let postRange = Range(match.range(at: 2), in: raw),
                   let postNumber = Int(raw[postRange]), postNumber > 0 {
                    path += "/\(postNumber)"
                }
                return URL(string: path)
            }
        }
        // Non-topic share → open read-later landing
        if raw.contains("http") {
            return URL(string: "dexo://read-later")
        }
        return nil
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let text = item as? String {
                    cont.resume(returning: text)
                } else if let data = item as? Data {
                    cont.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    @discardableResult
    private func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            // iOS 18+ / extension open via selector
            if current.responds(to: Selector(("openURL:options:completionHandler:"))) {
                current.perform(Selector(("openURL:")), with: url)
                return true
            }
            responder = current.next
        }
        // Fallback: extensionContext open (works for some hosts)
        var opened = false
        let sem = DispatchSemaphore(value: 0)
        extensionContext?.open(url) { success in
            opened = success
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.5)
        return opened
    }
}
