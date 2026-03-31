import SwiftUI
import Core

/// Asks the user whether to use AI to create the note.
/// Displays a summary of what was shared and an optional extra-text field.
struct AIDecisionView: View {

    @Bindable var viewModel: ShareViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Shared content summary
                sharedContentCard

                // User extra text input
                VStack(alignment: .leading, spacing: 8) {
                    Label("Additional Context (optional)", systemImage: "text.bubble")
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $viewModel.additionalText)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await viewModel.startAIGeneration() }
                    } label: {
                        Label("Use AI to Create Note", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    Button {
                        viewModel.useManualEntry()
                    } label: {
                        Label("Create Manually", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var sharedContentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sharing", systemImage: contentIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let url = viewModel.sharedURL {
                Text(url)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if !viewModel.sharedImages.isEmpty {
                HStack(spacing: 8) {
                    ForEach(viewModel.sharedImages.prefix(3).indices, id: \.self) { i in
                        Image(uiImage: viewModel.sharedImages[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contentIcon: String {
        if viewModel.sharedURL != nil { return "link" }
        return "photo"
    }
}
