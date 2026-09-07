import SwiftUI

// MARK: - Claude-style palette

extension Color {
    static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)      // coral
    static let claudeBackground = Color(red: 0.98, green: 0.97, blue: 0.95)   // warm cream
    static let claudeUserBubble = Color(red: 0.94, green: 0.91, blue: 0.86)   // soft beige
    static let claudeInk = Color(red: 0.16, green: 0.14, blue: 0.12)          // near-black warm
}

struct ChatView: View {
    @EnvironmentObject var store: ConversationStore
    @AppStorage("serverURL") private var serverURL = "192.168.1.192:11434"
    @AppStorage("model") private var model = "qwen3.8-vision"

    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var models: [String] = []
    @State private var showModelPicker = false
    @FocusState private var inputFocused: Bool

    private let client = OllamaClient()

    var body: some View {
        VStack(spacing: 0) {
            header
            messages
            if let errorMessage {
                errorBanner(errorMessage)
            }
            composer
        }
        .background(Color.claudeBackground.ignoresSafeArea())
        .navigationTitle(store.selected?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showModelPicker = true
                } label: {
                    Label(model, systemImage: "cpu")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(models: $models, selected: $model, serverURL: serverURL, client: client)
        }
        .task {
            await refreshModels()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(Color.claudeAccent)
            Text("Local AI")
                .font(.headline)
                .foregroundStyle(Color.claudeInk)
            Spacer()
            if isStreaming {
                ProgressView()
                    .tint(Color.claudeAccent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.claudeBackground)
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if (store.selected?.messages.isEmpty ?? true) {
                        emptyState
                    }
                    ForEach(store.selected?.messages ?? []) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: store.selected?.messages.last?.content) { _ in
                if let last = store.selected?.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.claudeAccent.opacity(0.7))
            Text("How can I help you today?")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.claudeInk)
            Text("Running locally on \(serverURL)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.claudeInk.opacity(0.12), lineWidth: 1)
                )
                .focused($inputFocused)

            Button {
                send()
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        (isStreaming || !draft.trimmingCharacters(in: .whitespaces).isEmpty)
                            ? Color.claudeAccent
                            : Color.claudeInk.opacity(0.25),
                        in: Circle()
                    )
            }
            .disabled(!isStreaming && draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.claudeBackground)
    }

    // MARK: Actions

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, var conversation = store.selected else { return }

        draft = ""
        inputFocused = false

        conversation.messages.append(ChatMessage(role: .user, content: text))
        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(32))
        }
        conversation.model = model
        store.update(conversation)

        let placeholder = ChatMessage(role: .assistant, content: "")
        conversation.messages.append(placeholder)
        store.update(conversation)

        isStreaming = true
        errorMessage = nil

        let history = conversation.messages
        Task {
            var streamed = ""
            do {
                for try await chunk in client.streamChat(server: serverURL, model: model, messages: history) {
                    streamed += chunk
                    let snapshot = streamed
                    await MainActor.run {
                        if var current = store.selected,
                           let last = current.messages.indices.last,
                           current.messages[last].role == .assistant {
                            current.messages[last].content = snapshot
                            store.update(current)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    if var current = store.selected,
                       let last = current.messages.indices.last,
                       current.messages[last].role == .assistant,
                       current.messages[last].content.isEmpty {
                        current.messages.removeLast()
                        store.update(current)
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
            }
        }
    }

    private func refreshModels() async {
        do {
            models = try await client.listModels(server: serverURL)
            if !models.contains(model), let first = models.first {
                model = first
            }
        } catch {
            // Server unreachable — user can fix the URL in Settings.
        }
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(Color.claudeInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.claudeUserBubble, in: RoundedRectangle(cornerRadius: 18))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.footnote)
                        .foregroundStyle(Color.claudeAccent)
                        .padding(.top, 4)
                    Text(message.content.isEmpty ? "…" : message.content)
                        .font(.body)
                        .foregroundStyle(Color.claudeInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Model picker

struct ModelPickerView: View {
    @Binding var models: [String]
    @Binding var selected: String
    let serverURL: String
    let client: OllamaClient
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Fetching models…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView(error, systemImage: "wifi.slash")
                } else if models.isEmpty {
                    ContentUnavailableView("No models found", systemImage: "cpu")
                } else {
                    List(models, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            if name == selected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.claudeAccent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selected = name
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task {
                            loading = true
                            defer { loading = false }
                            do { models = try await client.listModels(server: serverURL) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
