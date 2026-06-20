import SwiftUI

struct LoginView: View {
    private let onSuccess: (() -> Void)?

    init(onSuccess: (() -> Void)? = nil) {
        self.onSuccess = onSuccess
    }

    @State private var email      = ""
    @State private var password   = ""
    @State private var serverURL  = NetworkClient.shared.serverURL
    @State private var isRegister = false
    @State private var isWorking  = false
    @State private var errorMsg   = ""
    @State private var showServer = false

    private var auth  = AuthStore.shared
    private var net   = NetworkClient.shared

    var body: some View {
        VStack(spacing: 28) {
                // Лого / заголовок
                VStack(spacing: 6) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.primary)
                    Text("EditHub")
                        .font(.system(size: 28, weight: .semibold))
                    Text(isRegister ? "Create account" : "Sign in")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Форма
                VStack(spacing: 12) {
                    field("envelope", placeholder: "Email", text: $email)
                        .textContentType(.emailAddress)

                    field("lock", placeholder: "Password", text: $password, secure: true)
                        .textContentType(isRegister ? .newPassword : .password)

                    // Кнопка действия
                    Button(action: submit) {
                        Group {
                            if isWorking {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text(isRegister ? "Create account" : "Sign in")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isWorking || email.isEmpty || password.isEmpty)

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 300)

                // Переключатель режима
                Button(isRegister ? "Already have an account? Sign in" : "No account? Create one") {
                    withAnimation(.snappy) {
                        isRegister.toggle()
                        errorMsg = ""
                    }
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)

                // Сервер URL (скрытые настройки)
                VStack(spacing: 8) {
                    Button {
                        withAnimation { showServer.toggle() }
                    } label: {
                        Label("Server", systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)

                    if showServer {
                        TextField("http://your-server:3000", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 260)
                            .onChange(of: serverURL) { _, v in
                                net.serverURL = v
                            }
                    }
                }
            }
        .padding(40)
        .frame(width: 320)
    }

    // MARK: - Actions

    private func submit() {
        guard !isWorking else { return }
        isWorking = true
        errorMsg  = ""

        Task {
            do {
                let response: AuthResponse
                if isRegister {
                    response = try await net.register(
                        email: email.lowercased().trimmingCharacters(in: .whitespaces),
                        password: password,
                        workspaceName: "EditHub"
                    )
                } else {
                    response = try await net.login(
                        email: email.lowercased().trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                }
                auth.apply(response: response)
                onSuccess?()
            } catch {
                errorMsg = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: - Field builder

    @ViewBuilder
    private func field(
        _ icon: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            if secure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .onSubmit { submit() }
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .onSubmit { submit() }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}
