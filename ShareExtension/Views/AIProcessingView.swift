import SwiftUI

/// Displays LLM warm-up and generation progress.
struct AIProcessingView: View {

    @Bindable var viewModel: ShareViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated icon
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.indigo)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("Generating Note")
                    .font(.title3.weight(.semibold))

                Text(viewModel.processingStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: viewModel.processingStatus)
            }

            ProgressView()
                .scaleEffect(1.2)

            Spacer()

            Button("Cancel") { viewModel.dismiss() }
                .buttonStyle(.bordered)
                .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
