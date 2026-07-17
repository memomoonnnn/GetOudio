import Foundation

public final class NCMConversionService {
    private let runner: ProcessRunner
    private let componentManager: BundledComponentManager
    private let settingsStore: SettingsStore

    public init(
        runner: ProcessRunner = ProcessRunner(),
        componentManager: BundledComponentManager = BundledComponentManager(),
        settingsStore: SettingsStore
    ) {
        self.runner = runner
        self.componentManager = componentManager
        self.settingsStore = settingsStore
    }

    public convenience init(container: SharedContainer) {
        self.init(settingsStore: SettingsStore(container: container))
    }

    public func convert(
        _ jobs: [JobRequest],
        progressHandler: (@Sendable (JobRequest, JobProgressPhase, String?) -> Void)? = nil
    ) async -> ConversionSummary {
        let ncmJobs = jobs.filter { $0.category == .ncm }
        guard !ncmJobs.isEmpty else {
            return ConversionSummary(successCount: 0, failureCount: 0, messages: ["没有 NCM 文件需要转换。"])
        }

        var successCount = 0
        var failureCount = 0
        var messages: [String] = []

        do {
            let executableURL = try componentManager.executableURL(for: .ncmdump)

            for job in ncmJobs {
                progressHandler?(job, .running, nil)

                let access = job.startAccessingSecurityScopedResources()
                defer { access.stopAccessing() }

                let customOutputAccess: SecurityScopedDirectoryAccess?
                let outputDirectory: URL
                if settingsStore.ncmOutputMode == "customDirectory" {
                    let outputAccess = try settingsStore.ncmCustomOutputAccess()
                    customOutputAccess = outputAccess
                    outputDirectory = outputAccess.directoryURL
                } else {
                    customOutputAccess = nil
                    outputDirectory = access.outputDirectoryURL
                }
                defer { customOutputAccess?.stopAccessing() }
                DiagnosticLog.append(
                    "[NCM-DIAG] access file=\(access.fileURL.path) scopeDirectory=\(access.directoryURL?.path ?? "<none>") activeDirectoryScope=\(access.hasActiveDirectorySecurityScope) activeScopes=\(access.activeSecurityScopedResourceCount) output=\(outputDirectory.path)"
                )
                try DirectoryAccess.ensureWritableDirectory(outputDirectory)
                DiagnosticLog.append(
                    "[NCM-DIAG] output preflight \(outputDirectoryDiagnostic(for: outputDirectory, inputURL: access.fileURL))"
                )
                let outputBefore = outputCandidateStamps(in: outputDirectory, matching: access.fileURL)

                let result = try await runner.run(
                    executablePath: executableURL.path,
                    arguments: ["-o", outputDirectory.path, access.fileURL.path]
                )
                DiagnosticLog.append(
                    "[NCM-DIAG] ncmdump exit=\(result.exitCode) stdout=\(diagnosticExcerpt(result.standardOutput)) stderr=\(diagnosticExcerpt(result.standardError))"
                )
                DiagnosticLog.append(
                    "[NCM-DIAG] output postflight \(outputDirectoryDiagnostic(for: outputDirectory, inputURL: access.fileURL))"
                )

                if result.succeeded {
                    guard outputCandidateStamps(in: outputDirectory, matching: access.fileURL) != outputBefore else {
                        let message = "NCM 转换未生成输出文件：\(access.fileURL.lastPathComponent)"
                        failureCount += 1
                        messages.append(message)
                        progressHandler?(job, .failed, message)
                        continue
                    }
                    successCount += 1
                    progressHandler?(job, .succeeded, nil)
                } else {
                    failureCount += 1
                    let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
                    messages.append(message)
                    progressHandler?(job, .failed, message)
                }
            }

            return ConversionSummary(successCount: successCount, failureCount: failureCount, messages: messages)
        } catch {
            ncmJobs.forEach { progressHandler?($0, .failed, error.localizedDescription) }
            return ConversionSummary(successCount: successCount, failureCount: ncmJobs.count - successCount, messages: [error.localizedDescription])
        }
    }

    private func outputDirectoryDiagnostic(for directoryURL: URL, inputURL: URL) -> String {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
        let attributes = (try? fileManager.attributesOfItem(atPath: directoryURL.path)) ?? [:]
        let permissions = (attributes[.posixPermissions] as? Int16).map { String($0, radix: 8) } ?? "?"
        let owner = attributes[.ownerAccountName] as? String ?? "?"
        let candidates = outputCandidates(in: directoryURL, matching: inputURL)

        return "path=\(directoryURL.path) exists=\(exists) isDirectory=\(isDirectory.boolValue) writable=\(fileManager.isWritableFile(atPath: directoryURL.path)) permissions=\(permissions) owner=\(owner) candidates=\(candidates)"
    }

    private func outputCandidates(in directoryURL: URL, matching inputURL: URL) -> String {
        let entries = outputCandidateStamps(in: directoryURL, matching: inputURL)
        guard !entries.isEmpty else { return "<none>" }

        return entries
            .sorted { $0.name < $1.name }
            .map { entry in
                let size = entry.size.map(String.init) ?? "?"
                let modified = entry.modified.map(ISO8601DateFormatter().string(from:)) ?? "?"
                return "\(entry.name){size=\(size),modified=\(modified)}"
            }
            .joined(separator: ", ")
    }

    private func outputCandidateStamps(in directoryURL: URL, matching inputURL: URL) -> Set<OutputCandidateStamp> {
        let inputStem = inputURL.deletingPathExtension().lastPathComponent
        let audioExtensions: Set<String> = ["aac", "aiff", "alac", "flac", "m4a", "mp3", "ogg", "opus", "wav"]

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            return Set(urls.compactMap { url -> OutputCandidateStamp? in
                guard url.deletingPathExtension().lastPathComponent == inputStem,
                      audioExtensions.contains(url.pathExtension.lowercased()),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }

                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return OutputCandidateStamp(
                    name: url.lastPathComponent,
                    size: values?.fileSize,
                    modified: values?.contentModificationDate
                )
            })
        } catch {
            return []
        }
    }

    private struct OutputCandidateStamp: Hashable {
        let name: String
        let size: Int?
        let modified: Date?
    }

    private func diagnosticExcerpt(_ value: String, limit: Int = 800) -> String {
        guard !value.isEmpty else { return "<empty>" }

        let normalized = value
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return "\(normalized.prefix(limit))…"
    }
}
