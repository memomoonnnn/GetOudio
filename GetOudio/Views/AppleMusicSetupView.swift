import GetOudioCore
import SwiftUI

struct AppleMusicSetupView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var status = "尚未初始化"
    @State private var isInitializing = false
    private let keychain = KeychainService()
    private let downloadService = AppleMusicDownloadService()
    private let appleMusicAgentLauncher = AppleMusicRuntimeAgentLauncher.shared

    var body: some View {
        Form {
            Section("账号") {
                TextField("Apple ID", text: $username)
                SecureField("密码", text: $password)
            }

            Section("双重认证") {
                TextField("验证码", text: $verificationCode)
                Text(status)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    saveCredentials()
                } label: {
                    Label("保存凭据", systemImage: "key")
                }

                Button {
                    Task { await initializeWrapper() }
                } label: {
                    Label("开始初始化", systemImage: "play")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInitializing || username.isEmpty || password.isEmpty)

                Button {
                    Task { await submitVerificationCode() }
                } label: {
                    Label("提交验证码", systemImage: "number")
                }
                .disabled(verificationCode.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(minWidth: 620, minHeight: 420)
    }

    private func saveCredentials() {
        do {
            try keychain.save(username, account: "apple-id")
            try keychain.save(password, account: "apple-id-password")
            status = "凭据已保存到 Keychain"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    private func initializeWrapper() async {
        isInitializing = true
        status = "正在启动 Apple Music Runtime Agent。收到 Apple 验证码后，在此输入并点击提交验证码。"
        do {
            try await appleMusicAgentLauncher.ensureRunning()
        } catch {
            status = "启动 Runtime Agent 失败：\(error.localizedDescription)"
            isInitializing = false
            return
        }
        let summary = await downloadService.initializeWrapper(
            username: username,
            password: password,
            verificationCode: nil,
            useSystemProxy: false
        )
        isInitializing = false

        if summary.failureCount == 0 {
            status = summary.messages.first ?? "登录容器已启动"
        } else {
            status = summary.messages.first ?? "初始化失败"
        }
    }

    private func submitVerificationCode() async {
        do {
            try await appleMusicAgentLauncher.ensureRunning()
        } catch {
            status = "启动 Runtime Agent 失败：\(error.localizedDescription)"
            return
        }
        let summary = await downloadService.submitWrapperVerificationCode(verificationCode)
        if summary.failureCount == 0 {
            status = "验证码已写入 wrapper 运行目录"
        } else {
            status = summary.messages.first ?? "验证码写入失败"
        }
    }
}
