import SwiftUI
import Core

struct ChatMessageRow: View {
    let message: ChatMessage
    var onRespondToApproval: ((_ id: String, _ allow: Bool) -> Void)? = nil
    var onUpdateDraft: ((_ messageId: UUID, _ draftId: UUID, _ mutate: (inout NoteEdit) -> Void) -> Void)? = nil
    var onToggleDraftIncluded: ((_ messageId: UUID, _ draftId: UUID) -> Void)? = nil
    var onRegenerateDrafts: ((_ messageId: UUID, _ feedback: String) -> Void)? = nil
    var onSaveDrafts: ((_ messageId: UUID) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var expandedToolCall: String? = nil

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            bubbleView
            if !message.toolCalls.isEmpty {
                toolCallsView
            }
            if let bundle = message.draftBundle {
                DraftCard(
                    bundle: bundle,
                    onUpdate: { draftId, mutate in
                        onUpdateDraft?(message.id, draftId, mutate)
                    },
                    onToggleIncluded: { draftId in
                        onToggleDraftIncluded?(message.id, draftId)
                    },
                    onRegenerate: { feedback in
                        onRegenerateDrafts?(message.id, feedback)
                    },
                    onSave: {
                        onSaveDrafts?(message.id)
                    }
                )
            }
            if !message.citations.isEmpty {
                citationsView
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 12)
    }

    // MARK: - Bubble

    @ViewBuilder
    private var bubbleView: some View {
        if message.role == .user {
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
        } else if message.role == .assistant {
            if message.content.isEmpty && message.toolCalls.isEmpty {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .frame(width: 6, height: 6)
                            .opacity(0.4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else if !message.content.isEmpty {
                Text(markdownAttributed(message.content))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
            }
        }
    }

    /// Parses `content` as inline markdown. Falls back to a plain string on error
    /// so partially-streamed deltas never fail to render.
    private func markdownAttributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }

    // MARK: - Tool call cards

    @ViewBuilder
    private var toolCallsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.toolCalls) { call in
                if call.approvalState == .pending {
                    ApprovalCard(call: call) { allow in
                        onRespondToApproval?(call.id, allow)
                    }
                } else {
                    ToolCallCard(call: call, isExpanded: expandedToolCall == call.id) {
                        expandedToolCall = expandedToolCall == call.id ? nil : call.id
                    }
                }
            }
        }
    }

    // MARK: - Citations

    @ViewBuilder
    private var citationsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(message.citations, id: \.self) { ref in
                    CitationChip(ref: ref)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Approval card

private struct ApprovalCard: View {
    let call: ToolCallRecord
    let onRespond: (Bool) -> Void

    private var title: String {
        switch call.name {
        case "web_fetch":   return "Fetch URL?"
        default:            return "Run \(call.name)?"
        }
    }

    private var icon: String {
        switch call.name {
        case "web_fetch":   return "link"
        default:            return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let summary = call.approvalSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    onRespond(false)
                } label: {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onRespond(true)
                } label: {
                    Text("Allow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Tool call card

private struct ToolCallCard: View {
    let call: ToolCallRecord
    let isExpanded: Bool
    let onTap: () -> Void

    private var statusIcon: String {
        if call.isRunning { return "gear" }
        if call.approvalState == .denied { return "hand.raised" }
        if call.errorMessage != nil { return "xmark.circle" }
        return "checkmark.circle"
    }

    private var statusColor: Color {
        if call.isRunning { return .orange }
        if call.approvalState == .denied { return .secondary }
        if call.errorMessage != nil { return .red }
        return .green
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.rotate, isActive: call.isRunning)
                Text(call.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)

        if isExpanded, let result = call.resultJSON {
            ScrollView {
                Text(result)
                    .font(.caption.monospaced())
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
        }
    }
}
