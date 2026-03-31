import SwiftUI
import Core

/// Root SwiftUI view for the share extension.
/// Renders the appropriate child view based on `ShareViewModel.step`.
struct ShareRootView: View {

    @State var viewModel: ShareViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add to Lyst")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.dismiss() }
                    }
                }
                .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                    Button("OK", role: .cancel) {}
                    if case .decision = viewModel.step {
                        Button("Create Manually") { viewModel.useManualEntry() }
                    }
                } message: {
                    Text(viewModel.alertMessage)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .loadingContent:
            loadingView(message: viewModel.processingStatus)

        case .decision:
            AIDecisionView(viewModel: viewModel)

        case .aiProcessing:
            AIProcessingView(viewModel: viewModel)

        case .preview:
            NotePreviewView(viewModel: viewModel)

        case .manualForm:
            ManualNoteView(viewModel: viewModel)

        case .saving:
            loadingView(message: "Saving…")

        case .done:
            doneView

        case .error(let message):
            errorView(message: message)
        }
    }

    private func loadingView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Note saved to Lyst!")
                .font(.title3.weight(.semibold))
            Button("Done") { viewModel.dismissWithDone() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Dismiss") { viewModel.dismiss() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
