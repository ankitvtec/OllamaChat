import Foundation
import SwiftUI

/// Owns all conversations and persists them as JSON in the app's Documents folder.
@MainActor
final class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedID: UUID?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("conversations.json")
    }()

    init() {
        load()
    }

    var selected: Conversation? {
        conversations.first { $0.id == selectedID }
    }

    func newConversation(model: String) -> UUID {
        let conversation = Conversation(title: "New Chat", messages: [], model: model)
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        save()
        return conversation.id
    }

    func update(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index] = conversation
        save()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = conversations.first?.id
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = decoded
        selectedID = conversations.first?.id
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
