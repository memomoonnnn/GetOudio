import Foundation

public enum AppleMusicShareURLParser {
    public static func supportedURL(from url: URL) -> URL? {
        let value = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if url.scheme?.lowercased() == "music" {
            return url
        }

        let lowercased = value.lowercased()
        guard lowercased.contains("apple"), lowercased.contains("music") else {
            return nil
        }
        return url
    }

    public static func supportedURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var accepted: [URL] = []
        for url in urls {
            guard let supported = supportedURL(from: url) else { continue }
            let key = supported.absoluteString
            guard seen.insert(key).inserted else { continue }
            accepted.append(supported)
        }
        return accepted
    }
}
