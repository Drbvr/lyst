import SwiftUI
import Core

/// Settings for AI note generation — personal LLM configuration.
struct LLMSettingsView: View {

    @State private var settings: LLMSettings = LLMSettings.load()

    var body: some View {
        Form {
            Section {
                Picker("Processing", selection: $settings.processingMode) {
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("AI Processing")
            } footer: {
                modeFooter
            }

            if settings.processingMode == .personalLLM {
                Section {
                    LabeledContent("Base URL") {
                        TextField("http://192.168.1.1:8000", text: $settings.baseURL)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent("Model") {
                        TextField("e.g. qwen3-14b", text: $settings.model)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent("API Key") {
                        SecureField("Optional", text: $settings.apiKey)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Enable Thinking", isOn: $settings.useThinking)
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("The server must expose an OpenAI-compatible /v1/chat/completions endpoint. " +
                         "Lyst will wait up to 2 minutes for the server to start before giving up.")
                }

                Section("Connection") {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(settings.baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("AI Note Generation")
        .onChange(of: settings.processingMode) { _, _ in settings.save() }
        .onChange(of: settings.baseURL)        { _, _ in settings.save() }
        .onChange(of: settings.model)          { _, _ in settings.save() }
        .onChange(of: settings.apiKey)         { _, _ in settings.save() }
        .onChange(of: settings.useThinking)    { _, _ in settings.save() }
        .alert(connectionAlertTitle, isPresented: $showConnectionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionAlertMessage)
        }
    }

    // MARK: - Connection test

    @State private var showConnectionAlert = false
    @State private var connectionAlertTitle = ""
    @State private var connectionAlertMessage = ""

    private func testConnection() async {
        let service = LLMService(settings: settings)
        let isReady = await service.checkHealthPublic()

        connectionAlertTitle   = isReady ? "Connected" : "Not Reachable"
        connectionAlertMessage = isReady
            ? "The server responded successfully."
            : "Could not reach \(settings.baseURL)/health. Check the URL and make sure the server is running."
        showConnectionAlert = true
    }

    @ViewBuilder
    private var modeFooter: some View {
        switch settings.processingMode {
        case .onDevice:
            Text("Uses Apple Intelligence on-device models. Requires iOS 18.1+ with Apple Intelligence enabled.")
        case .personalLLM:
            Text("Connect to your own OpenAI-compatible server (e.g. Ollama, LM Studio, or a custom endpoint).")
        }
    }
}
