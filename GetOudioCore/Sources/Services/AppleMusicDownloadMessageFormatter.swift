import Foundation

public enum AppleMusicDownloadMessageFormatter {
    public static func coreMessage(from output: String, maxLines: Int = 12) -> String {
        let lines = coreLines(from: output, maxLines: maxLines)
        return lines.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) : lines.joined(separator: "\n")
    }

    public static func displayMessage(from output: String) -> String? {
        coreLines(from: output, maxLines: 6).first { line in
            line.localizedCaseInsensitiveContains("failed")
                || line.localizedCaseInsensitiveContains("error")
                || line.localizedCaseInsensitiveContains("错误")
                || line.localizedCaseInsensitiveContains("失败")
        } ?? coreLines(from: output, maxLines: 1).first
    }

    public static func coreLines(from output: String, maxLines: Int = 12) -> [String] {
        let lines = output
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { stripProgressPrefixIfNeeded(compact(String($0))) }
            .filter { !$0.isEmpty }
            .filter { !isProgressLine($0) }

        var selected: [String] = []
        for line in lines {
            if isCoreLine(line), selected.last != line {
                selected.append(line)
            }
        }

        if selected.isEmpty {
            selected = lines.filter { selectedLine in
                !selectedLine.localizedCaseInsensitiveContains("MediaUserToken not set")
            }
        }

        return Array(selected.prefix(maxLines))
    }

    private static func compact(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isProgressLine(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("Downloading...")
            || line.localizedCaseInsensitiveContains("Decrypting...")
            || line == "Downloaded"
            || line == "Decrypted"
    }

    private static func isCoreLine(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("Failed")
            || line.localizedCaseInsensitiveContains("Error")
            || line.localizedCaseInsensitiveContains("错误")
            || line.localizedCaseInsensitiveContains("失败")
            || line.localizedCaseInsensitiveContains("Completed:")
            || line.localizedCaseInsensitiveContains("Track ")
            || line.localizedCaseInsensitiveContains("Queue ")
    }

    private static func stripProgressPrefixIfNeeded(_ line: String) -> String {
        guard isProgressLine(line),
              let range = firstCoreKeywordRange(in: line)
        else {
            return line
        }
        return compact(String(line[range.lowerBound...]))
    }

    private static func firstCoreKeywordRange(in line: String) -> Range<String.Index>? {
        ["Failed", "Error", "错误", "失败"]
            .compactMap { line.range(of: $0, options: .caseInsensitive) }
            .min { first, second in
                first.lowerBound < second.lowerBound
            }
    }
}
