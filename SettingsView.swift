import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "192.168.1.192:11434"
    @AppStorage("model") private var model = "qwen3.8-vision"
    @Environment(\.dismiss) private var dismiss

    @State private var testResult: String?
    @State private var testing = false

    private let client = OllamaClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("Ollama Server") {
                    TextField("Host (e.g. 192.168.1.192:11434)", text: $serverURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing)

                    if let testResult {
                        Label(testResult, systemImage: testResult.hasPrefix("OK") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("OK") ? .green : .red)
                    }
                }

                Section("Default Model") {
                    TextField("Model name", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("Your iPhone and the Ollama server must be on the same Wi-Fi network. The server must be reachable at the address above (Ollama listens on all interfaces by default).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        Task {
            do {
                let models = try await client.listModels(server: serverURL)
                await MainActor.run {
                    testResult = "OK — \(models.count) model(s) found"
                    if !models.contains(model), let first = models.first {
                        model = first
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run { testing = false }
        }
    }
}
