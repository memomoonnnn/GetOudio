import AppKit
import Foundation
import GetOudioCore
import UniformTypeIdentifiers

final class ShareExtension: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for item in context.inputItems.compactMap({ $0 as? NSExtensionItem }) {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                        if let url = Self.url(from: item) {
                            lock.lock()
                            urls.append(url)
                            lock.unlock()
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                        if let url = Self.url(from: item) {
                            lock.lock()
                            urls.append(url)
                            lock.unlock()
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            self.enqueue(urls)
            self.openContainingApp()
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func enqueue(_ urls: [URL]) {
        let jobs = urls
            .filter { FileCategory.classify($0) == .appleMusic }
            .map { JobRequest(fileURL: $0, category: .appleMusic, operation: .appleMusicDownload(nil), source: .shareExtension) }

        guard !jobs.isEmpty else {
            return
        }

        do {
            let queue = try JobQueue()
            try queue.enqueue(jobs)
        } catch {
            NSLog("Get Oudio Share extension failed to enqueue jobs: \(error.localizedDescription)")
        }
    }

    private func openContainingApp() {
        guard let url = URL(string: "\(AppConstants.appURLScheme)://run-queued") else {
            return
        }

        // Signal launch source before opening app
        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) {
            sharedDefaults.set(LaunchSource.shareExtension.rawValue, forKey: AppConstants.extensionLaunchSourceKey)
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: AppConstants.extensionLaunchTimestampKey)
            sharedDefaults.synchronize()
        }

        NSWorkspace.shared.open(url)
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }
}

