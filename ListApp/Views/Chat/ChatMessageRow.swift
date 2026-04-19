import SwiftUI
import Core

struct ChatMessageRow: View {
    let message: ChatMessage
    @Environment(AppState.self) private var appState
    @State private var expandedToolCall: String? = nil

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            bubbleView
            if !message.toolCalls.isEmpty {
                toolCallsView
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
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .frame(width: 6, height: 6)
                            .opacity(0.4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Tool call cards

    @ViewBuilder
    private var toolCallsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.toolCalls) { call in
                ToolCallCard(call: call, isExpanded: expandedToolCall == call.id) {
                    expandedToolCall = expandedToolCall == call.id ? nil : call.id
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

// MARK: - Tool call card

private struct ToolCallCard: View {
    let call: ToolCallRecord
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: call.isRunning ? "gear" : (call.errorMessage != nil ? "xmark.circle" : "checkmark.circle"))
                    .foregroundStyle(call.isRunning ? Color.orange : (call.errorMessage != nil ? .red : .green))
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
