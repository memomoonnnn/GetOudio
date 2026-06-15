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
                    submitVerificationCode()
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
        status = "正在后台启动 Colima 并运行 wrapper 镜像。收到 Apple 验证码后，在此输入并点击提交验证码。"
        let summary = await downloadService.initializeWrapper(username: username, password: password, verificationCode: verificationCode)
        isInitializing = false

        if summary.failureCount == 0 {
            status = "初始化完成"
        } else {
            status = summary.messages.first ?? "初始化失败"
        }
    }

    private func submitVerificationCode() {
        let summary = downloadService.submitWrapperVerificationCode(verificationCode)
        if summary.failureCount == 0 {
            status = "验证码已写入 wrapper 运行目录"
        } else {
            status = summary.messages.first ?? "验证码写入失败"
        }
    }
}
