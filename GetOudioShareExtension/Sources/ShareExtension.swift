import AppKit
import Foundation
import GetOudioCore
import UniformTypeIdentifiers

final class ShareExtension: NSViewController {
    private var hasStarted = false

    override func loadView() {
        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.startAnimation(nil)

        let label = NSTextField(labelWithString: "正在发送到 Get Oudio…")
        label.alignment = .center

        let stackView = NSStackView(views: [progressIndicator, label])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 280),
            container.heightAnchor.constraint(equalToConstant: 120),
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container

        Task { @MainActor in
            guard !hasStarted, let context = extensionContext else {
                return
            }
            hasStarted = true
            process(context)
        }
    }

    private func process(_ context: NSExtensionContext) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for item in context.inputItems.compactMap({ $0 as? NSExtensionItem }) {
            if let text = item.attributedContentText?.string {
                urls.append(contentsOf: Self.urls(in: text))
            }

            for provider in item.attachments ?? [] {
                DiagnosticLog.append(
                    "[ShareExtension] registered types: \(provider.registeredTypeIdentifiers.joined(separator: ", "))"
                )

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                        let loadedURLs = Self.urls(from: item)
                        if !loadedURLs.isEmpty {
                            lock.lock()
                            urls.append(contentsOf: loadedURLs)
                            lock.unlock()
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                        let loadedURLs = Self.urls(from: item)
                        if !loadedURLs.isEmpty {
                            lock.lock()
                            urls.append(contentsOf: loadedURLs)
                            lock.unlock()
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            DiagnosticLog.append(
                "[ShareExtension] extracted URLs: \(urls.map(\.absoluteString).joined(separator: ", "))"
            )
            self.enqueue(urls)
            self.openContainingApp()
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func enqueue(_ urls: [URL]) {
        let supportedURLs = AppleMusicShareURLParser.supportedURLs(from: urls)
        let jobs = supportedURLs
            .map { JobRequest(fileURL: $0, category: .appleMusic, operation: .appleMusicDownload(nil), source: .shareExtension) }

        do {
            if !jobs.isEmpty {
                let intake = try JobIntake()
                try intake.enqueue(jobs, launchSource: .shareExtension)
            }
            if !urls.isEmpty, supportedURLs.isEmpty {
                let eventQueue = try ShareEventQueue()
                try eventQueue.enqueue([
                    ShareEvent(kind: .unsupportedDownloadSource, urls: urls)
                ])
            }
        } catch {
            NSLog("Get Oudio Share extension failed to enqueue jobs: \(error.localizedDescription)")
        }
    }

    private func openContainingApp() {
        LaunchMarkerStore().mark(.shareExtension)

        guard let runQueuedURL = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }
        NSWorkspace.shared.open(runQueuedURL)
    }

    private static func urls(from item: NSSecureCoding?) -> [URL] {
        if let url = item as? URL {
            return [url]
        }

        if let string = item as? String {
            return urls(in: string)
        }

        if let attributedString = item as? NSAttributedString {
            return urls(in: attributedString.string)
        }

        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return urls(in: string)
        }

        return []
    }

    private static func urls(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }
}
