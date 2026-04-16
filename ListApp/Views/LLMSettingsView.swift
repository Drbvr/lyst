import SwiftUI
import Core

/// Settings for AI note generation — personal LLM configuration.
struct LLMSettingsView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Picker("Processing", selection: $appState.llmSettings.processingMode) {
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Developer Mode", isOn: $appState.llmSettings.developerMode)
            } header: {
                Text("AI Processing")
            } footer: {
                modeFooter(for: appState.llmSettings.processingMode)
            }

            Section {
                TextEditor(text: $appState.llmSettings.customSystemPromptInstructions)
                    .frame(minHeight: 100)
            } header: {
                Text("Custom Instructions")
            } footer: {
                Text("Appended to every system prompt. Use this to set language, tone, or extra rules for note generation.")
            }

            if appState.llmSettings.processingMode == .personalLLM {
                Section {
                    LabeledContent("Base URL") {
                        TextField("http://192.168.1.1:8000", text: $appState.llmSettings.baseURL)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.URL)
                            #endif
                            .autocorrectionDisabled()
                            .noAutocapitalization()
                    }
                    LabeledContent("Model") {
                        TextField("e.g. qwen3-14b", text: $appState.llmSettings.model)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .noAutocapitalization()
                    }
                    LabeledContent("API Key") {
                        SecureField("Optional", text: $appState.llmSettings.apiKey)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Enable Thinking", isOn: $appState.llmSettings.useThinking)
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("The server must expose an OpenAI-compatible /v1/chat/completions endpoint. Lyst will wait up to 2 minutes for the server to start before giving up.")
                }

                Section {
                    Picker("Image Input", selection: $appState.llmSettings.imageProcessingMode) {
                        ForEach(ImageProcessingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Image Handling")
                } footer: {
                    switch appState.llmSettings.imageProcessingMode {
                    case .base64:
                        Text("The image is encoded and sent directly to the LLM. Requires a vision-capable model.")
                    case .ocr:
                        Text("Text is extracted from the image on-device first, then sent to the LLM as plain text.")
                    }
                }

                Section("Connection") {
                    Button("Test Connection") {
                        Task { await testConnection(settings: appState.llmSettings) }
                    }
                    .disabled(appState.llmSettings.baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("AI Note Generation")
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

    private func testConnection(settings: LLMSettings) async {
        let service = LLMService(settings: settings)
        let isReady = await service.checkHealthPublic()

        connectionAlertTitle   = isReady ? "Connected" : "Not Reachable"
        connectionAlertMessage = isReady
            ? "The server responded successfully."
            : "Could not reach \(settings.baseURL)/health. Check the URL and make sure the server is running."
        showConnectionAlert = true
    }

    @ViewBuilder
    private func modeFooter(for mode: ProcessingMode) -> some View {
        switch mode {
        case .onDevice:
            Text("Uses Apple Intelligence on-device models. Requires iOS 26+ with Apple Intelligence enabled.")
        case .personalLLM:
            Text("Connect to your own OpenAI-compatible server (e.g. Ollama, LM Studio, or a custom endpoint).")
        }
    }
}
